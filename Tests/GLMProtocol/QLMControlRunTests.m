#import "QLMTestSupport.h"

#include <math.h>

#include "QLMCommands.h"
#include "QLMReport.h"

// Sources: captures/qlm-control-first, qlm's first control run on the
// monitors, and its notes.md. GLM's last report there is at 17.45 s, so every
// frame from 30 s on is qlm's. Each control frame qlm sent is checked against
// GLM's: each level against volume-sweep, mute against mute-dim, the knob's
// burst against knob-sweep, and the power steps against standby-wake.
@interface QLMControlRunTests : XCTestCase
@end

@implementation QLMControlRunTests

static const NSTimeInterval QLMRunStart = 30;
static const double QLMRunCeiling = -35;

static BOOL QLMIsControl(QLMMessage message) {
    if (message.address == QLMAddressMulticast || message.length == 0) {
        return NO;
    }
    switch (message.payload[0]) {
    case 0x08:  // a poll
    case 0x19:  // a serial
    case 0x39:  // system info
    case 0xFE:  // the probe
        return NO;
    default:
        return YES;
    }
}

// The control frames qlm sent, in order.
static NSArray<QLMCaptureExchange *> *QLMRunControls(void) {
    NSMutableArray<QLMCaptureExchange *> *controls = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"qlm-control-first", NULL).exchanges) {
        if (exchange.time >= QLMRunStart && QLMIsControl(exchange.message)) {
            [controls addObject:exchange];
        }
    }
    return controls;
}

// `count` control frames of `scenario`, from the one at `time` to the half
// millisecond. Nil, after a failure, when there are fewer.
- (nullable NSArray<QLMCaptureExchange *> *)controls:(NSUInteger)count of:(NSString *)scenario from:(NSTimeInterval)time {
    NSMutableArray<QLMCaptureExchange *> *run = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        if (run.count == 0 && fabs(exchange.time - time) >= 0.0005) {
            continue;
        }
        if (!QLMIsControl(exchange.message)) {
            continue;
        }
        [run addObject:exchange];
        if (run.count == count) {
            return run;
        }
    }
    XCTFail(@"%@ has %lu of %lu control frames from %.6f s", scenario, (unsigned long)run.count, (unsigned long)count, time);
    return nil;
}

- (void)assertExchange:(QLMCaptureExchange *)exchange is:(QLMMessage)message {
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&message, report), QLMReportOK, @"%.6f s", exchange.time);
    XCTAssertEqualObjects(exchange.outputReport, QLMBytes(report, sizeof report), @"%.6f s", exchange.time);
}

- (void)assertExchange:(QLMCaptureExchange *)exchange isExchange:(QLMCaptureExchange *)glm {
    XCTAssertEqualObjects(exchange.outputReport, glm.outputReport, @"%.6f s against GLM's at %.6f s", exchange.time, glm.time);
}

static NSSet<NSData *> *QLMOutputReports(NSString *scenario, uint8_t opcode) {
    NSMutableSet<NSData *> *reports = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (message.length > 0 && message.payload[0] == opcode) {
            [reports addObject:exchange.outputReport];
        }
    }
    return reports;
}

// Every opcode qlm sent beyond discovery is a level, a mute, or a power step.
- (void)testTheRunSentOnlyControls {
    NSArray<QLMCaptureExchange *> *controls = QLMRunControls();
    XCTAssertEqual(controls.count, 585u);
    for (QLMCaptureExchange *exchange in controls) {
        uint8_t opcode = exchange.message.payload[0];
        XCTAssertTrue(opcode == 0x1F || opcode == 0x2B || opcode == 0x3A, @"%02X at %.6f s", opcode, exchange.time);
    }
}

// Each level is a report GLM sent in volume-sweep, byte for byte, and none
// passed the run's -35 dB ceiling. The run's levels went from -41.5 to
// -67 dB as the knob turned.
- (void)testEveryLevelIsGLMsAndUnderTheCeiling {
    NSSet<NSData *> *glm = QLMOutputReports(@"volume-sweep", 0x1F);
    XCTAssertGreaterThanOrEqual(glm.count, 200u);
    NSMutableSet<NSData *> *levels = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMRunControls()) {
        QLMMessage message = exchange.message;
        if (message.address != QLMAddressBroadcast || message.length != 4 || message.payload[0] != 0x1F) {
            continue;
        }
        uint32_t word = (uint32_t)message.payload[1] << 16 | (uint32_t)message.payload[2] << 8 | message.payload[3];
        [levels addObject:exchange.outputReport];
        XCTAssertTrue([glm containsObject:exchange.outputReport], @"%.6f s", exchange.time);
        XCTAssertLessThanOrEqual(QLMVolumeDecibelsForWord(word), QLMRunCeiling + 0.01, @"%.6f s", exchange.time);
    }
    XCTAssertEqual(levels.count, 37u);
}

// The volume runs, 180.16 and 274.76 s: -45 and -60 dB, every cycle.
- (void)testTheVolumeRunsAreGLMsLevels {
    NSArray<QLMCaptureExchange *> *minus45 = [self controls:27 of:@"qlm-control-first" from:180.157041];
    NSArray<QLMCaptureExchange *> *minus60 = [self controls:27 of:@"qlm-control-first" from:274.758405];
    for (QLMCaptureExchange *exchange in minus45) {
        [self assertExchange:exchange is:QLMCommandVolume(-45, QLMRunCeiling)];
    }
    for (QLMCaptureExchange *exchange in minus60) {
        [self assertExchange:exchange is:QLMCommandVolume(-60, QLMRunCeiling)];
    }
}

// The knob's first turn, 373.12 s: the level three times, `2B 00` to the
// adapter, two rounds of 2B to every monitor, then the level again. GLM's
// first turn in knob-sweep, 19.24 s, has the same shape and the same level,
// -41.5 dB. GLM sends 2B 05 and 2B 07 to monitors outside its group, and
// qlm sends each 2B 04 (docs/plan.md).
- (void)testTheKnobsBurstIsGLMs {
    NSArray<QLMCaptureExchange *> *qlm = [self controls:11 of:@"qlm-control-first" from:373.115781];
    NSArray<QLMCaptureExchange *> *glm = [self controls:20 of:@"knob-sweep" from:19.241470];
    if (qlm == nil || glm == nil) {
        return;
    }
    NSArray<QLMCaptureExchange *> *glmLevels = @[glm[0], glm[1], glm[2], glm[19]];
    NSArray<QLMCaptureExchange *> *qlmLevels = @[qlm[0], qlm[1], qlm[2], qlm[10]];
    for (NSUInteger i = 0; i < glmLevels.count; i++) {
        [self assertExchange:qlmLevels[i] isExchange:glmLevels[0]];
        [self assertExchange:glmLevels[i] isExchange:glmLevels[0]];
    }
    [self assertExchange:qlm[3] isExchange:glm[3]];
    [self assertExchange:qlm[3] is:QLMCommandMute(QLMAddressReply, QLMMuteValueAdapterUnmuted)];
    const uint8_t sessions[] = {0x02, 0x03, 0x04};
    for (NSUInteger round = 0; round < 2; round++) {
        for (size_t i = 0; i < sizeof sessions; i++) {
            [self assertExchange:qlm[4 + round * 3 + i] is:QLMCommandMute(sessions[i], QLMMuteValueUnmuted)];
        }
    }
}

// Dim, 538.34 s: -63.5 dB, 20 dB under the -43.5 dB that dim off restores
// at 558.04 s. mute-dim's dim is 20 dB under too: -76.5 from -56.5 dB, at
// 51.24 s. qlmctl's dim sent only the level. GLM's also sends one round of
// 2B, then 2D 00 and 3D 00 00 (notes.md).
- (void)testDimIsGLMsDrop {
    NSArray<QLMCaptureExchange *> *on = [self controls:18 of:@"qlm-control-first" from:538.342925];
    NSArray<QLMCaptureExchange *> *off = [self controls:9 of:@"qlm-control-first" from:558.041752];
    NSArray<QLMCaptureExchange *> *glm = [self controls:1 of:@"mute-dim" from:51.240592];
    if (on == nil || off == nil || glm == nil) {
        return;
    }
    for (QLMCaptureExchange *exchange in on) {
        [self assertExchange:exchange is:QLMCommandDim(-43.5, QLMRunCeiling)];
        [self assertExchange:exchange is:QLMCommandVolume(-63.5, QLMRunCeiling)];
    }
    for (QLMCaptureExchange *exchange in off) {
        [self assertExchange:exchange is:QLMCommandVolume(-43.5, QLMRunCeiling)];
    }
    [self assertExchange:glm[0] is:QLMCommandDim(-56.5, 0)];
    [self assertExchange:glm[0] is:QLMCommandVolume(-76.5, 0)];
}

// Muting the Right 8351B at 04, 638.71 s, and unmuting it, 660.48 s: two
// rounds of 2B to every monitor, 03 to it and 04 to the rest, as GLM mutes
// one monitor in mute-dim. Each 2B payload qlm sent is one GLM sent there.
- (void)testMuteIsGLMs {
    NSArray<QLMCaptureExchange *> *mute = [self controls:6 of:@"qlm-control-first" from:638.707664];
    NSArray<QLMCaptureExchange *> *unmute = [self controls:6 of:@"qlm-control-first" from:660.482687];
    if (mute == nil || unmute == nil) {
        return;
    }
    const uint8_t sessions[] = {0x02, 0x03, 0x04};
    for (NSUInteger round = 0; round < 2; round++) {
        for (size_t i = 0; i < sizeof sessions; i++) {
            uint8_t value = sessions[i] == 0x04 ? QLMMuteValueMuted : QLMMuteValueUnmuted;
            [self assertExchange:mute[round * 3 + i] is:QLMCommandMute(sessions[i], value)];
            [self assertExchange:unmute[round * 3 + i] is:QLMCommandMute(sessions[i], QLMMuteValueUnmuted)];
        }
    }

    NSMutableSet<NSData *> *glm = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"mute-dim", NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (message.length == 2 && message.payload[0] == 0x2B) {
            [glm addObject:[NSData dataWithBytes:message.payload length:2]];
        }
    }
    for (QLMCaptureExchange *exchange in QLMRunControls()) {
        QLMMessage message = exchange.message;
        if (message.payload[0] == 0x2B) {
            XCTAssertEqual(message.length, 2u);
            XCTAssertTrue([glm containsObject:[NSData dataWithBytes:message.payload length:2]], @"%.6f s", exchange.time);
        }
    }
}

// Standby, 816.94 s, and wake, 827.79 s: the same broadcasts as GLM's in
// standby-wake, at 34.86 and 46.57 s.
- (void)testPowerIsGLMs {
    NSArray<QLMCaptureExchange *> *standby = [self controls:4 of:@"qlm-control-first" from:816.942152];
    NSArray<QLMCaptureExchange *> *glmStandby = [self controls:4 of:@"standby-wake" from:34.855835];
    NSArray<QLMCaptureExchange *> *wake = [self controls:6 of:@"qlm-control-first" from:827.791994];
    if (standby == nil || glmStandby == nil || wake == nil) {
        return;
    }
    for (NSUInteger i = 0; i < 4; i++) {
        [self assertExchange:standby[i] isExchange:glmStandby[i]];
    }
    NSArray<NSNumber *> *pairs = @[@46.565318, @46.806259, @47.008166];
    for (NSUInteger pair = 0; pair < pairs.count; pair++) {
        NSArray<QLMCaptureExchange *> *glm = [self controls:2 of:@"standby-wake" from:pairs[pair].doubleValue];
        if (glm == nil) {
            continue;
        }
        [self assertExchange:wake[pair * 2] isExchange:glm[0]];
        [self assertExchange:wake[pair * 2 + 1] isExchange:glm[1]];
    }
}

@end
