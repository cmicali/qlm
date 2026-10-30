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

// A monitor's 08 poll, answered.
static BOOL QLMIsAnsweredPoll(QLMCaptureExchange *exchange) {
    QLMMessage message = exchange.message;
    return QLMAddressIsLeasable(message.address) && message.payload[0] == 0x08 && exchange.answered;
}

// Every reply in `scenario` that reads as telemetry, by the address polled.
static NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *QLMTelemetryFrames(NSString *scenario) {
    NSMutableDictionary<NSNumber *, NSMutableArray<QLMTelemetryFrame *> *> *frames = [NSMutableDictionary dictionary];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        if (!QLMIsAnsweredPoll(exchange)) {
            continue;
        }
        QLMMessage reply = exchange.reply;
        QLMTelemetry telemetry;
        if (QLMReplyTelemetry(&reply, &telemetry) != QLMTelemetryOK) {
            continue;
        }
        QLMTelemetryFrame *frame = [QLMTelemetryFrame new];
        frame.time = exchange.time;
        frame.telemetry = telemetry;
        NSNumber *address = @(exchange.message.address);
        if (frames[address] == nil) {
            frames[address] = [NSMutableArray array];
        }
        [frames[address] addObject:frame];
    }
    return frames;
}

// The frames in `run` that carry 8A.
static NSArray<QLMTelemetryFrame *> *QLMWakeStepFrames(NSArray<QLMTelemetryFrame *> *run) {
    return [run filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(QLMTelemetryFrame *frame, NSDictionary *bindings) {
        return frame.telemetry.wakeSteps != QLMTelemetryAbsent;
    }]];
}

// 49 advances by one a second, mod 256.
static NSInteger QLMWakeSecondsAdvance(QLMTelemetry from, QLMTelemetry to) {
    return (to.wakeSeconds - from.wakeSeconds + 256) % 256;
}

// A split frame's two parts as one: the first, then the second after its 09.
static QLMMessage QLMJoinedFrame(QLMMessage first, QLMMessage second) {
    uint8_t payload[QLMPayloadMax];
    memcpy(payload, first.payload, first.length);
    size_t rest = MIN(second.length - 1, sizeof payload - first.length);
    memcpy(payload + first.length, second.payload + 1, rest);
    return QLMMessageMake(first.address, payload, first.length + rest);
}

// The frame in `run` from the poll at `time`.
- (QLMTelemetry)telemetryIn:(NSArray<QLMTelemetryFrame *> *)run at:(NSTimeInterval)time {
    for (QLMTelemetryFrame *frame in run) {
        if (fabs(frame.time - time) < 0.005) {
            return frame.telemetry;
        }
    }
    XCTFail(@"no telemetry at %.3f", time);
    return (QLMTelemetry){0};
}

// From the poll at `before` to the one at `after`, each output meter falls
// 20 counts, give or take `accuracy`, and the input meter holds.
- (void)assertOutputsIn:(NSArray<QLMTelemetryFrame *> *)run fallFrom:(NSTimeInterval)before to:(NSTimeInterval)after within:(double)accuracy {
    QLMTelemetry from = [self telemetryIn:run at:before];
    QLMTelemetry to = [self telemetryIn:run at:after];
    XCTAssertEqualWithAccuracy(from.hfMeter - to.hfMeter, 20, accuracy, @"%.3f", after);
    XCTAssertEqualWithAccuracy(from.midMeter - to.midMeter, 20, accuracy, @"%.3f", after);
    XCTAssertEqualWithAccuracy(from.lfMeter - to.lfMeter, 20, accuracy, @"%.3f", after);
    XCTAssertEqual(from.inputMeter, to.inputMeter, @"%.3f", after);
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
            XCTAssertEqualWithAccuracy(advance, elapsed, 1.0, @"%@ at %.2f", address, run[i].time);
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
                XCTAssertEqualWithAccuracy(QLMWakeSecondsAdvance(run[i - 1].telemetry, run[i].telemetry), elapsed, 0.03 * elapsed);
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
        NSArray<QLMTelemetryFrame *> *steps = QLMWakeStepFrames(run);
        XCTAssertEqual(steps.count > 0 ? steps[0].telemetry.wakeSteps : QLMTelemetryAbsent, 0, @"%02X", address);
    }
}

// sleep-wake-darkwake: the Left 8351B, at 15, splits a frame at 313.28 s.
// The first part is the temperature alone. The next poll, at 313.88 s,
// brings the rest. In every capture, each of the 25 first parts and the
// monitor's next reply make one whole frame, and no second part comes alone.
- (void)testASplitFrame {
    QLMMessage first = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x2A);
    QLMMessage second = QLMMakeMessage(QLMAddressReply, 0x09, 0x81, 0x00, 0x2A, 0x82, 0x00, 0x2A, 0x83, 0x00, 0x2A, 0x42, 0x9F,
                                       0x43, 0x80, 0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x49, 0x73, 0x88, 0x00, 0x4B, 0x89, 0x00,
                                       0x41, 0x84, 0x02, 0xF1);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&first, &t), QLMTelemetryErrorPartial);
    XCTAssertEqual(t.temperature, 0x2A);
    XCTAssertEqual(t.status, QLMTelemetryAbsent);
    XCTAssertEqual(QLMReplyTelemetry(&second, &t), QLMTelemetryErrorNotTelemetry);
    QLMMessage whole = QLMJoinedFrame(first, second);
    XCTAssertEqual(QLMReplyTelemetry(&whole, &t), QLMTelemetryOK);
    XCTAssertEqual(t.wakeSeconds, 0x73);

    NSUInteger splits = 0;
    for (NSString *scenario in QLMCaptureScenarios()) {
        QLMMessage firsts[256];
        bool waiting[256] = {false};
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            if (!QLMIsAnsweredPoll(exchange)) {
                continue;
            }
            uint8_t address = exchange.message.address;
            QLMMessage reply = exchange.reply;
            QLMTelemetryStatus status = QLMReplyTelemetry(&reply, &t);
            if (waiting[address]) {
                whole = QLMJoinedFrame(firsts[address], reply);
                XCTAssertEqual(QLMReplyTelemetry(&whole, &t), QLMTelemetryOK, @"%@ %02X at %.3f", scenario, address, exchange.time);
                XCTAssertEqual(t.unknownTag, 0, @"%@ %02X at %.3f", scenario, address, exchange.time);
                splits += 1;
            } else {
                // Longer than a bare 09 or a busy marker.
                XCTAssertFalse(status == QLMTelemetryErrorNotTelemetry && reply.length > 2, @"%@ %02X at %.3f", scenario, address,
                               exchange.time);
            }
            waiting[address] = status == QLMTelemetryErrorPartial;
            firsts[address] = reply;
        }
    }
    XCTAssertEqual(splits, 25u);
}

// sleep-wake-darkwake: 8A rides one frame in 30 s. One frame that carried it
// came split, at 395.43 s, so one gap is 60 s.
// It counts up by one at a time, from 2 to 4, and 3 lasts 240 s.
// startup-idle: GLM's first poll of each monitor carries the 8A no host read.
- (void)testWakeStepsEveryThirtySeconds {
    NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *frames = QLMTelemetryFrames(@"sleep-wake-darkwake");
    for (NSNumber *address in frames) {
        NSArray<QLMTelemetryFrame *> *steps = QLMWakeStepFrames(frames[address]);
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
    NSArray<QLMTelemetryFrame *> *right = QLMTelemetryFrames(@"qlm-control-first")[@0x04];
    [self assertOutputsIn:right fallFrom:274.744 to:279.294 within:1];
    [self assertOutputsIn:right fallFrom:538.330 to:541.180 within:2];

    QLMTelemetry unmuted = [self telemetryIn:right at:639.271];
    QLMTelemetry muted = [self telemetryIn:right at:640.366];
    XCTAssertGreaterThan(unmuted.hfMeter, QLMTelemetryOutputSilent + 40);
    XCTAssertEqual(muted.hfMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(muted.midMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(muted.lfMeter, QLMTelemetryOutputSilent);
    XCTAssertEqual(unmuted.inputMeter, muted.inputMeter);
}

@end
