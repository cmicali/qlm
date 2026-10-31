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
    return QLMIsMonitorPoll(exchange.message) && exchange.answered;
}

// Every reply in `scenario` that reads as telemetry, by the address polled.
static NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *QLMReadTelemetryFrames(NSString *scenario) {
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

// QLMReadTelemetryFrames, read once per scenario and shared.
static NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *QLMTelemetryFrames(NSString *scenario) {
    static NSMutableDictionary<NSString *, NSDictionary *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSMutableDictionary dictionary];
    });
    @synchronized(cache) {
        if (cache[scenario] == nil) {
            cache[scenario] = QLMReadTelemetryFrames(scenario);
        }
        return cache[scenario];
    }
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
// brings the rest. In every capture, each of the 47 first parts and the
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
    XCTAssertEqual(splits, 47u);
}

// The time of a frame, less the seconds since the wake that 8A and 49 count
// together: 8A is the count over 256, and 49 the count mod 256.
static NSTimeInterval QLMWakeTime(QLMTelemetryFrame *frame) {
    return frame.time - (frame.telemetry.wakeSteps * 256 + frame.telemetry.wakeSeconds);
}

// sleep-wake-darkwake: 8A rides one frame in 30 s. One frame that carried it
// came split, at 395.43 s, so one gap is 60 s.
// It counts up by one at a time, from 2 to 4. With 49 it makes one count of
// seconds since the wake, so a step is 256 s. The wake time it gives holds
// within a second from one frame to the next, through both steps.
// startup-idle: GLM's first poll of each monitor carries the 8A no host read.
- (void)testWakeStepsEveryThirtySeconds {
    NSDictionary<NSNumber *, NSArray<QLMTelemetryFrame *> *> *frames = QLMTelemetryFrames(@"sleep-wake-darkwake");
    for (NSNumber *address in frames) {
        NSArray<QLMTelemetryFrame *> *steps = QLMWakeStepFrames(frames[address]);
        XCTAssertGreaterThanOrEqual(steps.count, 19u, @"%@", address);
        XCTAssertEqual(steps.firstObject.telemetry.wakeSteps, 2, @"%@", address);
        XCTAssertEqual(steps.lastObject.telemetry.wakeSteps, 4, @"%@", address);
        for (NSUInteger i = 1; i < steps.count; i++) {
            NSTimeInterval elapsed = steps[i].time - steps[i - 1].time;
            NSInteger step = steps[i].telemetry.wakeSteps - steps[i - 1].telemetry.wakeSteps;
            XCTAssertTrue(fabs(elapsed - 30) < 1.5 || fabs(elapsed - 60) < 1.5, @"%@ at %.2f", address, steps[i].time);
            XCTAssertTrue(step == 0 || step == 1, @"%@ at %.2f", address, steps[i].time);
            XCTAssertEqualWithAccuracy(QLMWakeTime(steps[i]), QLMWakeTime(steps[i - 1]), 1, @"%@ at %.2f", address, steps[i].time);
        }
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

// The frames in `run` from `from` to `to`.
static NSArray<QLMTelemetryFrame *> *QLMFramesBetween(NSArray<QLMTelemetryFrame *> *run, NSTimeInterval from, NSTimeInterval to) {
    return [run filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(QLMTelemetryFrame *frame, NSDictionary *bindings) {
        return frame.time >= from && frame.time <= to;
    }]];
}

// The session the first lease after `time` gave the hardware ID, or 0.
static uint8_t QLMSessionLeased(NSString *scenario, const uint8_t hardwareID[3], NSTimeInterval time) {
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (exchange.time > time && QLMIsLease(message) && memcmp(message.payload + 1, hardwareID, 3) == 0) {
            return message.payload[4];
        }
    }
    return 0;
}

// qlm-control-all: the Rear Right 8330A was switched on at its power switch
// and answered the probe at 214.755 s. Its first frame, at 215.94 s, reads
// 49 at 1, and 8A reads 0 at 225.05 and 254.68 s. So a power-on starts the
// count from 0, as a wake does.
- (void)testAPowerOnStartsTheWakeCount {
    NSArray<QLMTelemetryFrame *> *run = QLMFramesBetween(QLMTelemetryFrames(@"qlm-control-all")[@0x07], 214.7, 283);
    XCTAssertEqualWithAccuracy(run.firstObject.time, 215.941, 0.001);
    XCTAssertEqual(run.firstObject.telemetry.wakeSeconds, 1);
    NSArray<QLMTelemetryFrame *> *steps = QLMWakeStepFrames(run);
    XCTAssertEqual(steps.count, 2u);
    for (QLMTelemetryFrame *frame in steps) {
        XCTAssertEqual(frame.telemetry.wakeSteps, 0, @"%.3f", frame.time);
        XCTAssertEqualWithAccuracy(QLMWakeTime(frame), 214.9, 0.5, @"%.3f", frame.time);
    }
}

// In every whole frame from a monitor that is on, the system info's c- is
// the number of 81, 82, and 83 readings: 1 for the subwoofers, 2 for the
// 8330A, and 3 for the 8351B. The adapter's is 0.
- (void)testTheSystemInfosCCountsThe81To83Readings {
    NSUInteger frames = 0;
    for (NSString *scenario in QLMCaptureScenarios()) {
        NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            QLMMessage message = exchange.message;
            QLMMessage reply = exchange.reply;
            NSNumber *address = @(message.address);
            char text[QLMPayloadMax];
            if (exchange.answered && message.payload[0] == 0x39 && QLMReplyText(&reply, text, sizeof text)) {
                XCTAssertEqual(strncmp(text, "c-", 2), 0, @"%@ at %.3f", scenario, exchange.time);
                counts[address] = @(text[2] - '0');
                if (message.address == QLMAddressAdapter) {
                    XCTAssertEqual(text[2], '0', @"%@ at %.3f", scenario, exchange.time);
                }
                continue;
            }
            QLMTelemetry t;
            if (!QLMIsAnsweredPoll(exchange) || counts[address] == nil || QLMReplyTelemetry(&reply, &t) != QLMTelemetryOK || t.status != 0x01) {
                continue;
            }
            NSInteger readings = (t.sensor81 != QLMTelemetryAbsent) + (t.sensor82 != QLMTelemetryAbsent) + (t.sensor83 != QLMTelemetryAbsent);
            XCTAssertEqual(readings, counts[address].integerValue, @"%@ at %.3f", scenario, exchange.time);
            frames += 1;
        }
    }
    XCTAssertGreaterThan(frames, 10000u);
}

// A woken monitor doesn't wait for its mute state. Each run sent no 2B after
// its wake. In qlm-control-all and qlm-app-first, the wake ended with the
// level and the pair, and the Rear Right 8330A's HF meter left its floor
// 3.4 and 3.6 s after the first wake pair, with music in. In
// qlm-control-first, `wake` sent nothing but the pairs, and the Right 8351B,
// which played before its standby, read its floor in every output for 12 s
// though its input read the music.
- (void)testAWokenMonitorWaitsForALevelNotItsMute {
    const uint8_t rearRight[] = {0x12, 0x2F, 0xAB};
    const uint8_t right8351B[] = {0x11, 0x4B, 0xEA};
    struct {
        NSString *scenario;
        const uint8_t *hardwareID;
        NSTimeInterval wake;
        NSTimeInterval end;
        NSTimeInterval plays;
    } wakes[] = {
        {@"qlm-control-all", rearRight, 8481.939, 8486.5, 8485.336},
        {@"qlm-app-first", rearRight, 1232.644, 1237, 1236.198},
        {@"qlm-control-first", right8351B, 827.791, 840.0, 0},
    };
    for (size_t i = 0; i < sizeof wakes / sizeof wakes[0]; i++) {
        NSString *scenario = wakes[i].scenario;
        NSMutableSet<NSNumber *> *sent = [NSMutableSet set];
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            if (exchange.time >= wakes[i].end) {
                break;
            }
            QLMMessage message = exchange.message;
            if (exchange.time >= wakes[i].wake && QLMIsControl(message)) {
                [sent addObject:@(message.payload[0])];
            }
        }
        XCTAssertFalse([sent containsObject:@0x2B], @"%@", scenario);
        BOOL levelAndPair = wakes[i].plays > 0;
        XCTAssertEqual([sent containsObject:@0x1F], levelAndPair, @"%@", scenario);
        XCTAssertEqual([sent containsObject:@0x2D], levelAndPair, @"%@", scenario);

        uint8_t session = QLMSessionLeased(scenario, wakes[i].hardwareID, wakes[i].wake);
        NSArray<QLMTelemetryFrame *> *run = QLMFramesBetween(QLMTelemetryFrames(scenario)[@(session)], wakes[i].wake, wakes[i].end);
        XCTAssertGreaterThanOrEqual(run.count, 3u, @"%@", scenario);
        for (QLMTelemetryFrame *frame in run) {
            XCTAssertGreaterThan(frame.telemetry.inputMeter, 0xD0, @"%@ at %.3f", scenario, frame.time);
            if (levelAndPair && frame.time > wakes[i].plays - 0.001) {
                XCTAssertGreaterThan(frame.telemetry.hfMeter, QLMTelemetryOutputSilent + 40, @"%@ at %.3f", scenario, frame.time);
                continue;
            }
            XCTAssertEqual(frame.telemetry.hfMeter, QLMTelemetryOutputSilent, @"%@ at %.3f", scenario, frame.time);
            XCTAssertEqual(frame.telemetry.lfMeter, QLMTelemetryOutputSilent, @"%@ at %.3f", scenario, frame.time);
        }
        if (levelAndPair) {
            [self telemetryIn:run at:wakes[i].plays];
        }
    }
}

// qlm-control-all: the bare 04 comes only from the two monitors whose counts
// restarted minutes before: the Rear Right 8330A at 02, switched on at its
// power switch at 214.8 s, and the other 8330A at 04, whose count restarted
// at about 175 s for no reason the notes give. Each ends its first frame
// after GLM's apply at launch with 8A 00 00 and 04. By 49, they restarted
// 166 and 206 s before. By 8A, the other four woke 81 minutes before, and
// their frames in the same round end 8A 00 13.
- (void)testTheBare04ComesFromTheMonitorsJustStarted {
    NSArray<QLMCaptureExchange *> *round = [self qlm_frames:6 of:@"qlm-control-all" from:381.148658 keep:QLMIsMonitorPoll];
    if (round == nil) {
        return;
    }
    for (QLMCaptureExchange *exchange in round) {
        QLMMessage message = exchange.message;
        QLMMessage reply = exchange.reply;
        QLMTelemetry t;
        QLMTelemetryStatus status = QLMReplyTelemetry(&reply, &t);
        XCTAssertTrue(t.busy, @"%.6f s", exchange.time);
        if (message.address == 0x02 || message.address == 0x04) {
            XCTAssertEqual(status, QLMTelemetryErrorUnknownTag, @"%.6f s", exchange.time);
            XCTAssertEqual(t.unknownTag, 0x04, @"%.6f s", exchange.time);
            XCTAssertEqual(t.wakeSteps, 0, @"%.6f s", exchange.time);
            XCTAssertEqual(t.wakeSeconds, message.address == 0x02 ? 166 : 206, @"%.6f s", exchange.time);
        } else {
            XCTAssertEqual(status, QLMTelemetryOK, @"%.6f s", exchange.time);
            XCTAssertEqual(t.wakeSteps, 0x13, @"%.6f s", exchange.time);
        }
    }
}

@end
