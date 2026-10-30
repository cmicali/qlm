#import <XCTest/XCTest.h>

#include <sysexits.h>

#import "QLMAdapter.h"
#include "QLMCommands.h"
#import "QLMControl.h"
#import "QLMSnapshotInternal.h"
#import "QLMSystem.h"

// qlmctl's gates before a control goes over USB, and its dry run. AGENTS.md's
// Safety rules set the gates. The dry run's frames are System's own, so these
// tests check that they come through whole, addressed as discovery found the
// monitors, and that nothing comes with them.
@interface QLMControlTests : XCTestCase
@end

@implementation QLMControlTests

- (QLMControlOptions *)read:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments {
    NSString *problem = nil;
    QLMControlOptions *options = [QLMControlOptions optionsForCommand:command arguments:arguments problem:&problem];
    XCTAssertNotNil(options, @"%@: %@", arguments, problem);
    XCTAssertNil(problem);
    return options;
}

- (NSString *)refusal:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments {
    NSString *problem = nil;
    XCTAssertNil([QLMControlOptions optionsForCommand:command arguments:arguments problem:&problem], @"%@", arguments);
    XCTAssertNotNil(problem, @"%@", arguments);
    return problem ?: @"";
}

- (void)assertRefusal:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments mentions:(NSString *)text {
    NSString *problem = [self refusal:command arguments:arguments];
    XCTAssertTrue([problem containsString:text], @"%@", problem);
}

#pragma mark - The gates

- (void)testOverUSBVolumeAndDimNeedACeiling {
    [self assertRefusal:QLMControlCommandVolume arguments:@[@"-50"] mentions:@"--ceiling"];
    [self assertRefusal:QLMControlCommandDim arguments:@[@"on", @"--volume", @"-50"] mentions:@"--ceiling"];

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
    [self assertRefusal:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-29.5"] mentions:@"--allow-high-ceiling"];

    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"-29.5", @"--allow-high-ceiling"]];
    XCTAssertEqual(options.ceilingDecibels, -29.5);
    options = [self read:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"0", @"--allow-high-ceiling"]];
    XCTAssertEqual(options.ceilingDecibels, 0.0);
    [self refusal:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", @"0.5", @"--allow-high-ceiling"]];
}

- (void)testTheVolumeMayNotBeAboveTheCeiling {
    [self read:QLMControlCommandVolume arguments:@[@"-40", @"--ceiling", @"-40"]];
    [self refusal:QLMControlCommandVolume arguments:@[@"-39.5", @"--ceiling", @"-40"]];
    [self refusal:QLMControlCommandDim arguments:@[@"on", @"--volume", @"-35", @"--ceiling", @"-40"]];

    // Unstated, the ceiling is the limit, on any bus.
    [self refusal:QLMControlCommandVolume arguments:@[@"-20", @"--fake"]];
    QLMControlOptions *options = [self read:QLMControlCommandVolume arguments:@[@"-40", @"--fake"]];
    XCTAssertFalse(options.overUSB);
    XCTAssertEqual(options.ceilingDecibels, QLMCeilingLimit);
}

- (void)testOnlyAFiniteNumberReads {
    for (NSString *level in @[@"nan", @"inf", @"-inf", @"", @"-40dB", @"loud"]) {
        [self refusal:QLMControlCommandVolume arguments:@[level, @"--fake"]];
        [self refusal:QLMControlCommandVolume arguments:@[@"-50", @"--ceiling", level]];
    }
    [self refusal:QLMControlCommandVolume arguments:@[@"-50", @"--fake", @"--seconds", @"-1"]];
}

// TRAP: a loose reading sends for real: a mistyped --dry-run is ignored, and
// --replay without its file falls back to USB.
- (void)testAnUnknownRepeatedOrEmptyArgumentIsRefused {
    NSArray<NSString *> *usb = @[@"-40", @"--ceiling", @"-40"];
    [self assertRefusal:QLMControlCommandVolume arguments:[usb arrayByAddingObject:@"--dryrun"] mentions:@"unknown"];
    [self assertRefusal:QLMControlCommandVolume arguments:[usb arrayByAddingObject:@"--replay"] mentions:@"value"];
    [self assertRefusal:QLMControlCommandVolume arguments:[usb arrayByAddingObjectsFromArray:@[@"--ceiling", @"-50"]] mentions:@"twice"];
    [self refusal:QLMControlCommandVolume arguments:@[@"-40", @"--fake", @"--fake"]];
    [self refusal:QLMControlCommandVolume arguments:@[@"-40", @"--fake", @"--replay", @"reports.txt"]];
    [self refusal:QLMControlCommandVolume arguments:@[@"--fake"]];
    [self refusal:QLMControlCommandMute arguments:@[@"--fake"]];
    [self refusal:QLMControlCommandMute arguments:@[@"maybe", @"--fake"]];
    [self refusal:QLMControlCommandMute arguments:@[@"on", @"off", @"--fake"]];
    [self refusal:QLMControlCommandSleep arguments:@[@"--ceiling", @"-40"]];
    [self refusal:QLMControlCommandWake arguments:@[@"now"]];
}

- (void)testDimOverUSBNeedsTheLevelToDimFrom {
    [self assertRefusal:QLMControlCommandDim arguments:@[@"on", @"--ceiling", @"-40"] mentions:@"--volume"];
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

- (void)testADryRunAddressesEachMonitorAsDiscoveryFoundIt {
    QLMSnapshot *discovered = QLMDiscovered();
    NSData *target = discovered.monitors[0].hardwareID;
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(discovered, [[QLMSystemSettings alloc] init], ^int(QLMSystem *system, QLMSnapshot *found) {
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
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
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

- (void)testADryRunOfARefusedActionHasNoFrames {
    int status = -1;
    NSArray<NSData *> *records = QLMDryRunRecords(QLMDiscovered(), [[QLMSystemSettings alloc] init], ^int(QLMSystem *system, QLMSnapshot *found) {
        return EX_DATAERR;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return YES;
    }, &status);
    XCTAssertNil(records);
    XCTAssertEqual(status, EX_DATAERR);
}

@end
