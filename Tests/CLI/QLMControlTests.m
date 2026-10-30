#import <XCTest/XCTest.h>

#include <sysexits.h>

#import "QLMAdapter.h"
#include "QLMCommands.h"
#import "QLMControl.h"
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

- (void)testADryRunAddressesEachMonitorAsDiscoveryFoundIt {
    QLMSnapshot *discovered = QLMDiscovered();
    NSData *target = discovered.monitors[0].hardwareID;
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(discovered, [self dryRunSettings], ^int(QLMSystem *system, QLMSnapshot *found) {
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
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), settings, ^int(QLMSystem *system, QLMSnapshot *found) {
        [system setVolumeDecibels:-20];
        return 0;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.volumeDecibels isEqual:@(-20)];
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
    QLMSystemSettings *settings = [self dryRunSettings];
    settings.ceilingDecibels = -35;
    settings.cycleInterval = 10;
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), settings, action, effect, &status);
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
    NSArray<NSData *> *records = [self recordsOf:QLMWithMuted(@[@"5678"], mute) effect:QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.allMuted;
    })];
    NSArray<NSData *> *round = @[QLMRecord(QLMCommandMute(0x05, QLMMuteValueMuted)), QLMRecord(QLMCommandMute(0x09, QLMMuteValueMuted))];
    XCTAssertEqualObjects(records, [round arrayByAddingObjectsFromArray:round]);

    int status = -1;
    XCTAssertNil(QLMDryRunRecords(discovered, [self dryRunSettings], QLMWithMuted(@[@"9999"], mute), ^BOOL(QLMSnapshot *snapshot) {
        return YES;
    }, &status));
    XCTAssertEqual(status, EX_DATAERR);
}

static QLMHandBack *QLMMakeHandBack(QLMHandBackKind kind, NSNumber *_Nullable knob, NSNumber *_Nullable volume) {
    QLMHandBack *handBack = [[QLMHandBack alloc] init];
    handBack.kind = kind;
    handBack.knobDecibels = knob;
    handBack.volumeDecibels = volume;
    return handBack;
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

- (void)testADryRunOfARefusedActionHasNoFrames {
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), [self dryRunSettings], ^int(QLMSystem *system, QLMSnapshot *found) {
        return EX_DATAERR;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return YES;
    }, &status);
    XCTAssertNil(records);
    XCTAssertEqual(status, EX_DATAERR);
}

@end
