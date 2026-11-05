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

@interface QLMBusPreferences (QLMTesting)
- (void)keepKnobTenths:(nullable NSNumber *)knobTenths;
@end

// The app's preferences, over a defaults domain of the test's own.
@interface QLMPreferencesTests : XCTestCase
@end

@implementation QLMPreferencesTests {
    NSUserDefaults *_defaults;
    QLMPreferences *_preferences;
    QLMPreferences *_relaunched;  // the bus preferences hold it weakly
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

#pragma mark - The window

// docs/ui.md: the window opens at launch until the user turns that off,
// and modern is the skin until one is chosen.
- (void)testTheWindowsChoicesStartOnAndModern {
    XCTAssertTrue(_preferences.opensWindowAtLaunch);
    XCTAssertEqualObjects(_preferences.skinName, @"modern");
    _preferences.opensWindowAtLaunch = NO;
    _preferences.skinName = @"vintage";
    QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
    XCTAssertFalse(relaunched.opensWindowAtLaunch);
    XCTAssertEqualObjects(relaunched.skinName, @"vintage");
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

#pragma mark - The skin and the OSD

// docs/ui.md's OSD settings: on, at the bottom center, for 2 s. The skin
// is modern.
- (void)testTheOSDsDefaults {
    XCTAssertTrue(_preferences.showsOSD);
    XCTAssertEqual(_preferences.osdPlacement, QLMOSDPlacementBottomCenter);
    XCTAssertEqual(_preferences.osdSeconds, 2);
    XCTAssertEqualObjects(_preferences.skinName, @"modern");
}

- (void)testTheOSDsSettingsStay {
    _preferences.showsOSD = NO;
    _preferences.osdPlacement = QLMOSDPlacementTopRight;
    _preferences.osdSeconds = 4.5;
    _preferences.skinName = @"vintage";
    QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
    XCTAssertFalse(relaunched.showsOSD);
    XCTAssertEqual(relaunched.osdPlacement, QLMOSDPlacementTopRight);
    XCTAssertEqual(relaunched.osdSeconds, 4.5);
    XCTAssertEqualObjects(relaunched.skinName, @"vintage");
    XCTAssertEqualObjects([_defaults stringForKey:@"QLMOSDPlacement"], @"topRight");
}

// Each place keeps its own name.
- (void)testEachPlaceStays {
    for (QLMOSDPlacement placement = QLMOSDPlacementTopLeft; placement <= QLMOSDPlacementBottomRight; placement++) {
        _preferences.osdPlacement = placement;
        XCTAssertEqual(_preferences.osdPlacement, placement);
    }
}

// 0.5 to 10 s, on the nearest half second. No number keeps the old one.
- (void)testTheOSDsSecondsHoldToTheRange {
    NSDictionary<NSNumber *, NSNumber *> *saves = @{
        @(0): @(0.5), @(-3): @(0.5), @(0.7): @(0.5), @(0.8): @(1), @(3.3): @(3.5), @(10): @(10), @(11): @(10), @(INFINITY): @(10),
    };
    for (NSNumber *saved in saves) {
        _preferences.osdSeconds = saved.doubleValue;
        XCTAssertEqual(_preferences.osdSeconds, saves[saved].doubleValue, @"%@", saved);
    }
    _preferences.osdSeconds = 3;
    _preferences.osdSeconds = NAN;
    XCTAssertEqual(_preferences.osdSeconds, 3);
}

// A hand edit that is no number, or no place qlm knows, reads as the
// default. A number out of range is held to it. doubleForKey: reads "long"
// as 0 s.
- (void)testAHandEditedOSDSettingReadsAsTheDefault {
    for (id kept in @[@"long", @"4", @(NAN), @(INFINITY), @[@4]]) {
        [_defaults setObject:kept forKey:@"QLMOSDSeconds"];
        XCTAssertEqual(_preferences.osdSeconds, 2, @"%@", kept);
    }
    [_defaults setObject:@(60) forKey:@"QLMOSDSeconds"];
    XCTAssertEqual(_preferences.osdSeconds, 10);
    [_defaults setObject:@(0.1) forKey:@"QLMOSDSeconds"];
    XCTAssertEqual(_preferences.osdSeconds, 0.5);
    for (id kept in @[@"middle", @"BottomCenter", @(2), @[@"topLeft"]]) {
        [_defaults setObject:kept forKey:@"QLMOSDPlacement"];
        XCTAssertEqual(_preferences.osdPlacement, QLMOSDPlacementBottomCenter, @"%@", kept);
    }
    for (id kept in @[@"", @[@"vintage"]]) {
        [_defaults setObject:kept forKey:@"QLMSkinName"];
        XCTAssertEqualObjects(_preferences.skinName, @"modern", @"%@", kept);
    }
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

// A System on the fake bus and the virtual clock, started from the level,
// the record, and the knob kept, and keeping each snapshot's, as the app
// does.
- (QLMSystem *)systemOn:(QLMFakeBus *)bus clock:(QLMVirtualClock *)time keeping:(QLMBusPreferences *)kept {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = time;
    [kept fillSettings:settings];
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [kept keepFromSnapshot:snapshot];
    } queue:dispatch_get_main_queue()];
    [system setVolumeDecibels:kept.volumeDecibels];
    [system start];
    return system;
}

// Every monitor last heard this 2B value.
static BOOL QLMAllHeard(QLMFakeBus *bus, uint8_t value) {
    __block BOOL heard = YES;
    [bus perform:^{
        for (QLMFakeMonitor *monitor in bus.monitors) {
            heard = heard && monitor.muteValue == value;
        }
    }];
    return heard;
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

    [bus perform:^{
        for (QLMFakeMonitor *monitor in bus.monitors) {
            monitor.muteValue = 0;
        }
    }];
    QLMSystem *relaunched = [self systemOn:bus clock:time keeping:kept];
    XCTAssertTrue([time runUntil:^BOOL {
        return QLMAllHeard(bus, QLMMuteValueMuted);
    } within:60], @"the next System never restated the mutes");
    // The Mac's sleep may have ended in a shutdown, so a relaunch never
    // lifts the mute by itself, however long its level has been out.
    [time advanceBy:3];
    XCTAssertTrue(QLMAllHeard(bus, QLMMuteValueMuted));
    XCTAssertTrue(relaunched.snapshot.mutingAll);
    XCTAssertFalse(relaunched.snapshot.muteAllFromStop);
    XCTAssertTrue(kept.mutingAll);
    [self stop:relaunched clock:time muting:NO];
}

// The fake bus's knob, as the app makes it: a new demo bus for each launch,
// with its knob put back where the last one read.
- (QLMFakeBus *)fakeBusFor:(QLMBusPreferences *)kept {
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    [kept restoreKnobOn:bus];
    return bus;
}

// Runs the clock until System has both monitors identified and is idle,
// and `test`, if given, holds.
- (QLMSnapshot *)settle:(QLMSystem *)system clock:(QLMVirtualClock *)time until:(nullable BOOL (^)(QLMSnapshot *snapshot))test {
    XCTAssertTrue([time runUntil:^BOOL {
        QLMSnapshot *snapshot = system.snapshot;
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.idle && (test == nil || test(snapshot));
    } within:60]);
    return system.snapshot;
}

// The knob's last reading is kept per bus, from a running System's
// snapshot, and handed to the next one. A first launch has none, so its
// level stands. A relaunch on a fresh fake bus finds the knob where the
// last one left it, so its level stands too. A knob turned between
// launches caps the start at its level, and the level kept follows. The
// real monitors' reading stays apart.
- (void)testAFakeBusRelaunchKeepsItsLevelAndATurnCapsIt {
    QLMVirtualClock *time = [[QLMVirtualClock alloc] init];
    QLMBusPreferences *kept = _preferences.fakeBus;
    XCTAssertFalse(kept.knobRead);
    QLMFakeBus *bus = [self fakeBusFor:kept];
    QLMSystem *system = [self systemOn:bus clock:time keeping:kept];
    QLMSnapshot *first = [self settle:system clock:time until:nil];
    XCTAssertEqualObjects(first.volumeDecibels, @(-40));
    XCTAssertNil(first.startLoweredFromDecibels);
    // A turn while it runs is followed, and kept.
    [bus perform:^{
        bus.knobTenths = @(-500);
    }];
    [self settle:system clock:time until:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-50)] && [kept.knobTenths isEqual:@(-500)];
    }];
    [self stop:system clock:time muting:NO];

    bus = [self fakeBusFor:kept];
    system = [self systemOn:bus clock:time keeping:kept];
    QLMSnapshot *relaunched = [self settle:system clock:time until:nil];
    XCTAssertEqualObjects(relaunched.volumeDecibels, @(-50));
    XCTAssertNil(relaunched.startLoweredFromDecibels);
    [self stop:system clock:time muting:NO];

    bus = [self fakeBusFor:kept];
    [bus perform:^{
        bus.knobTenths = @(-700);
    }];
    system = [self systemOn:bus clock:time keeping:kept];
    QLMSnapshot *turned = [self settle:system clock:time until:nil];
    XCTAssertEqualObjects(turned.volumeDecibels, @(-70));
    XCTAssertEqualObjects(turned.startLoweredFromDecibels, @(-50));
    XCTAssertEqual(kept.volumeDecibels, -70);
    XCTAssertEqualObjects(kept.knobTenths, @(-700));
    [self stop:system clock:time muting:NO];
    XCTAssertFalse(_preferences.adapterBus.knobRead);
}

// A reading is kept with whether one was read, so "no knob" differs from
// "never read". A reading kept wrong reads as no knob, so a knob in at the
// next start counts as moved, and can only cap it.
- (void)testAKnobReadingKeptWrongReadsAsNoKnob {
    QLMBusPreferences *kept = _preferences.adapterBus;
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    [_defaults setObject:@(-300) forKey:@"QLMKnobTenths"];
    XCTAssertFalse(kept.knobRead);
    XCTAssertNil(kept.knobTenths);
    [kept keepKnobTenths:nil];
    XCTAssertTrue(kept.knobRead);
    XCTAssertNil(kept.knobTenths);
    for (id wrong in @[@"-300", @(-300.5), @(5), @(NAN), @[@(-300)]]) {
        [_defaults setObject:wrong forKey:@"QLMKnobTenths"];
        XCTAssertTrue(kept.knobRead, @"%@", wrong);
        XCTAssertNil(kept.knobTenths, @"%@", wrong);
    }
    [kept keepKnobTenths:@(-300)];
    XCTAssertEqualObjects(kept.knobTenths, @(-300));
    [kept fillSettings:settings];
    XCTAssertTrue(settings.knobRead);
    XCTAssertEqualObjects(settings.knobTenths, @(-300));
}

// The Mac's sleep stops System muting where the take-over would be louder.
// The same System's start at wake lifts that mute all once its level is
// out, and the record kept follows, back to no mutes.
- (void)testASleepsMuteLiftsAtWakeAndTheRecordFollows {
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
    XCTAssertTrue(QLMAllHeard(bus, QLMMuteValueMuted));

    [system start];
    XCTAssertTrue([time runUntil:^BOOL {
        QLMSnapshot *snapshot = system.snapshot;
        return !snapshot.muteAllFromStop && snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.idle &&
               QLMAllHeard(bus, QLMMuteValueUnmuted);
    } within:60], @"the wake never lifted the sleep's mute");
    XCTAssertFalse(kept.mutingAll);
    XCTAssertEqual(kept.mutedHardwareIDs.count, 0u);
    XCTAssertEqual(kept.volumeDecibels, -40);
    [self stop:system clock:time muting:NO];
}

#pragma mark - Writes per knob reading

// A running System's snapshot at the level, with the knob read at `knob`.
static QLMSnapshot *QLMKnobSnapshot(double volume, NSNumber *knob) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.volumeDecibels = @(volume);
    QLMAdapterState *adapter = [[QLMAdapterState alloc] init];
    adapter.hasStatus = YES;
    adapter.knobTenths = knob;
    snapshot.adapter = adapter;
    return snapshot;
}

// What a crash now would leave for the next launch: only what is written.
- (QLMBusPreferences *)written {
    _relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
    return _relaunched.adapterBus;
}

// The flushes a bus scheduled, which the test runs.
- (NSMutableArray<dispatch_block_t> *)holdFlushesOf:(QLMBusPreferences *)kept {
    NSMutableArray<dispatch_block_t> *flushes = [NSMutableArray array];
    kept.scheduler = ^(NSTimeInterval delay, dispatch_block_t block) {
        XCTAssertEqual(delay, QLMKeptRaiseDelay);
        [flushes addObject:block];
    };
    return flushes;
}

// A raise of the level and the knob waits, and a second's raises write
// once, the latest. Reads see what waits.
- (void)testRaisesWriteOnceASecond {
    QLMBusPreferences *kept = _preferences.adapterBus;
    NSMutableArray<dispatch_block_t> *flushes = [self holdFlushesOf:kept];
    [kept keepFromSnapshot:QLMKnobSnapshot(-40, @(-400))];
    XCTAssertEqualObjects(self.written.knobTenths, @(-400), @"a first reading writes at once");
    XCTAssertEqual(flushes.count, 0u);

    for (NSNumber *level in @[@(-39), @(-38), @(-37)]) {
        [kept keepFromSnapshot:QLMKnobSnapshot(level.doubleValue, @(level.integerValue * 10))];
    }
    XCTAssertEqual(flushes.count, 1u);
    XCTAssertEqual(kept.volumeDecibels, -37);
    XCTAssertEqualObjects(kept.knobTenths, @(-370));
    XCTAssertEqual(self.written.volumeDecibels, -40);
    XCTAssertEqualObjects(self.written.knobTenths, @(-400));

    flushes.firstObject();
    XCTAssertEqual(self.written.volumeDecibels, -37);
    XCTAssertEqualObjects(self.written.knobTenths, @(-370));
    [kept keepFromSnapshot:QLMKnobSnapshot(-36, @(-360))];
    XCTAssertEqual(flushes.count, 2u, @"the next raise waits again");
}

// AGENTS.md's Safety: a crash can't leave the next launch louder than the
// last level heard. A level or a knob reading lower than the one written
// writes both at once, with a raise waiting or none.
- (void)testALoweringWritesAtOnce {
    QLMBusPreferences *kept = _preferences.adapterBus;
    NSMutableArray<dispatch_block_t> *flushes = [self holdFlushesOf:kept];
    [kept keepFromSnapshot:QLMKnobSnapshot(-40, @(-400))];
    [kept keepFromSnapshot:QLMKnobSnapshot(-45, @(-450))];
    XCTAssertEqual(self.written.volumeDecibels, -45);
    XCTAssertEqualObjects(self.written.knobTenths, @(-450));

    [kept keepFromSnapshot:QLMKnobSnapshot(-30, @(-300))];
    XCTAssertEqual(self.written.volumeDecibels, -45);
    [kept keepFromSnapshot:QLMKnobSnapshot(-50, @(-300))];
    XCTAssertEqual(self.written.volumeDecibels, -50, @"a lower level writes at once");
    XCTAssertEqualObjects(self.written.knobTenths, @(-300), @"and the reading with it");

    [kept keepFromSnapshot:QLMKnobSnapshot(-50, @(-500))];
    XCTAssertEqualObjects(self.written.knobTenths, @(-500), @"a lower reading writes at once");
    [kept keepFromSnapshot:QLMKnobSnapshot(-50, nil)];
    XCTAssertTrue(self.written.knobRead);
    XCTAssertNil(self.written.knobTenths, @"a knob taken out writes at once");
    [kept keepFromSnapshot:QLMKnobSnapshot(-50, @(-500))];
    XCTAssertEqualObjects(self.written.knobTenths, @(-500), @"a knob put in writes at once");
    XCTAssertEqual(flushes.count, 1u);
}

// A snapshot that repeats the last one's values compares nothing with the
// defaults, yet a change made meanwhile by another path is kept right: the
// same snapshot again writes its values back.
- (void)testARepeatedSnapshotStillUndoesAnotherPathsChange {
    QLMBusPreferences *kept = _preferences.adapterBus;
    (void)[self holdFlushesOf:kept];
    QLMSnapshot *snapshot = QLMKnobSnapshot(-40, @(-400));
    snapshot.mutedHardwareIDs = [NSSet setWithObject:QLMID(0xEA)];
    [kept keepFromSnapshot:snapshot];
    XCTAssertTrue([kept saveVolumeDecibels:-35]);
    kept.mutedHardwareIDs = [NSSet set];
    [kept keepFromSnapshot:snapshot];
    XCTAssertEqual(self.written.volumeDecibels, -40, @"a lower level, so at once");
    XCTAssertEqualObjects(self.written.mutedHardwareIDs, [NSSet setWithObject:QLMID(0xEA)]);
}

// A level kept above a lowered ceiling is written down to the level that
// plays, so a ceiling raised again can't bring the louder one back at the
// next launch. The review's probe.
- (void)testALevelAboveALoweredCeilingIsWrittenDown {
    QLMBusPreferences *kept = _preferences.adapterBus;
    NSMutableArray<dispatch_block_t> *flushes = [self holdFlushesOf:kept];
    XCTAssertTrue([_preferences saveCeilingDecibels:0]);
    [kept keepFromSnapshot:QLMKnobSnapshot(-5, @(-50))];
    for (dispatch_block_t flush in flushes) {
        flush();
    }
    [kept flush];
    XCTAssertEqual(self.written.volumeDecibels, -5);
    XCTAssertTrue([_preferences saveCeilingDecibels:-10]);
    [kept keepFromSnapshot:QLMKnobSnapshot(-10, @(-50))];
    XCTAssertTrue([_preferences saveCeilingDecibels:0]);
    [kept keepFromSnapshot:QLMKnobSnapshot(-10, @(-50))];
    XCTAssertEqual(self.written.volumeDecibels, -10);
}

// What a relaunch reads, under a ceiling raised since, decides a lowering.
// A level under the stored one is written at once, not a second later.
- (void)testALoweringUnderAStoredLevelAboveTheCeilingWritesAtOnce {
    [_defaults setDouble:-5 forKey:@"QLMVolumeDecibels"];
    XCTAssertTrue([_preferences saveCeilingDecibels:-10]);
    QLMBusPreferences *kept = _preferences.adapterBus;
    NSMutableArray<dispatch_block_t> *flushes = [self holdFlushesOf:kept];
    XCTAssertTrue([_preferences saveCeilingDecibels:0]);
    [kept keepFromSnapshot:QLMKnobSnapshot(-8, @(-80))];
    XCTAssertEqual(flushes.count, 0u, @"a lowering never waits");
    XCTAssertEqual(self.written.volumeDecibels, -8);
}

// The writes go out off the main queue, in order, and a read anywhere waits
// for those queued before it: a turn down writes each lower level, and a
// relaunch reads the last.
- (void)testAReadSeesEveryWriteQueuedBeforeIt {
    QLMBusPreferences *kept = _preferences.adapterBus;
    NSMutableArray<dispatch_block_t> *flushes = [self holdFlushesOf:kept];
    for (int tenths = -400; tenths >= -600; tenths -= 5) {
        [kept keepFromSnapshot:QLMKnobSnapshot(tenths / 10.0, @(tenths))];
    }
    XCTAssertEqual(flushes.count, 0u, @"a lowering never waits");
    XCTAssertEqual(self.written.volumeDecibels, -60);
    XCTAssertEqualObjects(self.written.knobTenths, @(-600));
}

// Every stop writes what waits: a stopped System's snapshot, and the app's
// flush at quit, sleep, and a change of the adapter setting.
- (void)testEveryStopWritesWhatWaits {
    QLMBusPreferences *kept = _preferences.adapterBus;
    QLMBusPreferences *fake = _preferences.fakeBus;
    (void)[self holdFlushesOf:kept];
    (void)[self holdFlushesOf:fake];
    [kept keepFromSnapshot:QLMKnobSnapshot(-40, @(-400))];
    [kept keepFromSnapshot:QLMKnobSnapshot(-35, @(-350))];
    QLMSnapshot *stopped = [[QLMSnapshot alloc] init];
    stopped.volumeDecibels = @(-35);
    [kept keepFromSnapshot:stopped];
    XCTAssertEqual(self.written.volumeDecibels, -35);
    XCTAssertEqualObjects(self.written.knobTenths, @(-350));

    [kept keepFromSnapshot:QLMKnobSnapshot(-32, @(-320))];
    [fake keepFromSnapshot:QLMKnobSnapshot(-45, @(-450))];
    [fake keepFromSnapshot:QLMKnobSnapshot(-38, @(-380))];
    [_preferences flushKept];
    XCTAssertEqual(self.written.volumeDecibels, -32);
    XCTAssertEqualObjects(self.written.knobTenths, @(-320));
    QLMBusPreferences *writtenFake = self.written;
    writtenFake = _relaunched.fakeBus;
    XCTAssertEqual(writtenFake.volumeDecibels, -38);
    XCTAssertEqualObjects(writtenFake.knobTenths, @(-380));
}

// A turn up on the fake bus while System runs, then its stop, plain or
// muting, as at quit and sleep. The scheduled flush never runs, so only
// the stop's snapshot writes the raise.
- (void)testASystemsStopWritesARaise {
    for (NSNumber *mutes in @[@NO, @YES]) {
        [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
        QLMPreferences *preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
        QLMBusPreferences *kept = preferences.fakeBus;
        kept.scheduler = ^(NSTimeInterval delay, dispatch_block_t block) {
        };
        QLMVirtualClock *time = [[QLMVirtualClock alloc] init];
        QLMFakeBus *bus = [self fakeBusFor:kept];
        [bus perform:^{
            bus.knobTenths = @(-400);
        }];
        QLMSystem *system = [self systemOn:bus clock:time keeping:kept];
        [self settle:system clock:time until:nil];
        [bus perform:^{
            bus.knobTenths = @(-300);
        }];
        [self settle:system clock:time until:^BOOL(QLMSnapshot *snapshot) {
            return [snapshot.volumeDecibels isEqual:@(-30)] && [kept.knobTenths isEqual:@(-300)];
        }];
        (void)self.written;
        QLMBusPreferences *written = _relaunched.fakeBus;
        XCTAssertNotEqual(written.volumeDecibels, -30, @"the raise waits");
        [self stop:system clock:time muting:mutes.boolValue];
        (void)self.written;
        written = _relaunched.fakeBus;
        XCTAssertEqual(written.volumeDecibels, -30, @"muting %@", mutes);
        XCTAssertEqualObjects(written.knobTenths, @(-300), @"muting %@", mutes);
    }
}

@end
