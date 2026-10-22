#import <XCTest/XCTest.h>

#import "QLMFakeBus.h"
#import "QLMSystem.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the hlm protocol spec, revision 13. Section 3 gives the session
// IDs, their start at 02, and re-discovery after four missed polls. Section 9
// gives discovery, enumeration, and the poll loop. The plan's Phase 1 asks
// for fake-bus tests of lease loss, re-discovery, and a lost reply.
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

// Waits until a published snapshot satisfies the predicate, and returns it.
- (QLMSnapshot *)waitForSnapshot:(BOOL (^)(QLMSnapshot *snapshot))predicate {
    return [self waitForSnapshot:predicate after:nil];
}

// The same, with the handler in place before `action` runs.
- (QLMSnapshot *)waitForSnapshot:(BOOL (^)(QLMSnapshot *snapshot))predicate after:(nullable dispatch_block_t)action {
    XCTestExpectation *expectation = [self expectationWithDescription:@"snapshot"];
    __block QLMSnapshot *match = nil;
    __block BOOL fulfilled = NO;
    NSMutableArray<QLMSnapshot *> *received = _received;
    [_system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [received addObject:snapshot];
        if (!fulfilled && predicate(snapshot)) {
            fulfilled = YES;
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

@end
