#import "QLMTestSupport.h"

#include <math.h>

#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: captures/qlm-app-first, the menu bar app's first run on the
// monitors, and its notes.md. GLM sent every frame before 183 s, and the app
// every one after, across four launches. Each control frame the app sent is
// checked against GLM's, and each stop against the hand-back rule.
@interface QLMAppFirstTests : XCTestCase
@end

@implementation QLMAppFirstTests

static NSString *const QLMAppScenario = @"qlm-app-first";
static const NSTimeInterval QLMAppStart = 183;
static const double QLMAppCeiling = -35;

static QLMMessage QLMAppLevel(double decibels) {
    return QLMCommandVolume(decibels, QLMAppCeiling);
}

- (NSArray<QLMCaptureExchange *> *)exchanges {
    return QLMReadCapture(QLMAppScenario, NULL).exchanges;
}

// GLM's last report is at 182.770 s. The app's first is the open's sync,
// `01 39`, 0.85 s later. Turned on while GLM ran, the app sent nothing.
- (void)testTheAppWaitedForGLMToQuit {
    NSArray<QLMCaptureExchange *> *exchanges = [self exchanges];
    NSData *sync = QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter));
    NSUInteger first = [exchanges indexOfObjectPassingTest:^BOOL(QLMCaptureExchange *exchange, NSUInteger i, BOOL *stop) {
        return [exchange.outputReport isEqualToData:sync];
    }];
    XCTAssertNotEqual(first, NSNotFound);
    if (first == NSNotFound || first == 0) {
        return;
    }
    XCTAssertEqualWithAccuracy(exchanges[first].time, 183.621789, 0.0005);
    XCTAssertEqualWithAccuracy(exchanges[first - 1].time, 182.770264, 0.0005);
}

// The monitors kept GLM's leases until 2.5 to 3.1 s after GLM last polled
// them, at 182.660 s. The app's probes at 184.0, 184.5, and 185.1 s got
// `01 7E`. The one at 185.72 s found the Rear Right 8330A.
- (void)testGLMsLeasesLapsedWithinThreeSeconds {
    const NSTimeInterval lastPoll = 182.660137;
    NSData *probe = QLMReportFor(QLMCommandProbe());
    NSMutableArray<QLMCaptureExchange *> *probes = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in [self exchanges]) {
        if (exchange.time > QLMAppStart && exchange.time < 185.72 && [exchange.outputReport isEqualToData:probe]) {
            [probes addObject:exchange];
        }
    }
    XCTAssertEqual(probes.count, 4u);
    if (probes.count != 4) {
        return;
    }
    for (NSUInteger i = 0; i < 3; i++) {
        XCTAssertFalse(probes[i].answered, @"%.6f s", probes[i].time);
    }
    QLMMessage reply = probes[3].reply;
    uint8_t hardwareID[3] = {0};
    XCTAssertTrue(QLMReplyHardwareID(&reply, hardwareID));
    QLMAssertBytes(hardwareID, sizeof hardwareID, 0x12, 0x2F, 0xAB);
    XCTAssertGreaterThan(probes[2].time - lastPoll, 2.4);
    XCTAssertLessThan(probes[3].time - lastPoll, 3.1);
}

// Each of the app's 30 leases, at four launches and a wake, is acked, and
// the level goes next, within 5 ms of the lease: -45 dB at the first
// launch, -50 dB at the second, and -35 dB after.
- (void)testEveryLeaseGetsTheLevelFirst {
    NSArray<QLMCaptureExchange *> *exchanges = [self exchanges];
    NSUInteger leases = 0;
    for (NSUInteger i = 0; i + 1 < exchanges.count; i++) {
        QLMCaptureExchange *lease = exchanges[i];
        if (lease.time < QLMAppStart || !QLMIsLease(lease.message)) {
            continue;
        }
        leases += 1;
        double decibels = lease.time < 900 ? -45 : (lease.time < 1000 ? -50 : -35);
        [self qlm_assertLease:lease thenLevel:exchanges[i + 1] is:QLMAppLevel(decibels) within:0.005];
    }
    XCTAssertEqual(leases, 30u);
}

// Every frame the app sent beyond discovery is a level, a mute, a power
// step, or the input pair. Each 3A is a power step, 3A 03. Each of its 56
// levels is a report GLM sent in volume-sweep, at or under the -35 dB
// ceiling, though the knob reached its top stop, 0 dB, at 293.6 s.
- (void)testTheAppSentOnlyControlsUnderTheCeiling {
    NSSet<NSNumber *> *allowed = [NSSet setWithArray:@[@0x1F, @0x2B, @0x2D, @0x3A, @0x3D]];
    NSSet<NSData *> *glm = QLMOutputReports(@"volume-sweep", 0x1F);
    NSUInteger controls = 0;
    NSMutableSet<NSData *> *levels = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in [self exchanges]) {
        QLMMessage message = exchange.message;
        if (exchange.time < QLMAppStart || !QLMIsControl(message)) {
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
        XCTAssertLessThanOrEqual(QLMVolumeDecibelsForWord(QLMVolumeWordOf(message)), QLMAppCeiling + 0.01, @"%.6f s", exchange.time);
        XCTAssertTrue([glm containsObject:exchange.outputReport], @"%.6f s", exchange.time);
        [levels addObject:exchange.outputReport];
    }
    XCTAssertEqual(controls, 4208u);
    XCTAssertEqual(levels.count, 56u);
}

// The knob's first turn in step 5, 417.31 s: the level three times, `01 2B 00`,
// two rounds of 2B 04 to the six, then the level again. GLM's first turn in
// knob-sweep, 19.24 s, has that shape and the same level, -41.5 dB.
- (void)testTheKnobsBurstIsGLMs {
    NSArray<QLMCaptureExchange *> *app = [self qlm_controls:17 of:QLMAppScenario from:417.310490];
    NSArray<QLMCaptureExchange *> *glm = [self qlm_controls:4 of:@"knob-sweep" from:19.241470];
    if (app == nil || glm == nil) {
        return;
    }
    for (NSUInteger i = 0; i < 3; i++) {
        [self qlm_assertExchange:app[i] isExchange:glm[0]];
    }
    [self qlm_assertExchange:app[3] isExchange:glm[3]];
    for (NSUInteger i = 0; i < 12; i++) {
        [self qlm_assertExchange:app[4 + i] is:QLMCommandMute((uint8_t)(0x02 + i % 6), QLMMuteValueUnmuted)];
    }
    [self qlm_assertExchange:app[16] isExchange:glm[0]];
}

// Step 6: the Left 8351B, at 03, muted at 606.08 s, and the Right, at 06, at
// 612.72 s. Each is two rounds of 2B, 03 to it and 04 to the rest, as GLM
// mutes one monitor in mute-dim.
- (void)testMutingOneMonitorIsGLMs {
    const struct {
        NSTimeInterval time;
        uint8_t muted;
    } mutes[] = {{606.082228, 0x03}, {612.718836, 0x06}};
    for (size_t m = 0; m < sizeof mutes / sizeof mutes[0]; m++) {
        NSArray<QLMCaptureExchange *> *run = [self qlm_controls:12 of:QLMAppScenario from:mutes[m].time];
        if (run == nil) {
            continue;
        }
        for (NSUInteger i = 0; i < 12; i++) {
            uint8_t session = (uint8_t)(0x02 + i % 6);
            uint8_t value = session == mutes[m].muted ? QLMMuteValueMuted : QLMMuteValueUnmuted;
            [self qlm_assertExchange:run[i] is:QLMCommandMute(session, value)];
        }
    }
}

// Mute all, 666.41 s, and unmute all, 670.56 s: the level, `01 2B 01` or
// `01 2B 00`, then two rounds of 2B 03 or 2B 04. GLM's in mute-dim, at 46.19
// and 48.60 s, is the same, frame for frame but its level.
- (void)testMutingAllIsGLMs {
    const struct {
        NSTimeInterval app;
        NSTimeInterval glm;
        uint8_t value;
    } runs[] = {{666.411292, 46.188342, QLMMuteValueMuted}, {670.556644, 48.595249, QLMMuteValueUnmuted}};
    for (size_t r = 0; r < sizeof runs / sizeof runs[0]; r++) {
        NSArray<QLMCaptureExchange *> *app = [self qlm_controls:14 of:QLMAppScenario from:runs[r].app];
        NSArray<QLMCaptureExchange *> *glm = [self qlm_controls:14 of:@"mute-dim" from:runs[r].glm];
        if (app == nil || glm == nil) {
            continue;
        }
        [self qlm_assertExchange:app[0] is:QLMAppLevel(-45)];
        [self qlm_assertExchange:app[1] isExchange:glm[1]];
        for (NSUInteger i = 0; i < 12; i++) {
            [self qlm_assertExchange:app[2 + i] is:QLMCommandMute((uint8_t)(0x02 + i % 6), runs[r].value)];
            XCTAssertEqual(app[2 + i].message.payload[1], glm[2 + i].message.payload[1], @"%.6f s", app[2 + i].time);
        }
    }
}

// Step 7: dim on, 694.01 s, and off, 697.62 s, from -45 dB. Each is GLM's
// whole dim from mute-dim, 51.24 s: the new level twice, a round of 2B 04,
// then 2D 00 and 3D 00 00.
- (void)testDimIsGLMs {
    NSArray<QLMCaptureExchange *> *glm = [self qlm_controls:10 of:@"mute-dim" from:51.240592];
    if (glm == nil) {
        return;
    }
    const struct {
        NSTimeInterval time;
        QLMMessage level;
    } runs[] = {{694.007031, QLMCommandDim(-45, QLMAppCeiling)}, {697.624131, QLMAppLevel(-45)}};
    for (size_t r = 0; r < sizeof runs / sizeof runs[0]; r++) {
        NSArray<QLMCaptureExchange *> *run = [self qlm_controls:10 of:QLMAppScenario from:runs[r].time];
        if (run == nil) {
            continue;
        }
        [self qlm_assertExchange:run[0] is:runs[r].level];
        [self qlm_assertExchange:run[1] is:runs[r].level];
        for (uint8_t i = 0; i < 6; i++) {
            [self qlm_assertExchange:run[2 + i] is:QLMCommandMute(0x02 + i, QLMMuteValueUnmuted)];
        }
        [self qlm_assertExchange:run[8] isExchange:glm[8]];
        [self qlm_assertExchange:run[9] isExchange:glm[9]];
    }
}

// Step 10: standby, 1219.41 s, is standby-wake's at 34.86 s. The wake,
// 1232.64 s, is its three pairs, then 0.24 s after the last the level and
// the pair, as GLM's ends in standby-wake at 47.01 s.
- (void)testStandbyAndWakeAreGLMs {
    NSArray<QLMCaptureExchange *> *standby = [self qlm_controls:4 of:QLMAppScenario from:1219.405584];
    NSArray<QLMCaptureExchange *> *glmStandby = [self qlm_controls:4 of:@"standby-wake" from:34.855835];
    NSArray<QLMCaptureExchange *> *wake = [self qlm_controls:9 of:QLMAppScenario from:1232.643009];
    NSArray<QLMCaptureExchange *> *glmWake = [self qlm_controls:5 of:@"standby-wake" from:47.008166];
    if (standby == nil || glmStandby == nil || wake == nil || glmWake == nil) {
        return;
    }
    for (NSUInteger i = 0; i < 4; i++) {
        [self qlm_assertExchange:standby[i] isExchange:glmStandby[i]];
    }
    for (NSUInteger pair = 0; pair < 3; pair++) {
        [self qlm_assertExchange:wake[pair * 2] is:QLMCommandPower(QLMPowerStepWakeFirst)];
        [self qlm_assertExchange:wake[pair * 2 + 1] is:QLMCommandPower(QLMPowerStepWakeSecond)];
    }
    [self qlm_assertExchange:wake[6] is:QLMAppLevel(-35)];
    [self qlm_assertExchange:wake[7] isExchange:glmWake[3]];
    [self qlm_assertExchange:wake[8] isExchange:glmWake[4]];
    XCTAssertEqualWithAccuracy(wake[6].time - wake[5].time, glmWake[2].time - glmWake[1].time, 0.03);
}

// Step 9: the relaunch at 1158.08 s restates the Right's mute, kept by
// hardware ID: `06 2B 03` right after its lease and level. No other monitor
// gets a 2B.
- (void)testAMuteOutlastsARelaunch {
    NSArray<QLMCaptureExchange *> *run = [self qlm_frames:2 of:QLMAppScenario from:1158.179020 keep:NULL];
    if (run == nil) {
        return;
    }
    const uint8_t right[] = {0x11, 0x4B, 0xEA};
    [self qlm_assertExchange:run[0] is:QLMCommandAssignSession(right, 0x06)];
    [self qlm_assertExchange:run[1] is:QLMAppLevel(-35)];
    NSUInteger mutes = 0;
    for (QLMCaptureExchange *exchange in [self exchanges]) {
        if (exchange.time >= 1158 && exchange.time < 1158.3 && exchange.message.payload[0] == 0x2B) {
            [self qlm_assertExchange:exchange is:QLMCommandMute(0x06, QLMMuteValueMuted)];
            mutes += 1;
        }
    }
    XCTAssertEqual(mutes, 1u);
}

// The hand-back. At 754.25 s the knob, at -39.9 dB, sat above the app's
// -50 dB, so the app asked first and sent nothing more: its last level is
// its own, and its last report an ordinary poll. At 1034.57, 1125.91, and
// 1341.85 s the knob sat below the app's -35 dB, so the app's last report
// is the knob's level, -40 dB, and the take-over changes nothing.
- (void)testEachStopHandsBackAtTheKnob {
    NSArray<QLMCaptureExchange *> *exchanges = [self exchanges];
    QLMCaptureExchange *lastLevel = nil;
    QLMCaptureExchange *lastReport = nil;
    for (QLMCaptureExchange *exchange in exchanges) {
        if (exchange.time > 760) {
            break;
        }
        lastReport = exchange;
        if (exchange.message.payload[0] == 0x1F) {
            lastLevel = exchange;
        }
    }
    [self qlm_assertExchange:lastLevel is:QLMAppLevel(-50)];
    [self qlm_assertExchange:lastReport is:QLMCommandPoll(QLMAddressAdapter)];
    XCTAssertEqualWithAccuracy(lastReport.time, 754.247129, 0.0005);

    for (NSNumber *time in @[@1034.565512, @1125.910199, @1341.852592]) {
        NSUInteger i = [exchanges indexOfObjectPassingTest:^BOOL(QLMCaptureExchange *exchange, NSUInteger index, BOOL *stop) {
            return fabs(exchange.time - time.doubleValue) < 0.0005;
        }];
        XCTAssertNotEqual(i, NSNotFound, @"%@ s", time);
        if (i == NSNotFound) {
            continue;
        }
        [self qlm_assertExchange:exchanges[i] is:QLMAppLevel(-40)];
        XCTAssertTrue(i + 1 == exchanges.count || exchanges[i + 1].time - exchanges[i].time > 30, @"%@ s", time);
    }
}

@end
