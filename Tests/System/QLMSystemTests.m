#import <XCTest/XCTest.h>

#import "QLMDSPBlock.h"
#import "QLMFakeBus.h"
#import "QLMReplayAdapter.h"
#import "QLMSetupInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
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
    [self startSystemWithAdapter:_bus];
}

- (void)startSystemWithAdapter:(id<QLMAdapter>)adapter {
    _system = [[QLMSystem alloc] initWithAdapter:adapter settings:_settings];
    NSMutableArray<QLMSnapshot *> *received = _received;
    [_system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [received addObject:snapshot];
    } queue:_snapshots];
    [_system start];
}

// Waits until a snapshot satisfies the predicate, and returns it.
- (QLMSnapshot *)waitForSnapshot:(BOOL (^)(QLMSnapshot *snapshot))predicate {
    return [self waitForSnapshot:predicate after:nil];
}

// The same, with the handler in place before `action` runs. The handler gets
// the latest snapshot first, so a state reached earlier is seen.
- (QLMSnapshot *)waitForSnapshot:(BOOL (^)(QLMSnapshot *snapshot))predicate after:(nullable dispatch_block_t)action {
    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshot"];
    __block QLMSnapshot *match = nil;
    NSMutableArray<QLMSnapshot *> *received = _received;
    [_system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [received addObject:snapshot];
        if (match == nil && predicate(snapshot)) {
            match = snapshot;
            [expectation fulfill];
        }
    } queue:_snapshots];
    if (action != nil) {
        action();
    }
    [self waitForExpectations:@[expectation] timeout:5];
    return match;
}

// Waits until nothing is queued for the bus or in flight.
- (void)waitForIdle {
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    }];
}

static QLMMonitorState *QLMFindMonitor(QLMSnapshot *snapshot, NSData *hardwareID) {
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if ([monitor.hardwareID isEqualToData:hardwareID]) {
            return monitor;
        }
    }
    return nil;
}

- (QLMSnapshot *)waitForDiscovery {
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.anyOn;
    }];
}

// The messages sent from an index on that pass the test.
- (NSArray<NSData *> *)sentFrom:(NSUInteger)start matching:(BOOL (^)(NSData *message))test {
    NSArray<NSData *> *sent = _bus.sentMessages;
    NSMutableArray<NSData *> *found = [NSMutableArray array];
    for (NSUInteger i = start; i < sent.count; i++) {
        if (test(sent[i])) {
            [found addObject:sent[i]];
        }
    }
    return found;
}

- (NSArray<NSData *> *)sentWithOpcode:(uint8_t)opcode from:(NSUInteger)start {
    return [self sentFrom:start matching:^BOOL(NSData *message) {
        return message.length >= 2 && ((const uint8_t *)message.bytes)[1] == opcode;
    }];
}

- (NSUInteger)countSentTo:(uint8_t)address opcode:(uint8_t)opcode from:(NSUInteger)start {
    return [self sentFrom:start matching:^BOOL(NSData *message) {
        const uint8_t *bytes = message.bytes;
        return message.length >= 2 && bytes[0] == address && bytes[1] == opcode;
    }].count;
}

- (NSUInteger)countSent:(NSData *)expected from:(NSUInteger)start {
    return [self sentFrom:start matching:^BOOL(NSData *message) {
        return [message isEqualToData:expected];
    }].count;
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
    XCTAssertEqualObjects(left.model, @"8320A");
    XCTAssertNil(left.firmwareVersion);
    XCTAssertTrue(left.identified);
    XCTAssertEqual(left.status, QLMMonitorStatusOn);
    XCTAssertEqual(left.deviceClass, QLMMonitorClassTwoWay);
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
        return right.session == 0x04 && right.identified;
    }];
    XCTAssertEqual(snapshot.monitors.count, 2u);
    XCTAssertEqual(QLMFindMonitor(snapshot, _left.hardwareID).session, 0x02);
}

// A crowded bus runs the leases past 7C in one discovery. They skip 7D and
// 7E, which no capture shows as an address, and F0, the adapter's multicast.
- (void)testLeasesSkipAddressesThatNeedEscapingAndTheMulticast {
    NSMutableArray<QLMFakeMonitor *> *monitors = [NSMutableArray array];
    for (NSUInteger i = 0; i < 240; i++) {
        const uint8_t hardwareID[3] = {0xA0, (uint8_t)(i >> 8), (uint8_t)i};
        NSString *serial = [NSString stringWithFormat:@"8320apm2100%04lu", (unsigned long)i];
        [monitors addObject:[[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:hardwareID length:3] serialNumber:serial
                                                            systemInfo:@"c-1;model-8320A" deviceClass:QLMTelemetryClassTwoWay]];
    }
    _bus = [[QLMFakeBus alloc] initWithMonitors:monitors];
    _settings.cycleInterval = 10;
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.monitors.count == 240 && received.allIdentified;
    }];
    NSMutableIndexSet *sessions = [NSMutableIndexSet indexSet];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        XCTAssertTrue(QLMAddressIsLeasable(monitor.session), @"%02X", monitor.session);
        [sessions addIndex:monitor.session];
    }
    XCTAssertEqual(sessions.count, 240u);
    XCTAssertTrue([sessions containsIndex:0x7C] && [sessions containsIndex:0x7F]);
    XCTAssertTrue([sessions containsIndex:0xEF] && [sessions containsIndex:0xF1]);
}

// captures/startup-idle, where GLM finds the user's six monitors: two 8330A,
// two 8351B, a 7370A, and a 7350A, all on. System's discovery sends what GLM
// sent, in GLM's lease order, so the replay answers it.
- (void)testDiscoversEveryMonitorInAReplayOfStartupIdle {
    NSError *error = nil;
    QLMCapture *capture = QLMReadCapture(@"startup-idle", &error);
    XCTAssertNotNil(capture, @"%@", error);
    _settings.cycleInterval = 0.05;
    [self startSystemWithAdapter:[[QLMReplayAdapter alloc] initWithCapture:capture]];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        BOOL known = received.monitors.count == 6 && received.allIdentified;
        for (QLMMonitorState *monitor in received.monitors) {
            known = known && monitor.deviceClass != QLMMonitorClassUnknown;
        }
        return known;
    }];

    NSDictionary<NSString *, NSArray *> *expected = @{
        @"8330A": @[@"1.14.7.6281", @(QLMMonitorClassTwoWay)],
        @"8351B": @[@"1.24.07.6470", @(QLMMonitorClassTwoWay)],
        @"7370A": @[@"1.14.7.6281", @(QLMMonitorClassSubwoofer)],
        @"7350A": @[@"1.14.7.6281", @(QLMMonitorClassSubwoofer)],
    };
    NSCountedSet<NSString *> *models = [NSCountedSet set];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        NSArray *facts = expected[monitor.model];
        XCTAssertNotNil(facts, @"%@", monitor.model);
        [models addObject:monitor.model ?: @""];
        XCTAssertEqualObjects(monitor.firmwareVersion, facts[0]);
        XCTAssertEqual(monitor.deviceClass, [facts[1] integerValue]);
        XCTAssertTrue([monitor.serialNumber hasPrefix:monitor.model], @"%@", monitor.serialNumber);
        XCTAssertEqual(monitor.status, QLMMonitorStatusOn);
        XCTAssertGreaterThan(monitor.temperature, 0);
    }
    XCTAssertEqual([models countForObject:@"8330A"], 2u);
    XCTAssertEqual([models countForObject:@"8351B"], 2u);
    XCTAssertEqual([models countForObject:@"7370A"], 1u);
    XCTAssertEqual([models countForObject:@"7350A"], 1u);
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
    NSArray<NSData *> *expected = @[QLMBytes(leftMuted, 3), QLMBytes(rightSync, 3), QLMBytes(leftMuted, 3), QLMBytes(rightSync, 3)];
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
    XCTAssertEqual([self countSent:QLMBytes(leftMuted, 3) from:before], 0u);
    const uint8_t rightMuted[] = {right, 0x2B, QLMMuteValueMuted};
    XCTAssertEqual([self countSent:QLMBytes(rightMuted, 3) from:before], 0u);
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
        return snapshot.allMuted;
    } after:^{
        [system setAllMuted:YES];
    }];
    XCTAssertEqual(muted.monitors.count, 2u);
    NSArray<NSData *> *sent = _bus.sentMessages;
    const uint8_t volume[] = {QLMAddressBroadcast, 0x1F, 0x04, 0x0C, 0x37};
    XCTAssertTrue(sent.count > before);
    XCTAssertEqualObjects(sent[before], QLMBytes(volume, sizeof volume));
    for (QLMMonitorState *monitor in discovered.monitors) {
        const uint8_t mute[] = {monitor.session, 0x2B, QLMMuteValueMuted};
        XCTAssertEqual([self countSent:QLMBytes(mute, 3) from:before], 2u);
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
    NSData *minus10 = QLMBytes(minus10Bytes, 5);
    NSData *minus30 = QLMBytes(minus30Bytes, 5);
    NSData *minus40 = QLMBytes(minus40Bytes, 5);

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
    NSData *dimmed = QLMBytes(minus30, 5);
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
    NSArray<NSData *> *sleep = @[QLMBytes(prepare, 4), QLMBytes(prepare, 4), QLMBytes(off, 4), QLMBytes(off, 4)];
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
        [wake addObject:QLMBytes(first, 4)];
        [wake addObject:QLMBytes(second, 4)];
    }
    XCTAssertEqualObjects([self sentWithOpcode:0x3A from:before], wake);
}

#pragma mark - Group apply

// A group named `name` with the settings of `source` and only `nodes`.
- (QLMSetupGroup *)groupNamed:(NSString *)name from:(QLMSetupGroup *)source nodes:(NSArray<QLMSetupNode *> *)nodes {
    QLMSetupGroup *group = [[QLMSetupGroup alloc] init];
    group.name = name;
    group.groupSensitivity = source.groupSensitivity;
    group.crossover = source.crossover;
    group.crossoverGlobalMode = source.crossoverGlobalMode;
    group.videoDelay = source.videoDelay;
    group.subwooferBypass = source.subwooferBypass;
    group.lowShelf = source.lowShelf;
    group.highShelf = source.highShelf;
    group.nodes = nodes;
    return group;
}

// "Main 4x2" with only its two 8330A, nodes 0 and 2: two-way at 48 kHz, so
// their design rate is verified.
- (QLMSetupGroup *)mainsGroup {
    QLMSetupGroup *source = QLMReadFixtureSetup().groups[0];
    return [self groupNamed:@"Mains" from:source nodes:@[source.nodes[0], source.nodes[2]]];
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

- (NSError *)applyGroup:(QLMSetupGroup *)group {
    XCTestExpectation *expectation = [self expectationWithDescription:@"apply"];
    __block NSError *result = nil;
    [_system applyGroup:group completion:^(NSError *error) {
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
    NSError *error = [self applyGroup:QLMReadFixtureSetup().groups[0]];
    XCTAssertEqualObjects(error.domain, QLMSystemErrorDomain);
    XCTAssertEqual(error.code, QLMSystemErrorUnverifiedRate);
    [self waitForIdle];
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
        return snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    NSUInteger before = _bus.sentMessages.count;
    NSError *error = [self applyGroup:[self mainsGroup]];
    XCTAssertEqualObjects(error.domain, QLMSystemErrorDomain);
    XCTAssertEqual(error.code, QLMSystemErrorUnknownMonitor);
    [self waitForIdle];
    XCTAssertEqual(_bus.sentMessages.count, before);
}

static NSArray<NSData *> *QLMBlockFrames(QLMDSPBlock *block, uint8_t session) {
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    for (NSData *payload in block.payloads) {
        [frames addObject:[QLMFakeBus recordForSession:session payload:payload]];
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
        return QLMFindMonitor(snapshot, self->_right.hardwareID).muted && snapshot.volumeDecibels != nil && snapshot.idle;
    }];

    QLMSetupGroup *group = [self mainsGroup];
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
        [system applyGroup:group completion:^(NSError *error) {
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
    [expected addObject:QLMBytes(duckMin, 5)];
    [expected addObject:QLMBytes(duck, 5)];
    const uint8_t wakeFirst[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x7F};
    const uint8_t wakeSecond[] = {QLMAddressBroadcast, 0x3A, 0x03, 0x01};
    [expected addObject:QLMBytes(wakeFirst, 4)];
    [expected addObject:QLMBytes(wakeFirst, 4)];
    [expected addObject:QLMBytes(wakeSecond, 4)];
    const uint8_t sessions[2] = {first, second};
    for (int i = 0; i < 2; i++) {
        const uint8_t unmute[] = {sessions[i], 0x2B, QLMMuteValueUnmuted};
        [expected addObject:QLMBytes(unmute, 3)];
        [expected addObject:QLMBlockFrames(blocks[(NSUInteger)i], sessions[i]).lastObject];
    }
    const uint8_t keepAlive[] = {QLMAddressBroadcast, 0x04};
    for (int i = 0; i < 2; i++) {
        [expected addObject:QLMBytes(keepAlive, 2)];
        NSArray<NSData *> *frames = QLMBlockFrames(blocks[(NSUInteger)i], sessions[i]);
        XCTAssertEqual(frames.count, 27u);
        const uint8_t prepare[] = {sessions[i], 0x17, 0x01};
        XCTAssertEqualObjects(frames.firstObject, QLMBytes(prepare, 3));
        XCTAssertEqual(((const uint8_t *)frames.lastObject.bytes)[1], 0x40);
        [expected addObjectsFromArray:frames];
    }
    const uint8_t volume[] = {QLMAddressBroadcast, 0x1F, 0x28, 0x7A, 0x26};
    for (int i = 0; i < 5; i++) {
        [expected addObject:QLMBytes(volume, 5)];
    }
    const uint8_t restoreFirst[] = {first, 0x2B, QLMMuteValueUnmuted};
    const uint8_t restoreSecond[] = {second, 0x2B, QLMMuteValueMuted};
    const uint8_t syncFirst[] = {first, 0x3D, 0x00, 0x00};
    const uint8_t syncSecond[] = {second, 0x3D, 0x00, 0x00};
    [expected addObject:QLMBytes(restoreFirst, 3)];
    [expected addObject:QLMBytes(syncFirst, 4)];
    [expected addObject:QLMBytes(restoreSecond, 3)];
    [expected addObject:QLMBytes(syncSecond, 4)];

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
    QLMSetupGroup *group = [self mainsGroup];
    XCTestExpectation *firstDone = [self expectationWithDescription:@"first"];
    XCTestExpectation *secondDone = [self expectationWithDescription:@"second"];
    __block NSError *firstError = nil;
    __block NSError *secondError = nil;
    [_system applyGroup:group completion:^(NSError *error) {
        firstError = error;
        [firstDone fulfill];
    }];
    [_system applyGroup:group completion:^(NSError *error) {
        secondError = error;
        [secondDone fulfill];
    }];
    [self waitForExpectations:@[firstDone, secondDone] timeout:5];
    XCTAssertNil(firstError);
    XCTAssertEqual(secondError.code, QLMSystemErrorAlreadyApplying);
}

// An apply for a group whose nodes are all off has no per-monitor frames.
// The duck, the wake, and the volume restore still go out, and it finishes.
- (void)testApplyOfAGroupWithEveryNodeOffFinishes {
    _settings.cycleInterval = 10;
    [self useMainsMonitors];
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    // In "Main 2x2" the two 8330A, nodes 0 and 2, are off.
    QLMSetupGroup *source = QLMReadFixtureSetup().groups[1];
    QLMSetupGroup *group = [self groupNamed:@"Off" from:source nodes:@[source.nodes[0], source.nodes[2]]];
    XCTAssertEqual([QLMDSPBlock blocksForGroup:group error:NULL].count, 0u);

    NSUInteger before = _bus.sentMessages.count;
    XCTAssertNil([self applyGroup:group]);
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 7u);  // two duck frames, five restores
    XCTAssertEqual([self sentWithOpcode:0x3A from:before].count, 3u);
    XCTAssertEqual([self sentWithOpcode:0x2B from:before].count, 0u);
    XCTAssertEqual([self sentWithOpcode:0x10 from:before].count, 0u);

    XCTAssertNil([self applyGroup:group]);
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return !received.applying && [received.activeGroupName isEqualToString:@"Off"];
    }];
    XCTAssertTrue(snapshot.idle);
}

@end
