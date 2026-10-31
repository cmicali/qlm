#import "QLMTestSupport.h"

#include "QLMCommands.h"

// Sources: captures/qlm-control-all, qlm's control run on all six monitors,
// and its notes.md. GLM sent every frame before 17.5 s and from 378.5 to
// 405.5 s, and qlm every other. The run checks the fixes from the first
// run: the level to a new or woken monitor, the end of a wake against
// standby-wake, and the whole of dim against mute-dim.
@interface QLMControlAllTests : XCTestCase
@end

@implementation QLMControlAllTests

static NSString *const QLMAllScenario = @"qlm-control-all";
static const double QLMAllVolume = -50;
static const double QLMAllCeiling = -35;

static BOOL QLMSentByQLM(NSTimeInterval time) {
    return time >= 17.5 && (time < 378.5 || time >= 405.5);
}

static QLMMessage QLMAllLevel(void) {
    return QLMCommandVolume(QLMAllVolume, QLMAllCeiling);
}

// Every frame qlm sent beyond discovery is a level, a mute, a power step,
// or the input pair. Each 3A is a power step, 3A 03. Each level is a report
// GLM sent in volume-sweep, under the run's -35 dB ceiling: -50 dB, -70 dB
// dimmed, and -41.5 dB in step 6.
- (void)testTheRunSentOnlyControlsUnderTheCeiling {
    NSSet<NSNumber *> *allowed = [NSSet setWithArray:@[@0x1F, @0x2B, @0x2D, @0x3A, @0x3D]];
    NSSet<NSData *> *glm = QLMOutputReports(@"volume-sweep", 0x1F);
    NSUInteger controls = 0;
    NSMutableSet<NSData *> *levels = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMReadCapture(QLMAllScenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (!QLMSentByQLM(exchange.time) || !QLMIsControl(message)) {
            continue;
        }
        controls += 1;
        uint8_t opcode = message.payload[0];
        XCTAssertTrue([allowed containsObject:@(opcode)], @"%02X at %.6f s", opcode, exchange.time);
        if (opcode == 0x3A) {
            XCTAssertEqual(message.payload[1], 0x03, @"%.6f s", exchange.time);
        }
        if (opcode != 0x1F) {
            continue;
        }
        XCTAssertEqual(message.address, QLMAddressBroadcast, @"%.6f s", exchange.time);
        uint32_t word = QLMVolumeWordOf(message);
        XCTAssertLessThanOrEqual(QLMVolumeDecibelsForWord(word), QLMAllCeiling + 0.01, @"%.6f s", exchange.time);
        XCTAssertTrue([glm containsObject:exchange.outputReport], @"%.6f s", exchange.time);
        [levels addObject:exchange.outputReport];
    }
    XCTAssertEqual(controls, 375u);
    XCTAssertEqual(levels.count, 3u);
}

// Step 3, 214.77 s: the Rear Right 8330A, switched on during a 90 s hold at
// -50 dB, takes session 07. The level goes to it 1 ms after its ack, before
// its 39. In qlm-control-first, a monitor switched on played at its own
// level until a host sent one.
- (void)testANewMonitorGetsTheLevelFirst {
    NSArray<QLMCaptureExchange *> *run = [self qlm_frames:3 of:QLMAllScenario from:214.773938 keep:NULL];
    if (run == nil) {
        return;
    }
    const uint8_t rearRight[] = {0x12, 0x2F, 0xAB};
    [self qlm_assertExchange:run[0] is:QLMCommandAssignSession(rearRight, 0x07)];
    [self qlm_assertLease:run[0] thenLevel:run[1] is:QLMAllLevel() within:0.004];
    [self qlm_assertExchange:run[2] is:QLMCommandSystemInfo(0x07)];
}

// After each wake, from 575.83 and 8482.67 s, the six monitors come back
// without their sessions, as GLM's do in standby-wake. Each takes a new one,
// 09 to 0E, and the level goes to it next.
- (void)testWokenMonitorsGetTheLevelFirst {
    NSArray<QLMCaptureExchange *> *exchanges = QLMReadCapture(QLMAllScenario, NULL).exchanges;
    for (NSNumber *wake in @[@575.83, @8482.67]) {
        NSUInteger leases = 0;
        for (NSUInteger i = 0; i + 1 < exchanges.count; i++) {
            QLMCaptureExchange *exchange = exchanges[i];
            if (exchange.time > wake.doubleValue + 0.2) {
                break;
            }
            if (exchange.time < wake.doubleValue || !QLMIsLease(exchange.message)) {
                continue;
            }
            XCTAssertEqual(exchange.message.payload[4], 0x09 + leases, @"%.6f s", exchange.time);
            [self qlm_assertLease:exchange thenLevel:exchanges[i + 1] is:QLMAllLevel() within:0.004];
            leases += 1;
        }
        XCTAssertEqual(leases, 6u, @"after %@ s", wake);
    }
}

// wake --volume -50, 575.10 and 8481.94 s: the level, the three wake pairs,
// then 0.25 s later the level again, 2D 00, and 3D 00 00. GLM's wake in
// standby-wake ends the same way: its last pair at 47.01 s, then 0.23 s
// later its level, 2D 00, and 3D 00 00.
- (void)testTheWakeEndsAsGLMs {
    NSArray<QLMCaptureExchange *> *glm = [self qlm_controls:5 of:@"standby-wake" from:47.008166];
    if (glm == nil) {
        return;
    }
    XCTAssertEqual(glm[2].message.payload[0], 0x1F);
    for (NSNumber *time in @[@575.095543, @8481.937046]) {
        NSArray<QLMCaptureExchange *> *run = [self qlm_controls:10 of:QLMAllScenario from:time.doubleValue];
        if (run == nil) {
            continue;
        }
        [self qlm_assertExchange:run[0] is:QLMAllLevel()];
        for (NSUInteger pair = 0; pair < 3; pair++) {
            [self qlm_assertExchange:run[1 + pair * 2] is:QLMCommandPower(QLMPowerStepWakeFirst)];
            [self qlm_assertExchange:run[2 + pair * 2] is:QLMCommandPower(QLMPowerStepWakeSecond)];
        }
        [self qlm_assertExchange:run[5] isExchange:glm[0]];
        [self qlm_assertExchange:run[6] isExchange:glm[1]];
        [self qlm_assertExchange:run[7] is:QLMAllLevel()];
        [self qlm_assertExchange:run[8] isExchange:glm[3]];
        [self qlm_assertExchange:run[9] isExchange:glm[4]];
        XCTAssertEqualWithAccuracy(run[7].time - run[6].time, glm[2].time - glm[1].time, 0.03, @"%@ s", time);
    }
}

// dim on, 432.03 and 8400.57 s, and dim off, 451.79 and 8420.35 s: the level
// dim moves from, then GLM's whole dim, as in mute-dim at 51.24 s. That is
// the new level twice, one round of 2B 04 to all six, then 2D 00 and
// 3D 00 00. qlm-control-first's dim sent only the level.
- (void)testDimIsWhole {
    NSArray<QLMCaptureExchange *> *glm = [self qlm_controls:10 of:@"mute-dim" from:51.240592];
    if (glm == nil) {
        return;
    }
    QLMMessage level = QLMAllLevel();
    QLMMessage dimmed = QLMCommandDim(QLMAllVolume, QLMAllCeiling);
    const struct {
        NSTimeInterval time;
        QLMMessage from;
        QLMMessage to;
    } runs[] = {{432.032738, level, dimmed}, {451.792971, dimmed, level}, {8400.569307, level, dimmed}, {8420.349259, dimmed, level}};
    for (size_t r = 0; r < sizeof runs / sizeof runs[0]; r++) {
        NSArray<QLMCaptureExchange *> *run = [self qlm_controls:11 of:QLMAllScenario from:runs[r].time];
        if (run == nil) {
            continue;
        }
        [self qlm_assertExchange:run[0] is:runs[r].from];
        [self qlm_assertExchange:run[1] is:runs[r].to];
        [self qlm_assertExchange:run[2] is:runs[r].to];
        XCTAssertLessThan(run[1].time - run[0].time, 0.002, @"%.6f s", runs[r].time);
        for (uint8_t i = 0; i < 6; i++) {
            QLMCaptureExchange *mute = run[3 + i];
            [self qlm_assertExchange:mute is:QLMCommandMute(0x02 + i, QLMMuteValueUnmuted)];
            XCTAssertEqual(mute.message.payload[1], glm[2 + i].message.payload[1], @"%.6f s", mute.time);
        }
        [self qlm_assertExchange:run[9] isExchange:glm[8]];
        [self qlm_assertExchange:run[10] isExchange:glm[9]];
    }
}

@end
