#import <XCTest/XCTest.h>

#import "QLMDSPBlock.h"
#import "QLMFakeBus.h"
#import "QLMSetupInternal.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the hlm protocol spec, revision 13. Section 3 gives the session
// IDs, their start at 02, and re-discovery after four missed polls. Section 9
// gives discovery, enumeration, and the poll loop. The plan's Phase 1 asks
// for fake-bus tests of lease loss, re-discovery, and a lost reply. The
// Phase 2 tests name their sections one by one.
@interface QLMSystemTests : XCTestCase
@end

@implementation QLMSystemTests {
    QLMFakeMonitor *_left;
    QLMFakeMonitor *_right;
    QLMFakeBus *_bus;
    QLMSystemSettings *_settings;
    QLMSystem *_system;
    dispatch_queue_t _snapshots;
    NSMutableArray<QLMSnapshot *> *_received;
}

- (void)setUp {
    [super setUp];
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    _left = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:leftID length:3] serialNumber:@"8320apm21001234"
                                            systemInfo:@"c-1;model-8320A" deviceClass:QLMTelemetryClassTwoWay];
    _right = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:rightID length:3] serialNumber:@"8320apm21005678"
                                             systemInfo:@"c-1;model-8320A" deviceClass:QLMTelemetryClassTwoWay];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _right]];
    _settings = [[QLMSystemSettings alloc] init];
    _settings.cycleInterval = 0.02;
    _settings.ceilingDecibels = -20;
    _snapshots = dispatch_queue_create("qlm.tests.snapshots", DISPATCH_QUEUE_SERIAL);
    _received = [NSMutableArray array];
}

- (void)tearDown {
    [_system stop];
    [super tearDown];
}

- (void)startSystem {
    _system = [[QLMSystem alloc] initWithAdapter:_bus settings:_settings];
    NSMutableArray<QLMSnapshot *> *received = _received;
    [_system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [received addObject:snapshot];
    } queue:_snapshots];
    [_system start];
}

// Waits until the latest snapshot satisfies the predicate, and returns it.
- (QLMSnapshot *)waitForSnapshot:(BOOL (^)(QLMSnapshot *snapshot))predicate {
    return [self waitForSnapshot:predicate after:nil];
}

// The same, with the handler in place before `action` runs.
- (QLMSnapshot *)waitForSnapshot:(BOOL (^)(QLMSnapshot *snapshot))predicate after:(nullable dispatch_block_t)action {
    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshot"];
    __block QLMSnapshot *match = nil;
    __block BOOL fulfilled = NO;
    NSMutableArray<QLMSnapshot *> *received = _received;
    void (^check)(QLMSnapshot *) = ^(QLMSnapshot *snapshot) {
        if (!fulfilled && predicate(snapshot)) {
            fulfilled = YES;
            match = snapshot;
            [expectation fulfill];
        }
    };
    [_system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [received addObject:snapshot];
        check(snapshot);
    } queue:_snapshots];
    if (action != nil) {
        action();
    }
    // TRAP: an earlier action may publish before the handler is in place.
    // Once the System queue has run the handler's setup, the latest snapshot
    // covers whatever the handler missed.
    [_bus perform:^{
    }];
    QLMSnapshot *latest = _system.snapshot;
    dispatch_async(_snapshots, ^{
        check(latest);
    });
    [self waitForExpectations:@[expectation] timeout:5];
    return match;
}

static QLMMonitorState *QLMFindMonitor(QLMSnapshot *snapshot, NSData *hardwareID) {
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if ([monitor.hardwareID isEqualToData:hardwareID]) {
            return monitor;
        }
    }
    return nil;
}

static BOOL QLMIsIdentified(QLMMonitorState *monitor) {
    return monitor != nil && monitor.serialNumber != nil && monitor.systemInfo != nil && monitor.status == QLMMonitorStatusOn;
}

- (QLMSnapshot *)waitForDiscovery {
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMIsIdentified(QLMFindMonitor(snapshot, self->_left.hardwareID)) &&
               QLMIsIdentified(QLMFindMonitor(snapshot, self->_right.hardwareID));
    }];
}

// The messages sent to one address with one opcode, from an index on.
- (NSUInteger)countSentTo:(uint8_t)address opcode:(uint8_t)opcode from:(NSUInteger)start {
    NSUInteger count = 0;
    NSArray<NSData *> *sent = _bus.sentMessages;
    for (NSUInteger i = start; i < sent.count; i++) {
        const uint8_t *bytes = sent[i].bytes;
        if (sent[i].length >= 2 && bytes[0] == address && bytes[1] == opcode) {
            count++;
        }
    }
    return count;
}

// Waits until the condition holds, polling.
- (void)waitUntil:(BOOL (^)(void))condition {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] < 0) {
            XCTFail(@"timed out");
            return;
        }
        [NSThread sleepForTimeInterval:0.005];
    }
}

static NSData *QLMSentBytes(const uint8_t *bytes, size_t length) {
    return [NSData dataWithBytes:bytes length:length];
}

// The messages sent from an index on that equal `message`.
- (NSUInteger)countSent:(NSData *)message from:(NSUInteger)start {
    NSUInteger count = 0;
    NSArray<NSData *> *sent = _bus.sentMessages;
    for (NSUInteger i = start; i < sent.count; i++) {
        if ([sent[i] isEqualToData:message]) {
            count++;
        }
    }
    return count;
}

// The messages sent from an index on whose opcode is `opcode`, any address.
- (NSArray<NSData *> *)sentWithOpcode:(uint8_t)opcode from:(NSUInteger)start {
    NSMutableArray<NSData *> *found = [NSMutableArray array];
    NSArray<NSData *> *sent = _bus.sentMessages;
    for (NSUInteger i = start; i < sent.count; i++) {
        if (sent[i].length >= 2 && ((const uint8_t *)sent[i].bytes)[1] == opcode) {
            [found addObject:sent[i]];
        }
    }
    return found;
}

- (void)testDiscoversLeasesAndIdentifiesEveryMonitor {
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForDiscovery];
    XCTAssertTrue(snapshot.running);
    XCTAssertEqual(snapshot.monitors.count, 2u);

    // Section 3: leases start at 02 and go up by one.
    QLMMonitorState *left = QLMFindMonitor(snapshot, _left.hardwareID);
    QLMMonitorState *right = QLMFindMonitor(snapshot, _right.hardwareID);
    XCTAssertEqual(left.session, 0x02);
    XCTAssertEqual(right.session, 0x03);
    XCTAssertEqualObjects(left.serialNumber, @"8320apm21001234");
    XCTAssertEqualObjects(right.serialNumber, @"8320apm21005678");
    XCTAssertEqualObjects(left.systemInfo, @"c-1;model-8320A");
    XCTAssertEqual(left.status, QLMMonitorStatusOn);
    XCTAssertEqual(left.deviceClass, QLMTelemetryClassTwoWay);
    XCTAssertEqual(left.temperature, 38);
    XCTAssertEqual(left.missedPolls, 0u);
    XCTAssertNotNil(left.lastReply);

    // Section 9's order: probe, assign, then the identity queries.
    NSArray<NSData *> *sent = _bus.sentMessages;
    NSUInteger probe = NSNotFound, assign = NSNotFound, info = NSNotFound;
    for (NSUInteger i = 0; i < sent.count; i++) {
        const uint8_t *bytes = sent[i].bytes;
        if (probe == NSNotFound && bytes[0] == QLMAddressBroadcast && bytes[1] == 0xFE) probe = i;
        if (assign == NSNotFound && bytes[0] == QLMAddressMulticast && bytes[1] == 0x02) assign = i;
        if (info == NSNotFound && bytes[0] == 0x02 && bytes[1] == 0x39) info = i;
    }
    XCTAssertTrue(probe < assign && assign < info);
    XCTAssertGreaterThan([self countSentTo:QLMAddressBroadcast opcode:0x04 from:0], 0u);
}

- (void)testALostReplyDoesNotDropAMonitor {
    [self startSystem];
    [self waitForDiscovery];
    [_bus perform:^{
        self->_left.dropReplies = 1;
    }];
    QLMSnapshot *missed = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).missedPolls == 1;
    }];
    XCTAssertEqual(missed.monitors.count, 2u);
    QLMSnapshot *recovered = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).missedPolls == 0;
    }];
    XCTAssertEqual(recovered.monitors.count, 2u);
    XCTAssertEqual(QLMFindMonitor(recovered, _left.hardwareID).session, 0x02);
}

// Section 3: a re-discovered monitor gets the next unused ID, and the other
// keeps its lease. A monitor that forgot its lease answers the next probe.
- (void)testALostLeaseIsRediscoveredUnderTheNextSession {
    [self startSystem];
    [self waitForDiscovery];
    [_bus perform:^{
        self->_right.session = 0;
    }];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        QLMMonitorState *right = QLMFindMonitor(received, self->_right.hardwareID);
        return right.session == 0x04 && QLMIsIdentified(right);
    }];
    XCTAssertEqual(snapshot.monitors.count, 2u);
    XCTAssertEqual(QLMFindMonitor(snapshot, _left.hardwareID).session, 0x02);
}

// Section 3: four unanswered polls, then a burst to the dead address, then
// the monitor is dropped. Nothing answers, so no probe finds it again.
- (void)testAnUnpluggedMonitorIsDroppedAfterTheRetryBurst {
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger sentBefore = _bus.sentMessages.count;
    [_bus perform:^{
        self->_right.present = NO;
    }];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.monitors.count == 1;
    }];
    XCTAssertEqual(snapshot.monitors.firstObject.session, 0x02);
    NSUInteger pollsToDeadAddress = [self countSentTo:0x03 opcode:0x08 from:sentBefore];
    XCTAssertGreaterThanOrEqual(pollsToDeadAddress, _settings.missedPollsLimit + _settings.retryBurst);
}

// The Safety rule: every volume frame is clamped to the ceiling. And the
// plan: volume goes out at once, at most one frame per 50 ms.
- (void)testVolumeIsClampedAndCoalesced {
    // No cycle may fire inside the test, or it re-sends the volume.
    _settings.cycleInterval = 10;
    _settings.volumeInterval = 0.05;
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.running;
    }];

    [_system setVolumeDecibels:-10];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-10)];
    }];
    [NSThread sleepForTimeInterval:0.1];
    NSArray<NSData *> *sent = _bus.sentMessages;
    const uint8_t clamped[] = {QLMAddressBroadcast, 0x1F, 0x0C, 0xCC, 0xCC};
    XCTAssertTrue([sent containsObject:[NSData dataWithBytes:clamped length:sizeof clamped]]);
    NSUInteger before = sent.count;

    [_system setVolumeDecibels:-30];
    [_system setVolumeDecibels:-35];
    [_system setVolumeDecibels:-40];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-40)];
    }];
    [NSThread sleepForTimeInterval:0.15];
    NSMutableArray<NSData *> *volumes = [NSMutableArray array];
    sent = _bus.sentMessages;
    for (NSUInteger i = before; i < sent.count; i++) {
        const uint8_t *bytes = sent[i].bytes;
        if (bytes[1] == 0x1F) {
            [volumes addObject:sent[i]];
        }
    }
    const uint8_t first[] = {QLMAddressBroadcast, 0x1F, 0x04, 0x0C, 0x37};
    const uint8_t last[] = {QLMAddressBroadcast, 0x1F, 0x01, 0x47, 0xAE};
    XCTAssertEqual(volumes.count, 2u);
    XCTAssertEqualObjects(volumes.firstObject, [NSData dataWithBytes:first length:sizeof first]);
    XCTAssertEqualObjects(volumes.lastObject, [NSData dataWithBytes:last length:sizeof last]);
}

- (void)testStopClearsTheSystem {
    [self startSystem];
    [self waitForDiscovery];
    QLMSystem *system = _system;
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return !received.running;
    } after:^{
        [system stop];
    }];
    XCTAssertEqual(snapshot.monitors.count, 0u);
}

#pragma mark - Mute

// Section 7, 2B, and section 9, "Mute, Solo & Dim": two interleaved rounds
// to every monitor. The target gets 03, the other 04 as state sync. Mute is
// tracked in software.
- (void)testMuteOneMonitor {
    _settings.cycleInterval = 10;
    [self startSystem];
    QLMSnapshot *discovered = [self waitForDiscovery];
    uint8_t left = QLMFindMonitor(discovered, _left.hardwareID).session;
    uint8_t right = QLMFindMonitor(discovered, _right.hardwareID).session;
    NSUInteger before = _bus.sentMessages.count;

    QLMSystem *system = _system;
    NSData *leftID = _left.hardwareID;
    QLMSnapshot *muted = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, leftID).muted;
    } after:^{
        [system setMuted:YES forMonitorWithHardwareID:leftID];
    }];
    XCTAssertFalse(QLMFindMonitor(muted, _right.hardwareID).muted);
    const uint8_t leftMuted[] = {left, 0x2B, QLMMuteValueMuted};
    const uint8_t rightSync[] = {right, 0x2B, QLMMuteValueUnmuted};
    NSArray<NSData *> *expected = @[QLMSentBytes(leftMuted, 3), QLMSentBytes(rightSync, 3), QLMSentBytes(leftMuted, 3), QLMSentBytes(rightSync, 3)];
    XCTAssertEqualObjects([self sentWithOpcode:0x2B from:before], expected);
    // Individual mutes are not preceded by a volume frame.
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 0u);
    [_bus perform:^{
        XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted);
        XCTAssertEqual(self->_right.muteValue, QLMMuteValueUnmuted);
    }];

    before = _bus.sentMessages.count;
    QLMSnapshot *unmuted = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return !QLMFindMonitor(snapshot, leftID).muted;
    } after:^{
        [system setMuted:NO forMonitorWithHardwareID:leftID];
    }];
    XCTAssertFalse(QLMFindMonitor(unmuted, _right.hardwareID).muted);
    XCTAssertEqual([self sentWithOpcode:0x2B from:before].count, 4u);
    XCTAssertEqual([self countSent:QLMSentBytes(leftMuted, 3) from:before], 0u);
    const uint8_t rightMuted[] = {right, 0x2B, QLMMuteValueMuted};
    XCTAssertEqual([self countSent:QLMSentBytes(rightMuted, 3) from:before], 0u);
}

// Section 7, 2B: mute-all is preceded by a volume re-broadcast.
- (void)testMuteAllRebroadcastsTheVolumeFirst {
    _settings.cycleInterval = 10;
    _settings.ceilingDecibels = 0;
    [self startSystem];
    QLMSnapshot *discovered = [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-30)];
    }];
    NSUInteger before = _bus.sentMessages.count;

    QLMSystem *system = _system;
    QLMSnapshot *muted = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if (!monitor.muted) {
                return NO;
            }
        }
        return snapshot.monitors.count == 2;
    } after:^{
        [system setAllMuted:YES];
    }];
    XCTAssertEqual(muted.monitors.count, 2u);
    NSArray<NSData *> *sent = _bus.sentMessages;
    const uint8_t volume[] = {QLMAddressBroadcast, 0x1F, 0x04, 0x0C, 0x37};
    XCTAssertTrue(sent.count > before);
    XCTAssertEqualObjects(sent[before], QLMSentBytes(volume, sizeof volume));
    for (QLMMonitorState *monitor in discovered.monitors) {
        const uint8_t mute[] = {monitor.session, 0x2B, QLMMuteValueMuted};
        XCTAssertEqual([self countSent:QLMSentBytes(mute, 3) from:before], 2u);
    }
    XCTAssertEqual([self sentWithOpcode:0x2B from:before].count, 4u);
}

#pragma mark - Dim

// Section 7, 1F, and section 9, "Mute, Solo & Dim": no dim command, a plain
// volume frame 20 dB down. Dim off restores with an ordinary volume frame.
- (void)testDimSendsAPlainVolumeFrameTwentyDecibelsDown {
    _settings.cycleInterval = 10;
    _settings.ceilingDecibels = 0;
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.running;
    }];
    const uint8_t minus10Bytes[] = {QLMAddressBroadcast, 0x1F, 0x28, 0x7A, 0x26};
    const uint8_t minus30Bytes[] = {QLMAddressBroadcast, 0x1F, 0x04, 0x0C, 0x37};
    const uint8_t minus40Bytes[] = {QLMAddressBroadcast, 0x1F, 0x01, 0x47, 0xAE};
    NSData *minus10 = QLMSentBytes(minus10Bytes, 5);
    NSData *minus30 = QLMSentBytes(minus30Bytes, 5);
    NSData *minus40 = QLMSentBytes(minus40Bytes, 5);

    [_system setVolumeDecibels:-10];
    [self waitUntil:^BOOL {
        return [self countSent:minus10 from:0] == 1;
    }];

    NSUInteger before = _bus.sentMessages.count;
    QLMSystem *system = _system;
    QLMSnapshot *dimmed = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.dimmed;
    } after:^{
        [system setDimmed:YES];
    }];
    XCTAssertEqualObjects(dimmed.volumeDecibels, @(-10));
    [self waitUntil:^BOOL {
        return [self countSent:minus30 from:before] == 1;
    }];

    before = _bus.sentMessages.count;
    [_system setDimmed:NO];
    [self waitUntil:^BOOL {
        return [self countSent:minus10 from:before] == 1 && !self->_system.snapshot.dimmed;
    }];

    // A volume change while dimmed stores the volume and sends it dimmed.
    [_system setDimmed:YES];
    [_system setVolumeDecibels:-20];
    [self waitUntil:^BOOL {
        QLMSnapshot *snapshot = self->_system.snapshot;
        return [self countSent:minus40 from:before] == 1 && [snapshot.volumeDecibels isEqual:@(-20)] && snapshot.dimmed;
    }];
}

// Section 7, 1F: the cycle re-sends the volume, and while dimmed that is the
// dimmed word.
- (void)testTheCycleResendsTheDimmedVolume {
    _settings.ceilingDecibels = 0;
    [self startSystem];
    [self waitForDiscovery];
    [_system setDimmed:YES];
    [_system setVolumeDecibels:-10];
    const uint8_t minus30[] = {QLMAddressBroadcast, 0x1F, 0x04, 0x0C, 0x37};
    NSData *dimmed = QLMSentBytes(minus30, 5);
    __block NSUInteger first = NSNotFound;
    [self waitUntil:^BOOL {
        NSArray<NSData *> *sent = self->_bus.sentMessages;
        first = [sent indexOfObject:dimmed];
        return first != NSNotFound && [self countSent:dimmed from:first] >= 3;
    }];
    for (NSData *volume in [self sentWithOpcode:0x1F from:first]) {
        XCTAssertEqualObjects(volume, dimmed);
    }
}

#pragma mark - Power

// Section 7, 3A 03, and section 9, "System Power": sleep is 03 02 twice,
// then 03 00 twice, on the broadcast address.
- (void)testSleepThenWake {
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger before = _bus.sentMessages.count;
    [_system sleep];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.monitors[0].status == QLMMonitorStatusStandby &&
               snapshot.monitors[1].status == QLMMonitorStatusStandby;
    }];
    const uint8_t prepare[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x02};
    const uint8_t off[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x00};
    NSArray<NSData *> *sleep = @[QLMSentBytes(prepare, 4), QLMSentBytes(prepare, 4), QLMSentBytes(off, 4), QLMSentBytes(off, 4)];
    XCTAssertEqualObjects([self sentWithOpcode:0x3A from:before], sleep);

    // Section 9, "System Power": wake is 03 7F then 03 01, three times.
    before = _bus.sentMessages.count;
    [_system wake];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.monitors[0].status == QLMMonitorStatusOn &&
               snapshot.monitors[1].status == QLMMonitorStatusOn;
    }];
    const uint8_t first[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x7F};
    const uint8_t second[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x01};
    NSMutableArray<NSData *> *wake = [NSMutableArray array];
    for (int pair = 0; pair < 3; pair++) {
        [wake addObject:QLMSentBytes(first, 4)];
        [wake addObject:QLMSentBytes(second, 4)];
    }
    XCTAssertEqualObjects([self sentWithOpcode:0x3A from:before], wake);
}

#pragma mark - Group apply

- (QLMSetup *)fixture {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"Main" ofType:@"sam"];
    if (path == nil) {
        path = [[[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Setups/Fixtures/Main.sam"];
    }
    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readFileAtPath:path error:&error];
    XCTAssertNotNil(setup, @"%@", error);
    return setup;
}

// "Main 4x2" with only its two 8330A, nodes 0 and 2: two-way at 48 kHz, so
// their design rate is verified.
- (QLMSetupGroup *)mainsGroup:(QLMSetup *)setup {
    QLMSetupGroup *source = setup.groups[0];
    QLMSetupGroup *group = [[QLMSetupGroup alloc] init];
    group.name = @"Mains";
    group.groupSensitivity = source.groupSensitivity;
    group.crossover = source.crossover;
    group.crossoverGlobalMode = source.crossoverGlobalMode;
    group.videoDelay = source.videoDelay;
    group.subwooferBypass = source.subwooferBypass;
    group.lowShelf = source.lowShelf;
    group.highShelf = source.highShelf;
    group.nodes = @[source.nodes[0], source.nodes[2]];
    return group;
}

// Two 8330A whose bus serials end in the fixture's 1000005 and 1000004.
- (void)useMainsMonitors {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    _left = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:leftID length:3] serialNumber:@"8330apm21000005"
                                            systemInfo:@"c-1;model-8330A" deviceClass:QLMTelemetryClassTwoWay];
    _right = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:rightID length:3] serialNumber:@"8330apm21000004"
                                             systemInfo:@"c-1;model-8330A" deviceClass:QLMTelemetryClassTwoWay];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _right]];
}

- (NSError *)applyGroup:(QLMSetupGroup *)group inSetup:(QLMSetup *)setup {
    XCTestExpectation *expectation = [self expectationWithDescription:@"apply"];
    __block NSError *result = nil;
    [_system applyGroup:group inSetup:setup completion:^(NSError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        result = error;
        [expectation fulfill];
    }];
    [self waitForExpectations:@[expectation] timeout:5];
    return result;
}

// The Safety rule and section 9, "Apply / Group": the 8351B in "Main 4x2"
// has an unverified design rate, so the apply is refused and sends nothing.
- (void)testApplyRefusesAnUnverifiedRate {
    _settings.cycleInterval = 10;
    [self useMainsMonitors];
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger before = _bus.sentMessages.count;
    QLMSetup *setup = [self fixture];
    NSError *error = [self applyGroup:setup.groups[0] inSetup:setup];
    XCTAssertEqualObjects(error.domain, QLMSystemErrorDomain);
    XCTAssertEqual(error.code, QLMSystemErrorUnverifiedRate);
    [NSThread sleepForTimeInterval:0.05];
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 0u);
    XCTAssertEqual([self sentWithOpcode:0x3A from:before].count, 0u);
    XCTAssertEqual([self sentWithOpcode:0x10 from:before].count, 0u);
    XCTAssertEqual(_bus.sentMessages.count, before);
    XCTAssertNil(_system.snapshot.activeGroupName);
}

// The plan's matching rule: a node matches the monitor whose serial ends in
// the node's. These monitors' serials match neither node.
- (void)testApplyRefusesANodeWithNoMonitor {
    _settings.cycleInterval = 10;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.volumeDecibels != nil;
    }];
    [NSThread sleepForTimeInterval:0.05];
    NSUInteger before = _bus.sentMessages.count;
    QLMSetup *setup = [self fixture];
    NSError *error = [self applyGroup:[self mainsGroup:setup] inSetup:setup];
    XCTAssertEqualObjects(error.domain, QLMSystemErrorDomain);
    XCTAssertEqual(error.code, QLMSystemErrorUnknownMonitor);
    [NSThread sleepForTimeInterval:0.05];
    XCTAssertEqual(_bus.sentMessages.count, before);
}

static NSArray<NSData *> *QLMBlockFrames(QLMDSPBlock *block, uint8_t session) {
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    for (NSData *payload in block.payloads) {
        NSMutableData *frame = [NSMutableData dataWithBytes:&session length:1];
        [frame appendData:payload];
        [frames addObject:frame];
    }
    return frames;
}

// Section 9, "Apply / Group": duck, wake, per monitor 2B 04 and routing,
// then 04 and the DSP block per monitor, then the volume five times and
// 2B and 3D per monitor. qlm leaves out GLM's 05 04 00 (section 7's 05 is
// on the never-send list).
- (void)testVerifiedApplySendsGLMsSequence {
    _settings.cycleInterval = 10;
    _settings.ceilingDecibels = 0;
    [self useMainsMonitors];
    [self startSystem];
    QLMSnapshot *discovered = [self waitForDiscovery];
    uint8_t first = QLMFindMonitor(discovered, _left.hardwareID).session;   // node 0, serial 1000005
    uint8_t second = QLMFindMonitor(discovered, _right.hardwareID).session; // node 2, serial 1000004
    [_system setMuted:YES forMonitorWithHardwareID:_right.hardwareID];
    [_system setVolumeDecibels:-10];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_right.hardwareID).muted && snapshot.volumeDecibels != nil;
    }];
    [NSThread sleepForTimeInterval:0.1];

    QLMSetup *setup = [self fixture];
    QLMSetupGroup *group = [self mainsGroup:setup];
    NSArray<QLMDSPBlock *> *blocks = [QLMDSPBlock blocksForGroup:group error:NULL];
    XCTAssertEqual(blocks.count, 2u);
    NSUInteger before = _bus.sentMessages.count;
    QLMSystem *system = _system;
    __block BOOL sawApplying = NO;
    __block NSError *result = nil;
    XCTestExpectation *done = [self expectationWithDescription:@"apply"];
    QLMSnapshot *applied = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        sawApplying = sawApplying || snapshot.applying;
        return snapshot.activeGroupName != nil;
    } after:^{
        [system applyGroup:group inSetup:setup completion:^(NSError *error) {
            result = error;
            [done fulfill];
        }];
    }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertNil(result);
    XCTAssertTrue(sawApplying);
    XCTAssertFalse(applied.applying);
    XCTAssertEqualObjects(applied.activeGroupName, @"Mains");

    NSMutableArray<NSData *> *expected = [NSMutableArray array];
    const uint8_t duckMin[] = {QLMAddressBroadcast, 0x1F, 0x00, 0x00, 0x08};
    const uint8_t duck[] = {QLMAddressBroadcast, 0x1F, 0x00, 0x00, 0x02};
    [expected addObject:QLMSentBytes(duckMin, 5)];
    [expected addObject:QLMSentBytes(duck, 5)];
    const uint8_t wakeFirst[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x7F};
    const uint8_t wakeSecond[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x01};
    [expected addObject:QLMSentBytes(wakeFirst, 4)];
    [expected addObject:QLMSentBytes(wakeFirst, 4)];
    [expected addObject:QLMSentBytes(wakeSecond, 4)];
    const uint8_t sessions[2] = {first, second};
    for (int i = 0; i < 2; i++) {
        const uint8_t unmute[] = {sessions[i], 0x2B, QLMMuteValueUnmuted};
        [expected addObject:QLMSentBytes(unmute, 3)];
        [expected addObject:QLMBlockFrames(blocks[(NSUInteger)i], sessions[i]).lastObject];
    }
    const uint8_t keepAlive[] = {QLMAddressBroadcast, 0x04};
    for (int i = 0; i < 2; i++) {
        [expected addObject:QLMSentBytes(keepAlive, 2)];
        NSArray<NSData *> *frames = QLMBlockFrames(blocks[(NSUInteger)i], sessions[i]);
        XCTAssertEqual(frames.count, 27u);
        const uint8_t prepare[] = {sessions[i], 0x17, 0x01};
        XCTAssertEqualObjects(frames.firstObject, QLMSentBytes(prepare, 3));
        XCTAssertEqual(((const uint8_t *)frames.lastObject.bytes)[1], 0x40);
        [expected addObjectsFromArray:frames];
    }
    const uint8_t volume[] = {QLMAddressBroadcast, 0x1F, 0x28, 0x7A, 0x26};
    for (int i = 0; i < 5; i++) {
        [expected addObject:QLMSentBytes(volume, 5)];
    }
    const uint8_t restoreFirst[] = {first, 0x2B, QLMMuteValueUnmuted};
    const uint8_t restoreSecond[] = {second, 0x2B, QLMMuteValueMuted};
    const uint8_t syncFirst[] = {first, 0x3D, 0x00, 0x00};
    const uint8_t syncSecond[] = {second, 0x3D, 0x00, 0x00};
    [expected addObject:QLMSentBytes(restoreFirst, 3)];
    [expected addObject:QLMSentBytes(syncFirst, 4)];
    [expected addObject:QLMSentBytes(restoreSecond, 3)];
    [expected addObject:QLMSentBytes(syncSecond, 4)];

    NSArray<NSData *> *sent = _bus.sentMessages;
    XCTAssertGreaterThanOrEqual(sent.count, before + expected.count);
    if (sent.count >= before + expected.count) {
        XCTAssertEqualObjects([sent subarrayWithRange:NSMakeRange(before, expected.count)], expected);
    }
    [_bus perform:^{
        XCTAssertEqual(self->_right.muteValue, QLMMuteValueMuted);
    }];
}

// A second apply while one runs is refused.
- (void)testASecondApplyIsRefusedWhileOneRuns {
    _settings.cycleInterval = 10;
    [self useMainsMonitors];
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    QLMSetup *setup = [self fixture];
    QLMSetupGroup *group = [self mainsGroup:setup];
    XCTestExpectation *firstDone = [self expectationWithDescription:@"first"];
    XCTestExpectation *secondDone = [self expectationWithDescription:@"second"];
    __block NSError *firstError = nil;
    __block NSError *secondError = nil;
    [_system applyGroup:group inSetup:setup completion:^(NSError *error) {
        firstError = error;
        [firstDone fulfill];
    }];
    [_system applyGroup:group inSetup:setup completion:^(NSError *error) {
        secondError = error;
        [secondDone fulfill];
    }];
    [self waitForExpectations:@[firstDone, secondDone] timeout:5];
    XCTAssertNil(firstError);
    XCTAssertEqual(secondError.code, QLMSystemErrorAlreadyApplying);
}

@end
