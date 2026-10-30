#import "QLMTestSupport.h"

#include <math.h>

#include "QLMCommands.h"
#include "QLMReport.h"

// Sources: the captures each test names, and their notes.md. Each test
// starts at a frame GLM sent, by its time in the capture, and checks the
// frames after it against qlm's builders, byte for byte as qlm packs them.
// The bus addresses are the capture's. The adapter's 01 08 polls run on
// their own timer, so a run leaves them out.
@interface QLMControlGoldenTests : XCTestCase
@end

@implementation QLMControlGoldenTests

static const uint8_t QLMMuteDimMonitors[] = {0x03, 0x06, 0x0D, 0x0C, 0x05, 0x0B};  // mute-dim's order

// `count` frames of captures/<scenario>, from the one at `time` to the half
// millisecond. Nil, after a failure, when the capture has fewer.
- (nullable NSArray<QLMCaptureExchange *> *)frames:(NSUInteger)count of:(NSString *)scenario from:(NSTimeInterval)time {
    NSMutableArray<QLMCaptureExchange *> *run = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        if (run.count == 0 && fabs(exchange.time - time) >= 0.0005) {
            continue;
        }
        QLMMessage message = exchange.message;
        if (message.address == QLMAddressReply && message.length == 1 && message.payload[0] == 0x08) {
            continue;
        }
        [run addObject:exchange];
        if (run.count == count) {
            return run;
        }
    }
    XCTFail(@"%@ has %lu of %lu frames from %.6f s", scenario, (unsigned long)run.count, (unsigned long)count, time);
    return nil;
}

- (void)assertExchange:(QLMCaptureExchange *)exchange is:(QLMMessage)message {
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&message, report), QLMReportOK, @"%.6f s", exchange.time);
    XCTAssertEqualObjects(exchange.outputReport, QLMBytes(report, sizeof report), @"%.6f s", exchange.time);
}

// A frame GLM sent that the allowlist refuses, so qlm never packs it.
- (void)assertExchange:(QLMCaptureExchange *)exchange isRefused:(QLMMessage)message {
    QLMMessage sent = exchange.message;
    XCTAssertEqual(sent.address, message.address, @"%.6f s", exchange.time);
    XCTAssertEqualObjects(QLMBytes(sent.payload, sent.length), QLMBytes(message.payload, message.length), @"%.6f s", exchange.time);
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&message, report), QLMReportErrorForbidden, @"%.6f s", exchange.time);
}

// One round of mute state, from `index` in `run`: 2B to every monitor in
// mute-dim's order, `muted` with 03 and the rest with 04.
- (void)assertRun:(NSArray<QLMCaptureExchange *> *)run at:(NSUInteger)index mutes:(uint8_t)muted all:(BOOL)all {
    for (size_t i = 0; i < sizeof QLMMuteDimMonitors; i++) {
        uint8_t session = QLMMuteDimMonitors[i];
        uint8_t value = all || session == muted ? QLMMuteValueMuted : QLMMuteValueUnmuted;
        [self assertExchange:run[index + i] is:QLMCommandMute(session, value)];
    }
}

// Volume: one broadcast `FF 1F` with the level. quit-glm, 0.33 s: -20 dB,
// with the volume knob at -20 dB. Under a -20 dB ceiling, 0 dB sends the
// same frame. QLMVolumeScaleTests has every other step.
- (void)testVolumeIsGLMs {
    NSArray<QLMCaptureExchange *> *run = [self frames:1 of:@"quit-glm" from:0.326423];
    [self assertExchange:run[0] is:QLMCommandVolume(-20, 0)];
    [self assertExchange:run[0] is:QLMCommandVolume(0, -20)];
}

// Dim, mute-dim, 51.24 s on and 54.77 s off: the level 20 dB down, twice,
// from -56.5 to -76.5 dB. Then one round of 2B 04, then broadcast `2D 00`
// and `3D 00 00`. qlm builds all but `2D 00`, which the allowlist refuses.
- (void)testDimIsGLMs {
    NSArray<QLMCaptureExchange *> *on = [self frames:10 of:@"mute-dim" from:51.240592];
    NSArray<QLMCaptureExchange *> *off = [self frames:10 of:@"mute-dim" from:54.774959];
    if (on == nil || off == nil) {
        return;
    }
    QLMMessage levels[] = {QLMCommandDim(-56.5, 0), QLMCommandVolume(-56.5, 0)};
    QLMAssertBytes(levels[0].payload, levels[0].length, 0x1F, 0x00, 0x04, 0xE7);
    NSArray<NSArray<QLMCaptureExchange *> *> *runs = @[on, off];
    for (NSUInteger r = 0; r < runs.count; r++) {
        NSArray<QLMCaptureExchange *> *run = runs[r];
        [self assertExchange:run[0] is:levels[r]];
        [self assertExchange:run[1] is:levels[r]];
        [self assertRun:run at:2 mutes:0 all:NO];
        [self assertExchange:run[8] isRefused:QLMMakeMessage(QLMAddressBroadcast, 0x2D, 0x00)];
        [self assertExchange:run[9] is:QLMCommandInputSync(QLMAddressBroadcast)];
    }
}

// Mute one monitor, mute-dim, 19.2 to 42.2 s: two rounds of 2B to every
// monitor, 03 to the muted one and 04 to the rest. No volume frame and
// nothing to the adapter. The notes give each time.
- (void)testMutingOneMonitorIsGLMs {
    const struct {
        NSTimeInterval mute;
        NSTimeInterval unmute;
        uint8_t session;
    } monitors[] = {
        {19.186196, 22.739597, 0x0B}, {24.678596, 26.104893, 0x05}, {27.406607, 29.218016, 0x03},
        {30.903292, 32.945437, 0x06}, {34.844168, 36.709125, 0x0D}, {38.406374, 42.157616, 0x0C},
    };
    for (size_t i = 0; i < sizeof monitors / sizeof monitors[0]; i++) {
        NSArray<QLMCaptureExchange *> *mute = [self frames:12 of:@"mute-dim" from:monitors[i].mute];
        NSArray<QLMCaptureExchange *> *unmute = [self frames:12 of:@"mute-dim" from:monitors[i].unmute];
        if (mute == nil || unmute == nil) {
            continue;
        }
        for (NSUInteger round = 0; round < 2; round++) {
            [self assertRun:mute at:round * 6 mutes:monitors[i].session all:NO];
            [self assertRun:unmute at:round * 6 mutes:0 all:NO];
        }
    }
}

// Mute all, mute-dim, 46.19 s, and unmute all, 48.60 s: the volume again,
// then `2B 01` or `2B 00` to the adapter at 01, then two rounds of 2B to
// every monitor.
- (void)testMutingAllIsGLMs {
    NSArray<QLMCaptureExchange *> *mute = [self frames:14 of:@"mute-dim" from:46.188342];
    NSArray<QLMCaptureExchange *> *unmute = [self frames:14 of:@"mute-dim" from:48.595249];
    if (mute == nil || unmute == nil) {
        return;
    }
    [self assertExchange:mute[0] is:QLMCommandVolume(-56.5, 0)];
    [self assertExchange:mute[1] is:QLMCommandMute(QLMAddressReply, QLMMuteValueAdapterMuted)];
    [self assertExchange:unmute[0] is:QLMCommandVolume(-56.5, 0)];
    [self assertExchange:unmute[1] is:QLMCommandMute(QLMAddressReply, QLMMuteValueAdapterUnmuted)];
    for (NSUInteger round = 0; round < 2; round++) {
        [self assertRun:mute at:2 + round * 6 mutes:0 all:YES];
        [self assertRun:unmute at:2 + round * 6 mutes:0 all:NO];
    }
}

// Standby, standby-wake, 34.86 s: broadcast `3A 03 02` twice, then
// `3A 03 00` twice.
- (void)testStandbyIsGLMs {
    NSArray<QLMCaptureExchange *> *run = [self frames:4 of:@"standby-wake" from:34.855835];
    if (run == nil) {
        return;
    }
    [self assertExchange:run[0] is:QLMCommandPower(QLMPowerStepStandbyPrepare)];
    [self assertExchange:run[1] is:QLMCommandPower(QLMPowerStepStandbyPrepare)];
    [self assertExchange:run[2] is:QLMCommandPower(QLMPowerStepPowerOff)];
    [self assertExchange:run[3] is:QLMCommandPower(QLMPowerStepPowerOff)];
}

// Wake: broadcast `3A 03 7F` then `3A 03 01`, three times, about 0.2 s
// apart. startup-idle sends them back to back from 7.33 s. standby-wake
// sends them at 46.57, 46.81, and 47.01 s, with the 8351B's DSP block
// between the first two.
- (void)testWakeIsGLMs {
    NSArray<QLMCaptureExchange *> *startup = [self frames:6 of:@"startup-idle" from:7.331654];
    for (NSUInteger pair = 0; startup != nil && pair < 3; pair++) {
        [self assertExchange:startup[pair * 2] is:QLMCommandPower(QLMPowerStepWakeFirst)];
        [self assertExchange:startup[pair * 2 + 1] is:QLMCommandPower(QLMPowerStepWakeSecond)];
    }
    for (NSNumber *time in @[@46.565318, @46.806259, @47.008166]) {
        NSArray<QLMCaptureExchange *> *pair = [self frames:2 of:@"standby-wake" from:time.doubleValue];
        if (pair == nil) {
            continue;
        }
        [self assertExchange:pair[0] is:QLMCommandPower(QLMPowerStepWakeFirst)];
        [self assertExchange:pair[1] is:QLMCommandPower(QLMPowerStepWakeSecond)];
    }
}

// The wake in a group switch, group-switch-main-2x1-main-2x2, 8.96 s:
// broadcast `3A 03 7F` twice, then `3A 03 02` once to 08, which leaves the
// group, and `3A 03 01` twice to 03, which is in it.
- (void)testOneMonitorsPowerIsGLMs {
    NSString *scenario = @"group-switch-main-2x1-main-2x2";
    NSArray<QLMCaptureExchange *> *wake = [self frames:3 of:scenario from:8.960111];
    NSArray<QLMCaptureExchange *> *member = [self frames:2 of:scenario from:9.034704];
    if (wake == nil || member == nil) {
        return;
    }
    [self assertExchange:wake[0] is:QLMCommandPower(QLMPowerStepWakeFirst)];
    [self assertExchange:wake[1] is:QLMCommandPower(QLMPowerStepWakeFirst)];
    [self assertExchange:wake[2] is:QLMCommandMonitorPower(0x08, QLMPowerStepStandbyPrepare)];
    [self assertExchange:member[0] is:QLMCommandMonitorPower(0x03, QLMPowerStepWakeSecond)];
    [self assertExchange:member[1] is:QLMCommandMonitorPower(0x03, QLMPowerStepWakeSecond)];
}

@end
