#import <XCTest/XCTest.h>

#import "QLMControl.h"
#import "QLMFakeBus.h"
#import "QLMPreferences.h"
#import "QLMSnapshotInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"

static NSData *QLMID(uint8_t last) {
    const uint8_t bytes[3] = {0x11, 0x4B, last};
    return QLMBytes(bytes, sizeof bytes);
}

// The app's preferences, over a defaults domain of the test's own.
@interface QLMPreferencesTests : XCTestCase
@end

@implementation QLMPreferencesTests {
    NSUserDefaults *_defaults;
    QLMPreferences *_preferences;
}

- (void)setUp {
    [super setUp];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:NSStringFromClass([self class])];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    _preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    [super tearDown];
}

#pragma mark - The ceiling

// The default is qlmctl's highest without --allow-high-ceiling, in System
// and in the app.
- (void)testTheDefaultCeilingIsQlmctlsHighest {
    XCTAssertEqual([[QLMSystemSettings alloc] init].ceilingDecibels, QLMCeilingLimit);
    XCTAssertEqual(_preferences.ceilingDecibels, QLMCeilingLimit);
}

// A ceiling the user saved stays, above the default or below it.
- (void)testASavedCeilingStays {
    for (NSNumber *saved in @[@(-20), @(-45)]) {
        XCTAssertTrue([_preferences saveCeilingDecibels:saved.doubleValue]);
        QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
        XCTAssertEqual(relaunched.ceilingDecibels, saved.doubleValue);
    }
}

#pragma mark - Above 0 dB

// 0 dB is the monitors' full level. Each level, saved at it, stays.
- (void)testALevelAtFullLevelSaves {
    XCTAssertTrue([_preferences saveCeilingDecibels:0]);
    XCTAssertEqual(_preferences.ceilingDecibels, 0);
    XCTAssertTrue([_preferences saveLowestDecibels:-10]);
    XCTAssertEqual(_preferences.lowestDecibels, -10);
    XCTAssertTrue([_preferences.adapterBus saveVolumeDecibels:0]);
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, 0);
}

// Settings and the ceiling verb refuse a level above 0 dB first. Should one
// reach the preferences, each save refuses it and keeps the old level.
- (void)testASaveAboveFullLevelKeepsTheOldLevel {
    XCTAssertTrue([_preferences saveCeilingDecibels:-45]);
    XCTAssertTrue([_preferences saveLowestDecibels:-70]);
    XCTAssertTrue([_preferences.adapterBus saveVolumeDecibels:-50]);
    XCTAssertTrue([_preferences.fakeBus saveVolumeDecibels:-55]);
    for (NSNumber *level in @[@(0.04), @(0.5), @(35), @(INFINITY), @(NAN)]) {
        XCTAssertFalse([_preferences saveCeilingDecibels:level.doubleValue], @"%@", level);
        XCTAssertFalse([_preferences saveLowestDecibels:level.doubleValue], @"%@", level);
        XCTAssertFalse([_preferences.adapterBus saveVolumeDecibels:level.doubleValue], @"%@", level);
        XCTAssertFalse([_preferences.fakeBus saveVolumeDecibels:level.doubleValue], @"%@", level);
    }
    QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
    XCTAssertEqual(relaunched.ceilingDecibels, -45);
    XCTAssertEqual(relaunched.lowestDecibels, -70);
    XCTAssertEqual(relaunched.adapterBus.volumeDecibels, -50);
    XCTAssertEqual(relaunched.fakeBus.volumeDecibels, -55);
}

// A level kept above 0 dB, or one that is no number, reads as its default.
// The ceiling falls to -30 dB, not to 0 dB. The two strings are what
// `defaults write` keeps without -float, and doubleForKey: reads "loud" as
// 0 dB.
- (void)testAHandEditedLevelAboveFullLevelReadsAsTheDefault {
    for (id kept in @[@(0.04), @(6), @(INFINITY), @(NAN), @"loud", @"-20", @[@(-20)]]) {
        [_defaults setObject:kept forKey:@"QLMCeilingDecibels"];
        [_defaults setObject:kept forKey:@"QLMLowestDecibels"];
        [_defaults setObject:kept forKey:@"QLMVolumeDecibels"];
        [_defaults setObject:kept forKey:@"QLMFakeVolumeDecibels"];
        XCTAssertEqual(_preferences.ceilingDecibels, QLMCeilingLimit, @"%@", kept);
        XCTAssertEqual(_preferences.lowestDecibels, -60, @"%@", kept);
        XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -40, @"%@", kept);
        XCTAssertEqual(_preferences.fakeBus.volumeDecibels, -40, @"%@", kept);
    }
}

// No level registers a default, so a key with nothing kept, or a hand edit
// that is no level, reads as the class's own default. doubleForKey: reads
// either as 0 dB.
- (void)testALevelWithNoRegisteredDefaultReadsAsItsDefault {
    NSDictionary<NSString *, id> *registered = [_defaults volatileDomainForName:NSRegistrationDomain];
    NSDictionary<NSString *, NSNumber *> *levels = @{
        @"QLMCeilingDecibels": @(QLMCeilingLimit),
        @"QLMLowestDecibels": @(-60),
        @"QLMVolumeDecibels": @(-40),
        @"QLMFakeVolumeDecibels": @(-40),
    };
    for (id kept in @[NSNull.null, @"loud"]) {
        for (NSString *key in levels) {
            XCTAssertNil(registered[key], @"%@", key);
            if (kept != NSNull.null) {
                [_defaults setObject:kept forKey:key];
            }
            XCTAssertEqual([_defaults doubleForKey:key], 0, @"%@", key);
        }
        XCTAssertEqual(_preferences.ceilingDecibels, levels[@"QLMCeilingDecibels"].doubleValue, @"%@", kept);
        XCTAssertEqual(_preferences.lowestDecibels, levels[@"QLMLowestDecibels"].doubleValue, @"%@", kept);
        XCTAssertEqual(_preferences.adapterBus.volumeDecibels, levels[@"QLMVolumeDecibels"].doubleValue, @"%@", kept);
        XCTAssertEqual(_preferences.fakeBus.volumeDecibels, levels[@"QLMFakeVolumeDecibels"].doubleValue, @"%@", kept);
    }
}

// A hand-edited number at or under 0 dB still reads, held to the range.
- (void)testAHandEditedLevelUnderFullLevelReads {
    [_defaults setDouble:-12.3 forKey:@"QLMCeilingDecibels"];
    [_defaults setDouble:-150 forKey:@"QLMLowestDecibels"];
    [_defaults setDouble:-5 forKey:@"QLMVolumeDecibels"];
    XCTAssertEqual(_preferences.ceilingDecibels, -12.5);
    XCTAssertEqual(_preferences.lowestDecibels, -100);
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -12.5);
}

#pragma mark - Each bus keeps its own

// A level set on the fake bus never reaches the real monitors, nor theirs
// the fake bus.
- (void)testEachBusKeepsItsOwnLevel {
    XCTAssertTrue([_preferences.fakeBus saveVolumeDecibels:-35]);
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -40);
    XCTAssertTrue([_preferences.adapterBus saveVolumeDecibels:-50]);
    XCTAssertEqual(_preferences.fakeBus.volumeDecibels, -35);
}

// The same for a level kept from a snapshot, as the knob sets it.
- (void)testASnapshotsLevelStaysWithItsBus {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.volumeDecibels = @(-33);
    [_preferences.fakeBus keepFromSnapshot:snapshot];
    XCTAssertEqual(_preferences.fakeBus.volumeDecibels, -33);
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -40);
}

// The real monitors keep the keys they had before each bus kept its own, so
// their level and mute record carry over.
- (void)testTheRealMonitorsKeepTheirKeys {
    [_defaults setDouble:-45 forKey:@"QLMVolumeDecibels"];
    [_defaults setObject:@[QLMID(0xEA)] forKey:@"QLMMutedHardwareIDs"];
    [_defaults setBool:YES forKey:@"QLMMutingAll"];
    [_defaults setObject:@[QLMID(0xAB)] forKey:@"QLMFakeMutedHardwareIDs"];
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -45);
    XCTAssertEqualObjects(_preferences.adapterBus.mutedHardwareIDs, [NSSet setWithObject:QLMID(0xEA)]);
    XCTAssertTrue(_preferences.adapterBus.mutingAll);
    XCTAssertEqual(_preferences.fakeBus.volumeDecibels, -40);
    XCTAssertEqualObjects(_preferences.fakeBus.mutedHardwareIDs, [NSSet setWithObject:QLMID(0xAB)]);
    XCTAssertFalse(_preferences.fakeBus.mutingAll);
}

#pragma mark - The record and the leases

// A running System's record and leases, as qlm-app-first's monitors hold
// them: the Right 8351B muted under mute all, and the Left lifted.
- (QLMSnapshot *)runningSnapshot {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.mutedHardwareIDs = [NSSet setWithObject:QLMID(0xEA)];
    snapshot.mutingAll = YES;
    snapshot.liftedHardwareIDs = [NSSet setWithObject:QLMID(0xAB)];
    snapshot.knownLeases = @[
        [[QLMKnownLease alloc] initWithHardwareID:QLMID(0xAB) serialNumber:@"8351BP21002711" session:0x03],
        [[QLMKnownLease alloc] initWithHardwareID:QLMID(0xEA) serialNumber:@"8351BP21002717" session:0x06],
    ];
    return snapshot;
}

// PR #49's what the app must do: save the leases and the lifted mutes, and
// give them to the next System, with the mutes.
- (void)testTheRecordAndTheLeasesOutlastALaunch {
    QLMSnapshot *snapshot = [self runningSnapshot];
    [_preferences.adapterBus keepFromSnapshot:snapshot];

    QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    [relaunched.adapterBus fillSettings:settings];
    XCTAssertEqualObjects(settings.mutedHardwareIDs, snapshot.mutedHardwareIDs);
    XCTAssertTrue(settings.mutingAll);
    XCTAssertEqualObjects(settings.liftedHardwareIDs, snapshot.liftedHardwareIDs);
    XCTAssertEqual(settings.knownLeases.count, 2u);
    for (NSUInteger i = 0; i < settings.knownLeases.count; i++) {
        XCTAssertEqualObjects(settings.knownLeases[i].hardwareID, snapshot.knownLeases[i].hardwareID);
        XCTAssertEqualObjects(settings.knownLeases[i].serialNumber, snapshot.knownLeases[i].serialNumber);
        XCTAssertEqual(settings.knownLeases[i].session, snapshot.knownLeases[i].session);
    }

    QLMSystemSettings *fake = [[QLMSystemSettings alloc] init];
    [relaunched.fakeBus fillSettings:fake];
    XCTAssertEqual(fake.mutedHardwareIDs.count, 0u);
    XCTAssertFalse(fake.mutingAll);
    XCTAssertEqual(fake.liftedHardwareIDs.count, 0u);
    XCTAssertEqual(fake.knownLeases.count, 0u);
}

// AGENTS.md's Safety rule: the app applies no group with a model whose filter
// design rate is unverified, the 8351B, so System refuses each one. The app's
// settings are QLMSystemSettings' defaults, its ceiling, and either bus's
// fill, as QLMAppDelegate makes them, and none allows an unverified rate.
// No source of the app's sets allowsUnverifiedRates.
- (void)testTheAppNeverAllowsAnUnverifiedRate {
    [_preferences.adapterBus keepFromSnapshot:[self runningSnapshot]];
    for (QLMBusPreferences *bus in @[_preferences.adapterBus, _preferences.fakeBus]) {
        QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
        settings.ceilingDecibels = _preferences.ceilingDecibels;
        [bus fillSettings:settings];
        XCTAssertFalse(settings.allowsUnverifiedRates);
    }
    NSString *app = QLMRepositoryPath(@"qlm/App");
    NSArray<NSString *> *sources = [NSFileManager.defaultManager contentsOfDirectoryAtPath:app error:NULL];
    XCTAssertGreaterThan(sources.count, 0u);
    for (NSString *name in sources) {
        NSString *text = [NSString stringWithContentsOfFile:[app stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertFalse([text containsString:@"allowsUnverifiedRates"], @"%@", name);
    }
}

// A snapshot from before System starts carries an empty record, so it keeps
// nothing. One from after a stop keeps the volume only.
- (void)testOnlyARunningSystemsRecordIsKept {
    [_preferences.adapterBus keepFromSnapshot:[self runningSnapshot]];
    QLMSnapshot *stopped = [[QLMSnapshot alloc] init];
    stopped.volumeDecibels = @(-42);
    [_preferences.adapterBus keepFromSnapshot:stopped];
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -42);
    XCTAssertEqual(_preferences.adapterBus.mutedHardwareIDs.count, 1u);
    XCTAssertEqual(_preferences.adapterBus.liftedHardwareIDs.count, 1u);
    XCTAssertEqual(_preferences.adapterBus.knownLeases.count, 2u);
}

// A lease kept by hand-edit or an older qlm that is no lease is skipped.
- (void)testALeaseThatDoesNotReadIsSkipped {
    [_defaults setObject:@[@"no", @{@"hardwareID": QLMID(0xAB), @"serialNumber": @"8351BP21002711", @"session": @(300)},
                           @{@"hardwareID": QLMID(0xEA), @"serialNumber": @"8351BP21002717", @"session": @(6)}]
                  forKey:@"QLMKnownLeases"];
    NSArray<QLMKnownLease *> *leases = _preferences.adapterBus.knownLeases;
    XCTAssertEqual(leases.count, 1u);
    XCTAssertEqual(leases.firstObject.session, 6);
}

#pragma mark - A stop no one can answer

// A System on the fake bus and the virtual clock, started from the record
// kept, and keeping each snapshot's record as the app does.
- (QLMSystem *)systemOn:(QLMFakeBus *)bus clock:(QLMVirtualClock *)time keeping:(QLMBusPreferences *)kept {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = time;
    [kept fillSettings:settings];
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [kept keepFromSnapshot:snapshot];
    } queue:dispatch_get_main_queue()];
    [system start];
    [system setVolumeDecibels:-40];
    return system;
}

- (void)stop:(QLMSystem *)system clock:(QLMVirtualClock *)time muting:(BOOL)mutes {
    __block BOOL stopped = NO;
    dispatch_block_t completion = ^{
        stopped = YES;
    };
    if (mutes) {
        [system stopMutingIfLouderWithCompletion:completion];
    } else {
        [system stopWithCompletion:completion];
    }
    XCTAssertTrue([time runUntil:^BOOL {
        return stopped;
    } within:60]);
}

// A logout, restart, or shutdown mutes every monitor where the take-over
// would be louder (#70). The app keeps only a running System's record, yet
// keeps that mute all, so the next launch restates the mutes. Else it would
// start unmuted, and its next round would unmute the monitors.
- (void)testTheMutingStopsRecordOutlastsALaunch {
    QLMVirtualClock *time = [[QLMVirtualClock alloc] init];
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    [bus perform:^{
        bus.knobTenths = @(-300);
    }];
    QLMBusPreferences *kept = _preferences.adapterBus;
    QLMSystem *system = [self systemOn:bus clock:time keeping:kept];
    XCTAssertTrue([time runUntil:^BOOL {
        QLMSnapshot *snapshot = system.snapshot;
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.idle && snapshot.handBack.kind == QLMHandBackLouder;
    } within:60]);
    [self stop:system clock:time muting:YES];
    XCTAssertTrue(kept.mutingAll);
    XCTAssertEqual(kept.mutedHardwareIDs.count, 2u);

    __block BOOL heard = YES;
    [bus perform:^{
        for (QLMFakeMonitor *monitor in bus.monitors) {
            monitor.muteValue = 0;
        }
    }];
    QLMSystem *relaunched = [self systemOn:bus clock:time keeping:kept];
    XCTAssertTrue([time runUntil:^BOOL {
        [bus perform:^{
            heard = YES;
            for (QLMFakeMonitor *monitor in bus.monitors) {
                heard = heard && monitor.muteValue == QLMMuteValueMuted;
            }
        }];
        return heard;
    } within:60], @"the next System never restated the mutes");
    XCTAssertTrue(relaunched.snapshot.mutingAll);
    [self stop:relaunched clock:time muting:NO];
}

@end
