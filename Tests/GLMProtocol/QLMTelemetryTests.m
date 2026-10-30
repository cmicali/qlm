#import "QLMTestSupport.h"

#include <math.h>

#include "QLMReplies.h"

// Sources: the captures, GLM 5 and qlm talking to the user's six monitors,
// with each scenario's notes.md. docs/telemetry.md has the evidence for each
// tag. A time is seconds into the capture's reports.txt, at the poll.
@interface QLMTelemetryTests : XCTestCase
@end

@interface QLMTelemetryFrame : NSObject
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) QLMTelemetry telemetry;
@end

@implementation QLMTelemetryFrame
@end

@implementation QLMTelemetryTests

// Every reply in `scenario` that reads as telemetry, by the address polled.
static NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *QLMTelemetryFrames(NSString *scenario) {
    NSMutableDictionary<NSNumber *, NSMutableArray<QLMTelemetryFrame *> *> *frames = [NSMutableDictionary dictionary];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        QLMMessage reply = exchange.reply;
        QLMTelemetry telemetry;
        if (!QLMAddressIsLeasable(message.address) || message.payload[0] != 0x08 || !exchange.answered ||
            QLMReplyTelemetry(&reply, &telemetry) != QLMTelemetryOK) {
            continue;
        }
        QLMTelemetryFrame *frame = [QLMTelemetryFrame new];
        frame.time = exchange.time;
        frame.telemetry = telemetry;
        NSNumber *address = @(message.address);
        if (frames[address] == nil) {
            frames[address] = [NSMutableArray array];
        }
        [frames[address] addObject:frame];
    }
    return frames;
}

// The telemetry that answered the poll to `address` at `time`.
- (QLMTelemetry)telemetryIn:(NSString *)scenario from:(uint8_t)address at:(NSTimeInterval)time {
    for (QLMTelemetryFrame *frame in QLMTelemetryFrames(scenario)[@(address)]) {
        if (fabs(frame.time - time) < 0.005) {
            return frame.telemetry;
        }
    }
    XCTFail(@"%@: no telemetry from %02X at %.3f", scenario, address, time);
    QLMTelemetry none;
    memset(&none, 0, sizeof none);
    return none;
}

// 49 advances by one a second, mod 256.
static NSInteger QLMWakeSecondsAdvance(QLMTelemetry from, QLMTelemetry to) {
    return (to.wakeSeconds - from.wakeSeconds + 256) % 256;
}

// qlm-control-first, 829.40 s: the Right 8351B's first frame after qlm's
// wake. The three-way model sends 44, 82, 88, and 89, and the wake restarts
// 49. 81, 82, and 83 start apart after a wake.
- (void)testTheThreeWayFrame {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x17, 0x81, 0x00, 0x21, 0x82, 0x00, 0x28, 0x83, 0x00, 0x29,
                                        0x42, 0xE7, 0x43, 0x80, 0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x49, 0x01, 0x88, 0x00, 0x4F,
                                        0x89, 0x00, 0x43, 0x84, 0x02, 0xEF);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&message, &t), QLMTelemetryOK);
    XCTAssertEqual(t.temperature, 0x17);
    XCTAssertEqual(t.sensor81, 0x21);
    XCTAssertEqual(t.sensor82, 0x28);
    XCTAssertEqual(t.sensor83, 0x29);
    XCTAssertEqual(t.midMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(t.wakeSeconds, 1);
    XCTAssertEqual(t.wakeSteps, QLMTelemetryAbsent);
    XCTAssertEqual(t.deviceClass, QLMTelemetryClassTwoWay);
    XCTAssertEqual(t.unknownTag, 0);
}

// startup-idle, 9.87 s: GLM's first poll of the Left 8351B. 8A is big-endian.
- (void)testWakeStepsAreBigEndian {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x07, 0x41, 0x2A, 0x81, 0x00, 0x2A, 0x82, 0x00, 0x2A, 0x83, 0x00,
                                        0x2A, 0x42, 0x9E, 0x43, 0x80, 0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x49, 0xEE, 0x88, 0x00,
                                        0x4B, 0x89, 0x00, 0x41, 0x84, 0x02, 0xFB, 0x8A, 0x13, 0x05);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&message, &t), QLMTelemetryOK);
    XCTAssertTrue(t.busy);
    XCTAssertEqual(t.wakeSeconds, 0xEE);
    XCTAssertEqual(t.wakeSteps, 0x1305);
    XCTAssertEqual(t.unknownTag, 0);
}

// sleep-wake-darkwake: GLM polls all six for 600 s. Each frame is a second
// newer than the last one GLM read, or more, and never the same one twice.
// qlm-standby-discover: no one polls the six in standby from 40 to 250 s,
// and 49 keeps counting.
- (void)testWakeSecondsCountOnceASecond {
    NSUInteger pairs = 0;
    NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *frames = QLMTelemetryFrames(@"sleep-wake-darkwake");
    XCTAssertEqual(frames.count, 6u);
    for (NSNumber *address in frames) {
        NSArray<QLMTelemetryFrame *> *run = frames[address];
        for (NSUInteger i = 1; i < run.count; i++) {
            NSInteger advance = QLMWakeSecondsAdvance(run[i - 1].telemetry, run[i].telemetry);
            NSTimeInterval elapsed = run[i].time - run[i - 1].time;
            XCTAssertGreaterThan(advance, 0, @"%@ at %.2f", address, run[i].time);
            XCTAssertLessThanOrEqual(fabs(advance - elapsed), 1.0, @"%@ at %.2f", address, run[i].time);
            pairs += 1;
        }
    }
    XCTAssertGreaterThan(pairs, 3500u);

    NSUInteger gaps = 0;
    frames = QLMTelemetryFrames(@"qlm-standby-discover");
    for (NSNumber *address in frames) {
        NSArray<QLMTelemetryFrame *> *run = frames[address];
        for (NSUInteger i = 1; i < run.count; i++) {
            NSTimeInterval elapsed = run[i].time - run[i - 1].time;
            if (elapsed > 200 && elapsed < 256) {
                XCTAssertNotEqual(run[i].telemetry.status, QLMTelemetryStatusOn);
                XCTAssertLessThanOrEqual(fabs(QLMWakeSecondsAdvance(run[i - 1].telemetry, run[i].telemetry) - elapsed), 0.03 * elapsed);
                gaps += 1;
            }
        }
    }
    XCTAssertEqual(gaps, 6u);
}

// standby-wake: the Left 8351B, at 03, counts on through standby at 34.9 s.
// GLM wakes the six at 46.0 s and leases them 12 to 17 at 47.4 s. Each one's
// first frame, at 49.0 s, has 49 back at 1 or 2, and its first 8A reads 0.
- (void)testAWakeRestartsTheClocks {
    NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *frames = QLMTelemetryFrames(@"standby-wake");
    NSArray<QLMTelemetryFrame *> *left = frames[@0x03];
    XCTAssertEqual(left.firstObject.telemetry.status, QLMTelemetryStatusOn);
    XCTAssertEqual(left.lastObject.telemetry.status, QLMTelemetryStatusStandby);
    XCTAssertEqualWithAccuracy(QLMWakeSecondsAdvance(left.firstObject.telemetry, left.lastObject.telemetry),
                               left.lastObject.time - left.firstObject.time, 1.0);

    for (uint8_t address = 0x12; address <= 0x17; address++) {
        NSArray<QLMTelemetryFrame *> *run = frames[@(address)];
        XCTAssertEqualWithAccuracy(run.firstObject.time, 49.05, 0.05, @"%02X", address);
        XCTAssertLessThanOrEqual(run.firstObject.telemetry.wakeSeconds, 2, @"%02X", address);
        XCTAssertGreaterThanOrEqual(run.firstObject.telemetry.wakeSeconds, 1, @"%02X", address);
        NSUInteger index = [run indexOfObjectPassingTest:^BOOL(QLMTelemetryFrame *frame, NSUInteger i, BOOL *stop) {
            return frame.telemetry.wakeSteps != QLMTelemetryAbsent;
        }];
        XCTAssertNotEqual(index, NSNotFound, @"%02X", address);
        if (index != NSNotFound) {
            XCTAssertEqual(run[index].telemetry.wakeSteps, 0, @"%02X", address);
        }
    }
}

// sleep-wake-darkwake: the Left 8351B, at 15, splits a frame at 313.28 s.
// The first part is the temperature alone. The next poll, at 313.88 s,
// brings the rest. In every capture, each of the 21 first parts is followed
// by its second part, at that monitor's next poll, and no second part comes
// without one.
- (void)testASplitFrame {
    QLMMessage head = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x2A);
    QLMMessage tail = QLMMakeMessage(QLMAddressReply, 0x09, 0x81, 0x00, 0x2A, 0x82, 0x00, 0x2A, 0x83, 0x00, 0x2A, 0x42, 0x9F,
                                     0x43, 0x80, 0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x49, 0x73, 0x88, 0x00, 0x4B, 0x89, 0x00,
                                     0x41, 0x84, 0x02, 0xF1);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&head, &t), QLMTelemetryErrorPartial);
    XCTAssertEqual(t.temperature, 0x2A);
    XCTAssertEqual(t.status, QLMTelemetryAbsent);
    XCTAssertEqual(QLMReplyTelemetry(&tail, &t), QLMTelemetryErrorNotTelemetry);

    NSUInteger heads = 0;
    for (NSString *scenario in QLMCaptureScenarios()) {
        NSMutableSet<NSNumber *> *waiting = [NSMutableSet set];
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            QLMMessage message = exchange.message;
            if (!QLMAddressIsLeasable(message.address) || message.payload[0] != 0x08 || !exchange.answered) {
                continue;
            }
            QLMMessage reply = exchange.reply;
            QLMTelemetryStatus status = QLMReplyTelemetry(&reply, &t);
            NSNumber *address = @(message.address);
            // Longer than a bare 09 or a busy marker.
            BOOL second = status == QLMTelemetryErrorNotTelemetry && reply.length > 2;
            XCTAssertEqual(second, [waiting containsObject:address], @"%@ %@ at %.3f", scenario, address, exchange.time);
            [waiting removeObject:address];
            if (status == QLMTelemetryErrorPartial) {
                [waiting addObject:address];
                heads += 1;
            }
        }
    }
    XCTAssertEqual(heads, 21u);
}

// sleep-wake-darkwake: 8A rides one frame in 30 s. One frame that carried it
// came split, at 395.43 s, so one gap is 60 s.
// It counts up by one at a time, from 2 to 4, and 3 lasts 240 s.
// startup-idle: GLM's first poll of each monitor carries the 8A no host read.
- (void)testWakeStepsEveryThirtySeconds {
    NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *frames = QLMTelemetryFrames(@"sleep-wake-darkwake");
    for (NSNumber *address in frames) {
        NSMutableArray<QLMTelemetryFrame *> *steps = [NSMutableArray array];
        for (QLMTelemetryFrame *frame in frames[address]) {
            if (frame.telemetry.wakeSteps != QLMTelemetryAbsent) {
                [steps addObject:frame];
            }
        }
        XCTAssertGreaterThanOrEqual(steps.count, 19u, @"%@", address);
        XCTAssertEqual(steps.firstObject.telemetry.wakeSteps, 2, @"%@", address);
        XCTAssertEqual(steps.lastObject.telemetry.wakeSteps, 4, @"%@", address);
        NSTimeInterval three = 0;
        NSTimeInterval four = 0;
        for (NSUInteger i = 1; i < steps.count; i++) {
            NSTimeInterval elapsed = steps[i].time - steps[i - 1].time;
            NSInteger step = steps[i].telemetry.wakeSteps - steps[i - 1].telemetry.wakeSteps;
            XCTAssertTrue(fabs(elapsed - 30) < 1.5 || fabs(elapsed - 60) < 1.5, @"%@ at %.2f", address, steps[i].time);
            XCTAssertTrue(step == 0 || step == 1, @"%@ at %.2f", address, steps[i].time);
            if (step == 1 && steps[i].telemetry.wakeSteps == 3) {
                three = steps[i].time;
            } else if (step == 1 && steps[i].telemetry.wakeSteps == 4) {
                four = steps[i].time;
            }
        }
        XCTAssertEqualWithAccuracy(four - three, 240, 2, @"%@", address);
    }

    frames = QLMTelemetryFrames(@"startup-idle");
    XCTAssertEqual(frames.count, 6u);
    for (NSNumber *address in frames) {
        XCTAssertEqualWithAccuracy(frames[address].firstObject.time, 9.9, 0.1, @"%@", address);
        XCTAssertNotEqual(frames[address].firstObject.telemetry.wakeSteps, QLMTelemetryAbsent, @"%@", address);
    }
}

// qlm-control-first, the Right 8351B at 04 with music playing. qlm sends
// -60 dB at 274.76 s, over the knob's -40 dB. It dims from the knob's
// -43.3 dB to -63.5 dB at 538.34 s, and mutes it at 638.71 s. Each output
// meter falls about a count per dB, and to its floor on mute. The input
// meter does not move.
- (void)testTheMetersReadOneCountPerDB {
    NSString *run = @"qlm-control-first";
    QLMTelemetry before = [self telemetryIn:run from:0x04 at:274.744];
    QLMTelemetry after = [self telemetryIn:run from:0x04 at:279.294];
    XCTAssertEqualWithAccuracy(before.hfMeter - after.hfMeter, 20, 1);
    XCTAssertEqualWithAccuracy(before.midMeter - after.midMeter, 20, 1);
    XCTAssertEqualWithAccuracy(before.lfMeter - after.lfMeter, 20, 1);
    XCTAssertEqual(before.inputMeter, after.inputMeter);

    before = [self telemetryIn:run from:0x04 at:538.330];
    after = [self telemetryIn:run from:0x04 at:541.180];
    XCTAssertEqualWithAccuracy(before.hfMeter - after.hfMeter, 20, 2);
    XCTAssertEqualWithAccuracy(before.midMeter - after.midMeter, 20, 2);
    XCTAssertEqualWithAccuracy(before.lfMeter - after.lfMeter, 20, 2);
    XCTAssertEqual(before.inputMeter, after.inputMeter);

    before = [self telemetryIn:run from:0x04 at:639.271];
    after = [self telemetryIn:run from:0x04 at:640.366];
    XCTAssertGreaterThan(before.hfMeter, QLMTelemetryOutputSilent + 40);
    XCTAssertEqual(after.hfMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(after.midMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(after.lfMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(before.inputMeter, after.inputMeter);
}

@end
