#import <XCTest/XCTest.h>

#import "QLMControl.h"
#import "QLMPreferences.h"
#import "QLMSnapshotInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"

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
        _preferences.ceilingDecibels = saved.doubleValue;
        QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
        XCTAssertEqual(relaunched.ceilingDecibels, saved.doubleValue);
    }
}

#pragma mark - Each bus keeps its own

// A level set on the fake bus never reaches the real monitors, nor theirs
// the fake bus.
- (void)testEachBusKeepsItsOwnLevel {
    _preferences.fakeBus.volumeDecibels = -35;
    XCTAssertEqual(_preferences.adapterBus.volumeDecibels, -40);
    _preferences.adapterBus.volumeDecibels = -50;
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

@end
