#import <XCTest/XCTest.h>

#include <sysexits.h>

#import "QLMAdapter.h"
#include "QLMCommands.h"
#import "QLMControl.h"
#import "QLMFakeBus.h"
#import "QLMSnapshotInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"

// qlmctl's gates before a control goes over USB, and its dry run. AGENTS.md's
// Safety rules set the gates. The dry run's frames are System's own, so these
// tests check that they come through whole, addressed as discovery found the
// monitors, and that nothing comes with them.
@interface QLMControlTests : XCTestCase
@end

@implementation QLMControlTests {
    QLMVirtualClock *_time;
}

- (void)setUp {
    [super setUp];
    _time = [[QLMVirtualClock alloc] init];
}

// Runs what the dry runs left on the clock, their stops among it.
- (void)tearDown {
    [_time settle];
    [super tearDown];
}

- (QLMControlOptions *)read:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments {
    NSString *problem = nil;
    QLMControlOptions *options = [QLMControlOptions optionsForCommand:command arguments:arguments problem:&problem];
    XCTAssertNotNil(options, @"%@: %@", arguments, problem);
    XCTAssertNil(problem);
    return options;
}

// The reason given must contain `text`, when there is one.
- (void)refuse:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments mentions:(NSString *)text {
    NSString *problem = nil;
    XCTAssertNil([QLMControlOptions optionsForCommand:command arguments:arguments problem:&problem], @"%@", arguments);
    XCTAssertNotNil(problem, @"%@", arguments);
    XCTAssertTrue(text == nil || [problem containsString:text], @"%@", problem);
}

#pragma mark - The gates

- (void)testOverUSBVolumeAndDimNeedACeiling {
    [self refuse:QLMControlCommandVolume arguments:@[@"-50"] mentions:@"--ceiling"];
    [self refuse:QLMControlCommandDim arguments:@[@"on", @"--volume", @"-50"] mentions:@"--ceiling"];

    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-40"]];
    XCTAssertTrue(options.overUSB);
    XCTAssertFalse(options.dryRun);
    XCTAssertEqualObjects(options.volumeDecibels, @(-50));
    XCTAssertEqual(options.ceilingDecibels, -40.0);
    XCTAssertEqual(options.settings.ceilingDecibels, -40.0);
}

- (void)testACeilingAboveTheLimitTakesTheFlag {
    XCTAssertEqual(QLMCeilingLimit, -30.0);
    [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-30"]];
    [self refuse:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-29.5"] mentions:@"--allow-high-ceiling"];

    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-29.5", @"--allow-high-ceiling"]];
    XCTAssertEqual(options.ceilingDecibels, -29.5);
    options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"0", @"--allow-high-ceiling"]];
    XCTAssertEqual(options.ceilingDecibels, 0.0);
    [self refuse:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"0.5", @"--allow-high-ceiling"] mentions:nil];
}

- (void)testTheVolumeMayNotBeAboveTheCeiling {
    [self read:QLMControlCommandVolume arguments:@[@"-40", @"--ceiling", @"-40"]];
    [self refuse:QLMControlCommandVolume arguments:@[@"-39.5", @"--ceiling", @"-40"] mentions:nil];
    [self refuse:QLMControlCommandDim arguments:@[@"on", @"--volume", @"-35", @"--ceiling", @"-40"] mentions:nil];

    // Unstated, the ceiling is the limit, on any bus.
    [self refuse:QLMControlCommandVolume arguments:@[@"-20", @"--fake"] mentions:nil];
    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:@[@"-40", @"--fake"]];
    XCTAssertFalse(options.overUSB);
    XCTAssertEqual(options.ceilingDecibels, QLMCeilingLimit);
}

- (void)testOnlyAFiniteNumberReads {
    for (NSString *level in @[@"nan", @"inf", @"-inf", @"", @"-40dB", @"loud"]) {
        [self refuse:QLMControlCommandVolume arguments:@[level, @"--fake"] mentions:nil];
        [self refuse:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", level] mentions:nil];
    }
    [self refuse:QLMControlCommandVolume arguments:@[@"-50", @"--fake", @"--seconds", @"-1"] mentions:nil];
}

// The TRAP in QLMControlOptions: a loose reading sends for real.
- (void)testAnUnknownRepeatedOrEmptyArgumentIsRefused {
    NSArray<NSString *> *usb = @[@"-40", @"--ceiling", @"-40"];
    [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObject:@"--dryrun"] mentions:@"unknown"];
    [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObject:@"--replay"] mentions:@"value"];
    [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObjectsFromArray:@[@"--ceiling", @"-50"]] mentions:@"twice"];
    [self refuse:QLMControlCommandVolume arguments:@[@"-40", @"--fake", @"--fake"] mentions:nil];
    [self refuse:QLMControlCommandVolume arguments:@[@"-40", @"--fake", @"--replay", @"reports.txt"] mentions:nil];
    [self refuse:QLMControlCommandVolume arguments:@[@"--fake"] mentions:nil];
    [self refuse:QLMControlCommandMute arguments:@[@"--fake"] mentions:nil];
    [self refuse:QLMControlCommandMute arguments:@[@"maybe", @"--fake"] mentions:nil];
    [self refuse:QLMControlCommandMute arguments:@[@"on", @"off", @"--fake"] mentions:nil];
    [self refuse:QLMControlCommandSleep arguments:@[@"--ceiling", @"-40"] mentions:nil];
    [self refuse:QLMControlCommandWake arguments:@[@"now"] mentions:nil];
}

- (void)testDimOverUSBNeedsTheLevelToDimFrom {
    [self refuse:QLMControlCommandDim arguments:@[@"on", @"--ceiling", @"-40"] mentions:@"--volume"];
    QLMControlOptions *options = [self read:QLMControlCommandDim arguments:@[@"on", @"--volume", @"-50", @"--ceiling", @"-40"]];
    XCTAssertTrue(options.on);
    XCTAssertEqualObjects(options.volumeDecibels, @(-50));

    // On the fake bus a dim without one sends nothing.
    options = [self read:QLMControlCommandDim arguments:@[@"off", @"--fake"]];
    XCTAssertFalse(options.on);
    XCTAssertNil(options.volumeDecibels);
}

- (void)testMuteSleepAndWakeNeedNoCeiling {
    QLMControlOptions *options = [self read:QLMControlCommandMute arguments:@[@"on", @"--serial", @"21001"]];
    XCTAssertTrue(options.overUSB);
    XCTAssertTrue(options.on);
    XCTAssertEqualObjects(options.serial, @"21001");
    XCTAssertEqual(options.ceilingDecibels, QLMCeilingLimit);

    options = [self read:QLMControlCommandSleep arguments:@[]];
    XCTAssertTrue(options.overUSB);
    options = [self read:QLMControlCommandWake arguments:@[@"--dry-run", @"--seconds", @"2", @"--replay", @"reports.txt"]];
    XCTAssertTrue(options.dryRun);
    XCTAssertEqual(options.seconds, 2.0);
    XCTAssertEqualObjects(options.replayPath, @"reports.txt");
    XCTAssertFalse(options.overUSB);
}

#pragma mark - The dry run

static QLMMonitorState *QLMFoundMonitor(uint8_t session, uint8_t identity, NSString *serial) {
    QLMMonitorState *monitor = [[QLMMonitorState alloc] init];
    const uint8_t hardwareID[3] = {identity, identity, identity};
    monitor.hardwareID = [NSData dataWithBytes:hardwareID length:3];
    monitor.session = session;
    monitor.serialNumber = serial;
    monitor.systemInfo = @"c-1;model-8330A;ver-1.14.7";
    monitor.model = @"8330A";
    monitor.status = QLMMonitorStatusOn;
    monitor.deviceClass = QLMMonitorClassTwoWay;
    monitor.identified = YES;
    return monitor;
}

// Two monitors whose sessions are not the ones the mirror leases, 02 and 03.
static QLMSnapshot *QLMDiscovered(void) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.monitors = @[QLMFoundMonitor(0x09, 0x44, @"8330apm21005678"), QLMFoundMonitor(0x05, 0x11, @"8330apm21001234")];
    snapshot.allIdentified = YES;
    snapshot.anyOn = YES;
    return snapshot;
}

static NSData *QLMRecord(QLMMessage message) {
    return QLMAdapterRecord(&message);
}

// The dry run's waits move the test's clock, so its time is the test's own.
- (QLMSystemSettings *)dryRunSettings {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = _time;
    return settings;
}

// An action that is done before it returns, as when qlmctl's thread is slow
// to come back from it. The wait's handler is in place first, so it sees the
// mute land, and the dry run does not run out.
- (void)testAnActionDoneBeforeItReturnsStillShows {
    NSData *target = QLMDiscovered().monitors[0].hardwareID;  // at 09
    NSArray<NSData *> *records = [self recordsOf:^int(QLMSystem *system, QLMSnapshot *found) {
        [system setMuted:YES forMonitorWithHardwareID:target];
        [self->_time settle];
        return 0;
    } effect:QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.mutedHardwareIDs containsObject:target];
    })];
    XCTAssertTrue([records containsObject:QLMRecord(QLMCommandMute(0x09, QLMMuteValueMuted))], @"%@", records);
}

- (void)testADryRunAddressesEachMonitorAsDiscoveryFoundIt {
    QLMSnapshot *discovered = QLMDiscovered();
    NSData *target = discovered.monitors[0].hardwareID;
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(discovered, [self dryRunSettings], @[], ^int(QLMSystem *system, QLMSnapshot *found) {
        [system setMuted:YES forMonitorWithHardwareID:target];
        return 0;
    }, QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if ([monitor.hardwareID isEqualToData:target]) {
                return snapshot.idle && monitor.muted;
            }
        }
        return NO;
    }), &status);

    XCTAssertEqual(status, 0);
    XCTAssertTrue([records containsObject:QLMRecord(QLMCommandMute(0x09, QLMMuteValueMuted))]);
    XCTAssertTrue([records containsObject:QLMRecord(QLMCommandMute(0x05, QLMMuteValueUnmuted))]);
    for (NSData *record in records) {
        uint8_t address = ((const uint8_t *)record.bytes)[0];
        XCTAssertTrue(address == 0x05 || address == 0x09, @"%@", record);
    }
}

- (void)testADryRunLeavesOutDiscoveryAndKeepsTheCeiling {
    QLMSystemSettings *settings = [self dryRunSettings];
    settings.ceilingDecibels = -40;
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), settings, @[], ^int(QLMSystem *system, QLMSnapshot *found) {
        [system setVolumeDecibels:-20];  // held at the -40 dB ceiling
        return 0;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.volumeDecibels isEqual:@(-40)];
    }, &status);

    XCTAssertEqual(status, 0);
    XCTAssertGreaterThan(records.count, 0u);
    NSData *capped = QLMRecord(QLMCommandVolume(-40, -40));
    for (NSData *record in records) {
        XCTAssertEqualObjects(record, capped);
    }
}

- (void)testAVolumeFrameShowsItsWord {
    QLMMessage volume = QLMCommandVolume(-50, -40);
    uint32_t word = 0;
    XCTAssertTrue(QLMVolumeFrameWord(&volume, &word));
    XCTAssertEqual(word, QLMVolumeWordForDecibels(-50));

    QLMMessage capped = QLMCommandVolume(-20, -40);
    XCTAssertTrue(QLMVolumeFrameWord(&capped, &word));
    XCTAssertEqual(word, QLMVolumeWordForDecibels(-40));

    QLMMessage power = QLMCommandPower(QLMPowerStepPowerOff);
    QLMMessage mute = QLMCommandMute(0x02, QLMMuteValueMuted);
    QLMMessage unicast = QLMMessageMake(0x02, volume.payload, volume.length);
    XCTAssertFalse(QLMVolumeFrameWord(&power, &word));
    XCTAssertFalse(QLMVolumeFrameWord(&mute, &word));
    XCTAssertFalse(QLMVolumeFrameWord(&unicast, &word));
}

// What `action` sends on the dry run's mirror of QLMDiscovered, its monitors
// at 09 and 05, with no cycle inside it.
- (NSArray<NSData *> *)recordsOf:(QLMControlAction)action effect:(QLMSnapshotTest)effect {
    return [self recordsOf:action muted:@[] effect:effect];
}

- (NSArray<NSData *> *)recordsOf:(QLMControlAction)action muted:(NSArray<NSString *> *)muted effect:(QLMSnapshotTest)effect {
    QLMSystemSettings *settings = [self dryRunSettings];
    settings.ceilingDecibels = -35;
    settings.cycleInterval = 10;
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), settings, muted, action, effect, &status);
    XCTAssertEqual(status, 0);
    return records;
}

// Broadcast 2D 00 and 3D 00 00.
static NSArray<NSData *> *QLMPair(void) {
    return @[QLMRecord(QLMCommandInputPreamble()), QLMRecord(QLMCommandInputSync(QLMAddressBroadcast))];
}

// qlmctl dim sends GLM's whole dim (captures/mute-dim, 51.24 s on and
// 54.77 s off): the level it changes from, then the new level twice, a
// round of 2B, and 2D 00 and 3D 00 00. qlm's first run set dim before the
// volume, and sent the dimmed level alone (captures/qlm-control-first,
// 538.3 s).
- (void)testDimSendsGLMsWholeSequence {
    NSData *level = QLMRecord(QLMCommandVolume(-43.5, -35));
    NSData *dimmed = QLMRecord(QLMCommandDim(-43.5, -35));
    for (NSNumber *on in @[@YES, @NO]) {
        NSArray<NSData *> *records = [self recordsOf:QLMDimAction(on.boolValue, @(-43.5)) effect:^BOOL(QLMSnapshot *snapshot) {
            return snapshot.idle && snapshot.dimmed == on.boolValue && [snapshot.volumeDecibels isEqual:@(-43.5)];
        }];
        NSData *from = on.boolValue ? level : dimmed;
        NSData *to = on.boolValue ? dimmed : level;
        // The round of 2B goes in the mirror's lease order.
        NSArray<NSData *> *round = @[QLMRecord(QLMCommandMute(0x05, QLMMuteValueUnmuted)), QLMRecord(QLMCommandMute(0x09, QLMMuteValueUnmuted))];
        NSArray<NSData *> *expected = [[@[from, to, to] arrayByAddingObjectsFromArray:round] arrayByAddingObjectsFromArray:QLMPair()];
        XCTAssertEqualObjects(records, expected, @"dim %@", on.boolValue ? @"on" : @"off");
    }
}

// qlmctl wake --volume sets the level, then wakes, so the wake ends with the
// level and the pair, as GLM's does (captures/standby-wake, 47.24 s).
- (void)testWakeWithAVolumeEndsWithIt {
    NSData *level = QLMRecord(QLMCommandVolume(-43.5, -35));
    NSArray<NSData *> *records = [self recordsOf:QLMWakeAction(@(-43.5)) effect:QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.anyOn && [snapshot.volumeDecibels isEqual:@(-43.5)];
    })];
    NSMutableArray<NSData *> *expected = [NSMutableArray arrayWithObject:level];
    for (int pair = 0; pair < 3; pair++) {
        [expected addObject:QLMRecord(QLMCommandPower(QLMPowerStepWakeFirst))];
        [expected addObject:QLMRecord(QLMCommandPower(QLMPowerStepWakeSecond))];
    }
    [expected addObject:level];
    [expected addObjectsFromArray:QLMPair()];
    XCTAssertEqualObjects(records, expected);
}

// Over USB, wake --volume needs a ceiling. Without --volume it needs none.
- (void)testWakeWithAVolumeOverUSBNeedsACeiling {
    [self refuse:QLMControlCommandWake arguments:@[@"--volume", @"-40"] mentions:@"--ceiling"];
    [self refuse:QLMControlCommandWake arguments:@[@"--volume", @"-30", @"--ceiling", @"-35"] mentions:nil];
    QLMControlOptions *options = [self read:QLMControlCommandWake arguments:@[@"--volume", @"-40", @"--ceiling", @"-35"]];
    XCTAssertEqualObjects(options.volumeDecibels, @(-40));
    XCTAssertNil([self read:QLMControlCommandWake arguments:@[]].volumeDecibels);
}

// --muted is a comma list, on every control. An empty item is refused.
- (void)testMutedTakesACommaList {
    QLMControlOptions *options = [self read:QLMControlCommandMute arguments:@[@"on", @"--fake", @"--muted", @"2717, 9012"]];
    XCTAssertEqualObjects(options.mutedSerials, (@[@"2717", @"9012"]));
    XCTAssertEqualObjects([self read:QLMControlCommandSleep arguments:@[@"--fake"]].mutedSerials, @[]);
    for (NSNumber *command in @[@(QLMControlCommandVolume), @(QLMControlCommandDim), @(QLMControlCommandSleep), @(QLMControlCommandWake)]) {
        NSArray<NSString *> *arguments = @[@"--fake", @"--muted", @"2717"];
        if (command.integerValue == QLMControlCommandVolume) {
            arguments = [@[@"-50"] arrayByAddingObjectsFromArray:arguments];
        } else if (command.integerValue == QLMControlCommandDim) {
            arguments = [@[@"on"] arrayByAddingObjectsFromArray:arguments];
        }
        XCTAssertEqualObjects([self read:(QLMControlCommand)command.integerValue arguments:arguments].mutedSerials, @[@"2717"]);
    }
    [self refuse:QLMControlCommandMute arguments:@[@"on", @"--fake", @"--muted", @"2717,,9012"] mentions:@"--muted"];
    [self refuse:QLMControlCommandMute arguments:@[@"on", @"--fake", @"--muted", @","] mentions:@"--muted"];
}

// Each text names the one monitor whose serial contains it, or none at all.
- (void)testMutedSerialsNameOneMonitorEach {
    QLMSnapshot *discovered = QLMDiscovered();
    NSString *problem = nil;
    NSSet<NSData *> *hardwareIDs = QLMHardwareIDsForSerials(@[@"5678"], discovered, &problem);
    XCTAssertEqualObjects(hardwareIDs, [NSSet setWithObject:discovered.monitors[0].hardwareID]);
    XCTAssertNil(QLMHardwareIDsForSerials(@[@"8330"], discovered, &problem));
    XCTAssertTrue([problem containsString:@"2 monitors"], @"%@", problem);
    XCTAssertNil(QLMHardwareIDsForSerials(@[@"5678", @"9999"], discovered, &problem));
    XCTAssertTrue([problem containsString:@"0 monitors"], @"%@", problem);
}

// mute --serial restates the monitors --muted names as muted, so a monitor
// muted in GLM stays muted (captures/qlm-control-first/notes.md, 638.7 s).
- (void)testMuteKeepsTheMonitorsMutedElsewhereMuted {
    QLMSnapshot *discovered = QLMDiscovered();
    NSData *target = discovered.monitors[1].hardwareID;  // at 05
    QLMControlAction mute = ^int(QLMSystem *system, QLMSnapshot *found) {
        [system setMuted:YES forMonitorWithHardwareID:target];
        return 0;
    };
    NSArray<NSData *> *records = [self recordsOf:mute muted:@[@"5678"] effect:QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.allMuted;
    })];
    NSArray<NSData *> *round = @[QLMRecord(QLMCommandMute(0x05, QLMMuteValueMuted)), QLMRecord(QLMCommandMute(0x09, QLMMuteValueMuted))];
    XCTAssertEqualObjects(records, [round arrayByAddingObjectsFromArray:round]);

    int status = -1;
    XCTAssertNil(QLMDryRunRecords(discovered, [self dryRunSettings], @[@"9999"], mute, ^BOOL(QLMSnapshot *snapshot) {
        return YES;
    }, &status));
    XCTAssertEqual(status, EX_DATAERR);
}

// qlmctl mute off --serial with --muted. The record --muted makes shows the
// target unmuted already. A wait that saw it ended before the rounds went
// out, and the dry run printed nothing. The virtual clock settles every hop
// before a wait returns, so this counts what had gone out when the test
// first passed.
- (void)testAnUnmuteWithMutedWaitsForItsRounds {
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    QLMSystemSettings *settings = [self dryRunSettings];
    settings.cycleInterval = 10;
    settings.adapterPollInterval = 0;
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    QLMSnapshot *discovered = QLMWaitForSnapshot(system, 5, ^BOOL {
        [system start];
        return YES;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allIdentified && snapshot.monitors.count == 2;
    });
    NSData *target = bus.monitors[0].hardwareID;  // 1234, at 02
    NSUInteger start = bus.sentMessages.count;
    __block NSUInteger sentWhenShown = 0;
    QLMSnapshotTest effect = QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        if (!snapshot.idle || [snapshot.mutedHardwareIDs containsObject:target]) {
            return NO;
        }
        sentWhenShown = bus.sentMessages.count - start;
        return YES;
    });
    int status = -1;
    QLMSnapshot *shown = QLMWaitForEffect(system, discovered, @[@"5678"], ^int(QLMSystem *running, QLMSnapshot *found) {
        [running setMuted:NO forMonitorWithHardwareID:target];
        return 0;
    }, effect, 5, &status);
    XCTAssertEqual(status, 0);
    XCTAssertNotNil(shown);

    NSArray<NSData *> *round = @[QLMRecord(QLMCommandMute(0x02, QLMMuteValueUnmuted)), QLMRecord(QLMCommandMute(0x03, QLMMuteValueMuted))];
    NSArray<NSData *> *rounds = [round arrayByAddingObjectsFromArray:round];
    XCTAssertEqual(sentWhenShown, rounds.count);
    NSArray<NSData *> *sent = bus.sentMessages;
    XCTAssertEqualObjects([sent subarrayWithRange:NSMakeRange(start, sent.count - start)], rounds);
    [system stop];
}

// qlmctl's note at exit says what the stop did. A louder take-over names
// both levels.
- (void)testTheHandBackNoteSaysWhatTheStopDid {
    NSString *text = QLMHandBackText(QLMMakeHandBack(QLMHandBackKnobLevel, @(-43.3), @(-40)));
    XCTAssertTrue([text containsString:@"-43.3 dB"], @"%@", text);

    text = QLMHandBackText(QLMMakeHandBack(QLMHandBackLouder, @(-30), @(-40)));
    XCTAssertTrue([text containsString:@"-30.0 dB"] && [text containsString:@"-40.0 dB"], @"%@", text);

    text = QLMHandBackText(QLMMakeHandBack(QLMHandBackUnknown, nil, @(-40)));
    XCTAssertTrue([text containsString:@"no knob"], @"%@", text);
    text = QLMHandBackText(QLMMakeHandBack(QLMHandBackUnknown, @(-40), nil));
    XCTAssertTrue([text containsString:@"no volume"], @"%@", text);
}

// apply-group's options follow its file and group. Over USB it is a
// supervised test: it needs the level to restore and a ceiling, and only
// --unverified-rate lets System apply a model whose rate is unverified.
// Its dry run reads only the setup file, so it needs neither.
- (void)testApplyGroupOverUSBIsGated {
    [self refuse:QLMControlCommandApplyGroup arguments:@[] mentions:@"--volume"];
    [self refuse:QLMControlCommandApplyGroup arguments:@[@"--volume", @"-50"] mentions:@"--ceiling"];
    [self refuse:QLMControlCommandApplyGroup arguments:@[@"--volume", @"-30", @"--ceiling", @"-40"] mentions:@"ceiling"];
    QLMControlOptions *options = [self read:QLMControlCommandApplyGroup arguments:@[@"--volume", @"-50", @"--ceiling", @"-40"]];
    XCTAssertFalse(options.settings.allowsUnverifiedRates);
    XCTAssertFalse(options.launch);
    options = [self read:QLMControlCommandApplyGroup
               arguments:@[@"--volume", @"-50", @"--ceiling", @"-40", @"--unverified-rate", @"--launch"]];
    XCTAssertTrue(options.settings.allowsUnverifiedRates);
    XCTAssertTrue(options.launch);
    XCTAssertTrue([self read:QLMControlCommandApplyGroup arguments:@[@"--dry-run"]].dryRun);
    [self refuse:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-40", @"--unverified-rate"] mentions:@"unknown"];
    QLMControlOptions *volume = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-40"]];
    XCTAssertFalse(volume.settings.allowsUnverifiedRates);
}

#pragma mark - The adapter's polling

// docs/experiments.md, The flag: --adapter-poll goes on volume alone, from 0
// to QLMAdapterPollLimit seconds. Every other command refuses it, and so
// sends nothing.
- (void)testAdapterPollIsVolumesAloneAndBounded {
    NSArray<NSString *> *usb = @[@"-50", @"--ceiling", @"-40"];
    for (NSString *seconds in @[@"0", @"0.57", @"2", @"10"]) {
        QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:[usb arrayByAddingObjectsFromArray:@[@"--adapter-poll", seconds]]];
        XCTAssertEqualObjects(options.adapterPollSeconds, @(seconds.doubleValue));
    }
    for (NSString *seconds in @[@"-1", @"-0.01", @"10.5", @"1e9"]) {
        [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObjectsFromArray:@[@"--adapter-poll", seconds]] mentions:@"0 to 10"];
    }
    for (NSString *seconds in @[@"nan", @"inf", @"", @"0.5s", @"fast", @"--dry-run"]) {
        [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObjectsFromArray:@[@"--adapter-poll", seconds]] mentions:@"not a number"];
    }
    [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObject:@"--adapter-poll"] mentions:@"value"];
    [self refuse:QLMControlCommandVolume arguments:[usb arrayByAddingObjectsFromArray:@[@"--adapter-poll", @"1", @"--adapter-poll", @"2"]]
        mentions:@"twice"];

    NSArray<NSString *> *poll = @[@"--fake", @"--adapter-poll", @"1"];
    [self refuse:QLMControlCommandMute arguments:[@[@"on"] arrayByAddingObjectsFromArray:poll] mentions:@"unknown argument '--adapter-poll'"];
    [self refuse:QLMControlCommandDim arguments:[@[@"on"] arrayByAddingObjectsFromArray:poll] mentions:@"unknown argument '--adapter-poll'"];
    [self refuse:QLMControlCommandSleep arguments:poll mentions:@"unknown argument '--adapter-poll'"];
    [self refuse:QLMControlCommandWake arguments:poll mentions:@"unknown argument '--adapter-poll'"];
    [self refuse:QLMControlCommandApplyGroup arguments:[@[@"--dry-run"] arrayByAddingObjectsFromArray:poll]
        mentions:@"unknown argument '--adapter-poll'"];
}

// info, discover, and poll refuse what they don't know, as the controls do.
// poll ignored --adapter-poll, and ran GLM's pairs.
- (void)testQueriesRefuseAnArgumentTheyDoNotKnow {
    NSString *problem = nil;
    NSDictionary<NSString *, NSString *> *given = QLMQueryArguments(@"poll", @[@"--seconds", @"30", @"--fake"], &problem);
    XCTAssertEqualObjects(given, (@{@"--seconds": @"30", @"--fake": @"--fake"}));
    given = QLMQueryArguments(@"discover", @[@"--setup", @"Main.sam", @"--seconds", @"3", @"--replay", @"reports.txt"], &problem);
    XCTAssertEqualObjects(given[@"--setup"], @"Main.sam");
    XCTAssertEqualObjects(given[@"--replay"], @"reports.txt");
    XCTAssertEqualObjects(QLMQueryArguments(@"info", @[], &problem), @{});

    NSArray<NSArray<NSString *> *> *refused = @[
        @[@"poll", @"--seconds", @"30", @"--adapter-poll", @"0"], @[@"discover", @"--adapter-poll", @"0"], @[@"info", @"--adapter-poll", @"0"],
        @[@"info", @"--seconds", @"3"], @[@"poll", @"--setup", @"Main.sam"], @[@"poll", @"--secnds", @"30"], @[@"poll", @"30"],
        @[@"poll", @"--seconds"], @[@"poll", @"--fake", @"--fake"], @[@"poll", @"--seconds", @"abc"], @[@"poll", @"--seconds", @"30s"],
        @[@"discover", @"--seconds", @"-5"], @[@"info", @"--fake", @"--replay", @"reports.txt"],
    ];
    for (NSArray<NSString *> *line in refused) {
        NSArray<NSString *> *arguments = [line subarrayWithRange:NSMakeRange(1, line.count - 1)];
        XCTAssertNil(QLMQueryArguments(line[0], arguments, &problem), @"%@", line);
        XCTAssertNotNil(problem, @"%@", line);
    }
}

// Without --adapter-poll, the settings are System's own: GLM's pair every
// 0.107 s (docs/adapter-status.md). With it, one poll a round.
- (void)testAdapterPollSetsOnePollARound {
    QLMSystemSettings *glm = [[QLMSystemSettings alloc] init];
    XCTAssertEqual(glm.adapterPollInterval, 0.107);
    XCTAssertEqual(glm.adapterPollsPerRound, 2u);
    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--fake"]];
    XCTAssertNil(options.adapterPollSeconds);
    XCTAssertEqual(options.settings.adapterPollInterval, glm.adapterPollInterval);
    XCTAssertEqual(options.settings.adapterPollsPerRound, glm.adapterPollsPerRound);
    XCTAssertEqualObjects(options.adapterPollText, @"qlm polls the adapter as GLM does, with a pair of 01 08 every 0.107 s.");

    options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--fake", @"--adapter-poll", @"0.57"]];
    XCTAssertEqual(options.settings.adapterPollInterval, 0.57);
    XCTAssertEqual(options.settings.adapterPollsPerRound, 1u);
    XCTAssertEqual(((QLMSystemSettings *)[options.settings copy]).adapterPollsPerRound, 1u);
    XCTAssertEqualObjects(options.adapterPollText, @"qlm polls the adapter with one 01 08 every 0.57 s, in place of GLM's pair every 0.107 s.");

    options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--fake", @"--adapter-poll", @"0"]];
    XCTAssertEqual(options.settings.adapterPollInterval, 0.0);
    XCTAssertEqual(options.settings.adapterPollsPerRound, 1u);
    XCTAssertEqualObjects(options.adapterPollText, @"qlm polls the adapter with one 01 08 at start only, in place of GLM's pair every 0.107 s.");
}

// The time of each 01 08, from the start, over 5 s of `volume -50 --fake`
// with these arguments, on the fake bus. `others` gets every other frame,
// the stop's included.
- (NSArray<NSNumber *> *)adapterPollTimesWith:(NSArray<NSString *> *)arguments others:(NSArray<NSData *> **)others {
    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:[@[@"-50", @"--fake"] arrayByAddingObjectsFromArray:arguments]];
    QLMSystemSettings *settings = options.settings;
    settings.clock = _time;
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    NSData *poll = QLMRecord(QLMCommandPoll(QLMAddressAdapter));
    NSMutableArray<NSNumber *> *times = [NSMutableArray array];
    __block NSUInteger seen = 0;
    NSTimeInterval start = _time.now;
    [system start];
    [system setVolumeDecibels:-50];
    [_time runUntil:^BOOL {
        NSArray<NSData *> *sent = bus.sentMessages;
        for (; seen < sent.count; seen++) {
            if ([sent[seen] isEqualToData:poll]) {
                [times addObject:@(self->_time.now - start)];
            }
        }
        return NO;
    } within:5];
    [system stop];
    [_time settle];
    *others = [bus.sentMessages filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSData *record, NSDictionary *bindings) {
        return ![record isEqualToData:poll];
    }]];
    return times;
}

// docs/experiments.md, The flag: one 01 08 every SECONDS in place of GLM's
// pair every 0.107 s, and 0 polls only at start. The rest of the cycle, the
// probe, the volume, and a poll to each monitor, stays as it is, and so does
// the stop's level.
- (void)testAdapterPollSetsTheCadence {
    NSArray<NSData *> *glmOthers = nil;
    NSArray<NSNumber *> *glm = [self adapterPollTimesWith:@[] others:&glmOthers];
    XCTAssertEqual(glm.count, 2 * (1 + 46u));  // 46 * 0.107 s = 4.922 s
    for (NSUInteger i = 0; i < glm.count; i++) {
        XCTAssertEqualWithAccuracy(glm[i].doubleValue, (i / 2) * 0.107, 1e-9, @"poll %lu", (unsigned long)i);
    }
    XCTAssertGreaterThan(glmOthers.count, 0u);
    uint32_t ceiling = QLMVolumeWordForDecibels(QLMCeilingLimit);
    for (NSData *record in glmOthers) {
        const uint8_t *bytes = record.bytes;
        QLMMessage message = QLMMessageMake(bytes[0], bytes + 1, record.length - 1);
        uint32_t word = 0;
        XCTAssertTrue(!QLMVolumeFrameWord(&message, &word) || word <= ceiling, @"%@", record);
    }

    NSDictionary<NSString *, NSNumber *> *rounds = @{@"0": @1, @"0.57": @9, @"2": @3};  // from 0, to 4.56 s and 4 s
    for (NSString *interval in rounds) {
        NSArray<NSData *> *others = nil;
        NSArray<NSNumber *> *times = [self adapterPollTimesWith:@[@"--adapter-poll", interval] others:&others];
        XCTAssertEqual(times.count, rounds[interval].unsignedIntegerValue, @"every %@ s", interval);
        for (NSUInteger i = 0; i < times.count; i++) {
            XCTAssertEqualWithAccuracy(times[i].doubleValue, i * interval.doubleValue, 1e-9, @"every %@ s, poll %lu", interval, (unsigned long)i);
        }
        XCTAssertEqualObjects(others, glmOthers, @"every %@ s", interval);
    }
}

static QLMSnapshot *QLMDiscoveredWithKnob(NSNumber *_Nullable tenths) {
    QLMSnapshot *snapshot = QLMDiscovered();
    QLMAdapterState *adapter = [[QLMAdapterState alloc] init];
    adapter.hasStatus = YES;
    adapter.knobPresent = tenths != nil;
    adapter.knobTenths = tenths;
    snapshot.adapter = adapter;
    return snapshot;
}

// With fewer polls, the adapter may take over during the run, at the knob's
// level, which the ceiling does not bound. So --adapter-poll needs the knob
// in, at or below the level that goes out, by System's hand-back rule. The
// knob reads in tenths of a dB.
- (void)testFewerAdapterPollsNeedTheKnobAtOrBelowTheVolume {
    QLMSnapshotTest effect = ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.volumeDecibels isEqual:@(-50)];
    };
    NSData *level = QLMRecord(QLMCommandVolume(-50, QLMCeilingLimit));
    for (NSNumber *knob in @[@(-600), @(-500)]) {
        int status = -1;
        NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscoveredWithKnob(knob), [self dryRunSettings], @[], QLMVolumeAction(-50, YES), effect, &status);
        XCTAssertEqual(status, 0, @"knob %@", knob);
        XCTAssertTrue([records containsObject:level], @"knob %@", knob);
    }
    for (QLMSnapshot *discovered in @[QLMDiscoveredWithKnob(@(-480)), QLMDiscoveredWithKnob(nil)]) {
        int status = -1;
        XCTAssertNil(QLMDryRunRecords(discovered, [self dryRunSettings], @[], QLMVolumeAction(-50, YES), effect, &status));
        XCTAssertEqual(status, EX_DATAERR, @"knob %@", discovered.adapter.knobTenths);
    }
    // The frame under a -40.2 dB ceiling goes out at a step below the knob's.
    QLMSystemSettings *settings = [self dryRunSettings];
    settings.ceilingDecibels = -40.2;
    int status = -1;
    XCTAssertNil(QLMDryRunRecords(QLMDiscoveredWithKnob(@(-402)), settings, @[], QLMVolumeAction(-40.2, YES), effect, &status));
    XCTAssertEqual(status, EX_DATAERR);

    XCTAssertNotNil(QLMDryRunRecords(QLMDiscoveredWithKnob(@(-400)), [self dryRunSettings], @[], QLMVolumeAction(-50, NO), effect, &status));
    XCTAssertEqual(status, 0);
}

- (void)testADryRunOfARefusedActionHasNoFrames {
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), [self dryRunSettings], @[], ^int(QLMSystem *system, QLMSnapshot *found) {
        return EX_DATAERR;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return YES;
    }, &status);
    XCTAssertNil(records);
    XCTAssertEqual(status, EX_DATAERR);
}

@end
