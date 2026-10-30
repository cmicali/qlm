#import <XCTest/XCTest.h>

#import "QLMApplySequence.h"
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
    // The adapter polls only at start, so the tests that count frames see
    // none but GLM's opening pair. The adapter's own tests turn them on.
    _settings.adapterPollInterval = 0;
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

// Waits for `count` more of the adapter's polls, each a reading of the knob.
- (void)waitForAdapterPolls:(NSUInteger)count {
    NSUInteger start = _bus.sentMessages.count;
    [self waitUntil:^BOOL {
        return [self countSentTo:QLMAddressAdapter opcode:0x08 from:start] >= count;
    }];
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
    // captures/startup-idle: GLM's idle cycle has no keep-alive.
    XCTAssertEqual([self countSentTo:QLMAddressBroadcast opcode:0x04 from:0], 0u);

    // GLM's opening: the adapter's status twice, its system info, its
    // serial, then the probe.
    const uint8_t poll[] = {QLMAddressAdapter, 0x08};
    const uint8_t info39[] = {QLMAddressAdapter, 0x39};
    const uint8_t serial[] = {QLMAddressAdapter, 0x19, 0x01};
    const uint8_t probeBytes[] = {QLMAddressBroadcast, 0xFE};
    NSArray<NSData *> *opening = @[QLMBytes(poll, 2), QLMBytes(poll, 2), QLMBytes(info39, 2), QLMBytes(serial, 3), QLMBytes(probeBytes, 2)];
    XCTAssertEqualObjects([sent subarrayWithRange:NSMakeRange(0, opening.count)], opening);
    XCTAssertTrue(snapshot.adapter.identified);
    XCTAssertEqualObjects(snapshot.adapter.model, @"GLM Adapter");
    XCTAssertEqualObjects(snapshot.adapter.firmwareVersion, @"1.4.0.6113");
    XCTAssertEqualObjects(snapshot.adapter.serialNumber, @"H00000F001");
    XCTAssertEqualObjects(snapshot.adapter.knobTenths, @(-1004));
    XCTAssertEqualObjects(snapshot.adapter.device, @"a fake bus of 2 monitors");
    XCTAssertNil(snapshot.adapterError);
}

#pragma mark - Phase 1: only GLM's discovery and polls

// What info, discover, and poll may send: the probe, the lease, and polls
// and identity queries, to a monitor or to the adapter at 01. Every one is
// a frame GLM sends in captures/startup-idle.
static BOOL QLMIsDiscoveryOrPoll(NSData *record) {
    const uint8_t *bytes = record.bytes;
    if (record.length == 2 && bytes[0] == QLMAddressBroadcast && bytes[1] == 0xFE) {
        return YES;
    }
    if (record.length == 6 && bytes[0] == QLMAddressMulticast && bytes[1] == 0x02) {
        return YES;
    }
    if (bytes[0] == QLMAddressBroadcast || bytes[0] == QLMAddressMulticast) {
        return NO;
    }
    return (record.length == 2 && (bytes[1] == 0x08 || bytes[1] == 0x39)) ||
           (record.length == 3 && bytes[1] == 0x19 && bytes[2] == 0x01);
}

- (void)testSendsOnlyDiscoveryAndPolls {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForDiscovery];
    [NSThread sleepForTimeInterval:0.3];
    NSArray<NSData *> *sent = _bus.sentMessages;
    XCTAssertGreaterThan(sent.count, 40u);
    for (NSData *record in sent) {
        XCTAssertTrue(QLMIsDiscoveryOrPoll(record), @"%@", record);
    }
    XCTAssertGreaterThan([self countSentTo:QLMAddressAdapter opcode:0x08 from:0], 10u);
}

// qlmctl info: with discovery off, System talks to the adapter alone.
- (void)testTalksToTheAdapterAloneWithoutDiscovery {
    _settings.discoversMonitors = NO;
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.adapter.identified;
    }];
    [NSThread sleepForTimeInterval:0.1];
    XCTAssertEqual(snapshot.monitors.count, 0u);
    for (NSData *record in _bus.sentMessages) {
        XCTAssertEqual(((const uint8_t *)record.bytes)[0], QLMAddressAdapter, @"%@", record);
        XCTAssertTrue(QLMIsDiscoveryOrPoll(record), @"%@", record);
    }
    XCTAssertEqual(_left.session, 0);
}

// docs/adapter-status.md: GLM polls the adapter in pairs about every 107 ms.
- (void)testPollsTheAdapterInPairs {
    _settings.cycleInterval = 10;
    _settings.adapterPollInterval = 0.04;
    [self startSystem];
    [self waitForDiscovery];
    const uint8_t pollBytes[] = {QLMAddressAdapter, 0x08};
    NSData *poll = QLMBytes(pollBytes, 2);
    // TRAP: a fixed sleep, read while System ran, failed under load.
    [self waitUntil:^BOOL {
        return [self countSent:poll from:0] >= 10;
    }];
    [_system stop];
    NSArray<NSData *> *sent = _bus.sentMessages;
    NSUInteger polls = 0;
    for (NSUInteger i = 0; i < sent.count; i++) {
        if ([sent[i] isEqualToData:poll]) {
            polls += 1;
            // The stop may cut the last pair in half.
            if (polls % 2 == 1 && i + 1 < sent.count) {
                XCTAssertEqualObjects(sent[i + 1], poll, @"a poll at %lu with no pair", (unsigned long)i);
            }
        }
    }
    XCTAssertGreaterThanOrEqual(polls, 10u);
}

// The knob's position rides the adapter's status, and a change publishes.
- (void)testTheKnobShowsInTheSnapshot {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.adapter.knobTenths isEqual:@(-1004)];
    }];
    [_bus perform:^{
        self->_bus.knobTenths = @(-123);
    }];
    QLMSnapshot *turned = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.adapter.knobTenths isEqual:@(-123)];
    }];
    XCTAssertTrue(turned.adapter.knobPresent);
    [_bus perform:^{
        self->_bus.knobTenths = nil;
    }];
    QLMSnapshot *unplugged = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.hasStatus && !snapshot.adapter.knobPresent;
    }];
    XCTAssertNil(unplugged.adapter.knobTenths);
    XCTAssertFalse(unplugged.adapter.micPresent);
}

#pragma mark - The knob

// The plan's "Behavior System must copy from GLM": at connect, keep qlm's own
// level. docs/adapter-status.md: GLM opens at its own level, and the knob's
// position moves nothing until the knob turns.
- (void)testTheKnobLeavesTheVolumeAtStart {
    _settings.cycleInterval = 10;
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [self waitForAdapterPolls:10];
    XCTAssertEqualObjects(_system.snapshot.volumeDecibels, @(-30));
    XCTAssertEqual([self countSentTo:QLMAddressAdapter opcode:0x2B from:0], 0u);
}

// A turn sets the volume to the knob's nearest step. The ceiling still caps
// it. Jitter after the turn sends nothing. QLMSystemGoldenTests checks the
// frames a turn sends against GLM's.
- (void)testATurnOfTheKnobSetsTheVolume {
    _settings.cycleInterval = 10;
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-30)];
    }];

    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_bus.knobTenths = @(-503);
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-50.5)];
    }];
    QLMMessage levelMessage = QLMCommandVolume(-50.5, _settings.ceilingDecibels);
    NSArray<NSData *> *levels = [self sentWithOpcode:0x1F from:before];
    XCTAssertGreaterThan(levels.count, 0u);
    for (NSData *level in levels) {
        XCTAssertEqualObjects(level, QLMAdapterRecord(&levelMessage));
    }

    before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_bus.knobTenths = @(-505);
    }];
    [self waitForAdapterPolls:10];
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 0u);

    // The top stop: 0 dB, capped at the -20 dB ceiling.
    [_bus perform:^{
        self->_bus.knobTenths = @(0);
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(0)];
    }];
    const uint8_t ceiling[] = {QLMAddressBroadcast, 0x1F, 0x0C, 0xCC, 0xCC};
    levels = [self sentWithOpcode:0x1F from:before];
    XCTAssertGreaterThan(levels.count, 0u);
    for (NSData *level in levels) {
        XCTAssertEqualObjects(level, QLMBytes(ceiling, sizeof ceiling));
    }
}

// qlmctl info, discover, and poll set no volume, and send only discovery and
// polls. A turn of the knob changes that for none of them.
- (void)testTheKnobSetsNoVolumeWhenNoneIsSet {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForDiscovery];
    [_bus perform:^{
        self->_bus.knobTenths = @(-300);
    }];
    [self waitForAdapterPolls:10];
    XCTAssertNil(_system.snapshot.volumeDecibels);
    XCTAssertEqualObjects(_system.snapshot.adapter.knobTenths, @(-300));
    for (NSData *record in _bus.sentMessages) {
        XCTAssertTrue(QLMIsDiscoveryOrPoll(record), @"%@", record);
    }
}

// Never drive the bus while GLM runs: while the adapter is busy, the
// snapshot says why and nothing goes out. Once it frees up, discovery runs.
- (void)testABusyAdapterShowsAndNothingGoesOut {
    _bus.busyReason = @"GLM is running (pid 1). Quit GLM first.";
    [self startSystem];
    QLMSnapshot *busy = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil;
    }];
    XCTAssertEqualObjects(busy.adapterError.domain, QLMAdapterErrorDomain);
    XCTAssertEqual(busy.adapterError.code, QLMAdapterErrorBusy);
    XCTAssertEqualObjects(busy.adapterError.localizedDescription, @"GLM is running (pid 1). Quit GLM first.");
    [NSThread sleepForTimeInterval:0.1];
    XCTAssertEqual(_bus.sentMessages.count, 0u);
    XCTAssertEqual(_system.snapshot.monitors.count, 0u);

    _bus.busyReason = nil;
    QLMSnapshot *freed = [self waitForDiscovery];
    XCTAssertNil(freed.adapterError);
}

// A lost connection takes the adapter's identity with it, since another
// adapter may answer the reconnect. The new one's identity is read afresh.
- (void)testAReconnectReadsTheNewAdaptersIdentity {
    _settings.discoversMonitors = NO;
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    QLMSnapshot *first = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.identified;
    }];
    XCTAssertEqualObjects(first.adapter.serialNumber, @"H00000F001");

    [_bus perform:^{
        self->_bus.disconnected = YES;
    }];
    QLMSnapshot *lost = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil;
    }];
    XCTAssertEqual(lost.adapterError.code, QLMAdapterErrorDisconnected);
    XCTAssertFalse(lost.adapter.identified);
    XCTAssertNil(lost.adapter.serialNumber);
    XCTAssertNil(lost.adapter.model);
    XCTAssertNil(lost.adapter.firmwareVersion);

    [_bus perform:^{
        self->_bus.adapterSystemInfo = @"c-0;model-GLM Adapter B;ver-1.5.2.7001;hw-0.0.203;build-2026.01.10.s  ";
        self->_bus.adapterSerialNumber = @"H00000F002";
        self->_bus.disconnected = NO;
    }];
    QLMSnapshot *second = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.identified;
    }];
    XCTAssertNil(second.adapterError);
    XCTAssertEqualObjects(second.adapter.serialNumber, @"H00000F002");
    XCTAssertEqualObjects(second.adapter.model, @"GLM Adapter B");
    XCTAssertEqualObjects(second.adapter.firmwareVersion, @"1.5.2.7001");
}

#pragma mark - Phase 1: lost replies

// A lost lease ack: the monitor holds the lease but never said so, so it
// would never answer a probe again. It is tracked anyway, and its polls and
// identity queries answer under the lease it took.
- (void)testALostLeaseAckIsRecovered {
    _left.dropReplies = 1;
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForDiscovery];
    XCTAssertEqual(QLMFindMonitor(snapshot, _left.hardwareID).session, 0x02);
    XCTAssertEqual(QLMFindMonitor(snapshot, _right.hardwareID).session, 0x03);
    NSUInteger leasesToLeft = [self sentFrom:0 matching:^BOOL(NSData *message) {
        const uint8_t *bytes = message.bytes;
        return bytes[0] == QLMAddressMulticast && memcmp(bytes + 2, self->_left.hardwareID.bytes, 3) == 0;
    }].count;
    XCTAssertEqual(leasesToLeft, 1u);
}

// A lost reply to an identity query is asked again on the next cycle.
- (void)testALostIdentityReplyIsAskedAgain {
    _left.dropReplies = 2;  // the lease ack, then the system info
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForDiscovery];
    QLMMonitorState *left = QLMFindMonitor(snapshot, _left.hardwareID);
    XCTAssertEqualObjects(left.model, @"8320A");
    XCTAssertEqual([self countSentTo:left.session opcode:0x39 from:0], 2u);
    XCTAssertEqual([self countSentTo:left.session opcode:0x19 from:0], 1u);
}

// Lost replies to the adapter's status polls are missed polls, then clear.
// A snapshot waits for the pair, so both polls of one are lost here.
- (void)testALostAdapterReplyIsAMissedPoll {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.identified;
    }];
    [_bus perform:^{
        self->_bus.adapterDropReplies = 2;
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.missedPolls == 2;
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.missedPolls == 0;
    }];
}

#pragma mark - Phase 1: GLM's own traffic

// captures/startup-idle, replayed while System polls the adapter as GLM
// does: every message System sends is one GLM sent, byte for byte.
- (void)testSendsNothingGLMDidNotInStartupIdle {
    _settings.cycleInterval = 0.05;
    _settings.adapterPollInterval = 0.02;
    QLMReplayAdapter *replay = [[QLMReplayAdapter alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)];
    [self startSystemWithAdapter:replay];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.adapter.identified;
    }];
    [NSThread sleepForTimeInterval:0.5];
    [_system stop];
    XCTAssertEqualObjects(replay.unmatchedMessages, @[]);
    XCTAssertGreaterThan(replay.playedCount, 100u);
}

// The same capture, report by report, through the report link the HID
// adapter uses: every reply is assembled from input reports, the adapter's
// system info from two.
- (void)testDiscoversEveryMonitorThroughTheReportLink {
    _settings.cycleInterval = 0.05;
    _settings.adapterPollInterval = 0.02;
    QLMCaptureDevice *device = [[QLMCaptureDevice alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)];
    [self startSystemWithAdapter:device];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        BOOL known = received.monitors.count == 6 && received.allIdentified && received.adapter.identified;
        for (QLMMonitorState *monitor in received.monitors) {
            known = known && monitor.deviceClass != QLMMonitorClassUnknown;
        }
        return known;
    }];
    XCTAssertEqualObjects(snapshot.adapter.model, @"GLM Adapter");
    XCTAssertEqualObjects(snapshot.adapter.serialNumber, @"H99999F000");
    XCTAssertEqualObjects(snapshot.adapter.knobTenths, @(-1004));
    [_system stop];
    XCTAssertEqual(device.unmatchedReports, 0u);
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

// The plan: after any gap in polling, lease again. captures/qlm-first-discover:
// the monitors drop their leases within 23 to 42 s of the host going quiet,
// then answer the probe. Here System's queue stalls, as in a sleep, and both
// monitors drop their leases meanwhile. The next cycle's probe finds them,
// and each gets the next session.
- (void)testAGapInPollingLeasesAgain {
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger before = _bus.sentMessages.count;
    // perform: runs on System's queue, so nothing goes out while it sleeps.
    [_bus perform:^{
        [NSThread sleepForTimeInterval:0.05];
        self->_left.session = 0;
        self->_right.session = 0;
    }];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *left = QLMFindMonitor(snapshot, self->_left.hardwareID);
        QLMMonitorState *right = QLMFindMonitor(snapshot, self->_right.hardwareID);
        return snapshot.monitors.count == 2 && left.session > 0x03 && right.session > 0x03 && snapshot.allIdentified;
    }];
    NSMutableIndexSet *sessions = [NSMutableIndexSet indexSet];
    for (QLMMonitorState *monitor in again.monitors) {
        [sessions addIndex:monitor.session];
        XCTAssertEqual(monitor.status, QLMMonitorStatusOn);
    }
    XCTAssertEqualObjects(sessions, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0x04, 2)]);

    NSArray<NSData *> *probes = [self sentFrom:before matching:^BOOL(NSData *message) {
        const uint8_t *bytes = message.bytes;
        return bytes[0] == QLMAddressBroadcast && bytes[1] == 0xFE;
    }];
    XCTAssertGreaterThanOrEqual(probes.count, 2u);
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:before], 2u);
}

// Every 2B sent from `start` on to any of `sessions`.
- (NSArray<NSData *> *)mutesFrom:(NSUInteger)start to:(NSIndexSet *)sessions {
    return [self sentFrom:start matching:^BOOL(NSData *message) {
        const uint8_t *bytes = message.bytes;
        return message.length == 3 && bytes[1] == 0x2B && [sessions containsIndex:bytes[0]];
    }];
}

// Sends rounds of 2B from every action that sends them: a mute of the other
// monitor and its lift, dim on and off, and a turn of the knob.
- (void)sendEveryMuteRound {
    [_system setMuted:YES forMonitorWithHardwareID:_right.hardwareID];
    [_system setMuted:NO forMonitorWithHardwareID:_right.hardwareID];
    [_system setDimmed:YES];
    [_system setDimmed:NO];
    [_bus perform:^{
        self->_bus.knobTenths = @(-500);
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-50)] && !snapshot.dimmed && snapshot.idle;
    }];
}

// The user's mute outlives a lapsed lease. When the monitor answers the
// probe again, it hears its mute right after its first poll, under its new
// session, as GLM sends a new monitor its state (captures/startup-idle,
// 9.861 s). After that, every 2B it gets says muted.
- (void)testAMuteOutlivesALapsedLease {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    QLMSystem *system = _system;
    NSData *leftID = _left.hardwareID;
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, leftID).muted;
    } after:^{
        [system setMuted:YES forMonitorWithHardwareID:leftID];
    }];

    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_left.session = 0;
    }];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *left = QLMFindMonitor(snapshot, leftID);
        return left.session > 0x03 && left.identified;
    }];
    uint8_t session = QLMFindMonitor(again, leftID).session;
    XCTAssertTrue(QLMFindMonitor(again, leftID).muted);
    NSArray<NSData *> *toLeft = [self sentFrom:before matching:^BOOL(NSData *message) {
        return ((const uint8_t *)message.bytes)[0] == session;
    }];
    const uint8_t mutedBytes[] = {session, 0x2B, QLMMuteValueMuted};
    NSData *muted = QLMBytes(mutedBytes, sizeof mutedBytes);
    const uint8_t pollBytes[] = {session, 0x08};
    NSUInteger poll = [toLeft indexOfObject:QLMBytes(pollBytes, sizeof pollBytes)];
    XCTAssertNotEqual(poll, NSNotFound);
    XCTAssertEqual([toLeft indexOfObject:muted], poll + 1);

    [self sendEveryMuteRound];
    NSMutableIndexSet *sessions = [NSMutableIndexSet indexSetWithIndex:session];
    [sessions addIndex:0x02];
    NSArray<NSData *> *mutes = [self mutesFrom:before to:sessions];
    XCTAssertGreaterThan(mutes.count, 6u);
    for (NSData *mute in mutes) {
        XCTAssertEqual(((const uint8_t *)mute.bytes)[2], QLMMuteValueMuted, @"%@", mute);
    }
    [_bus perform:^{
        XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted);
    }];
}

// The same when the monitor drops off the bus: System drops it after the
// retry burst, and finds it again once it answers the probe.
- (void)testAMuteOutlivesAMonitorDroppedAndFoundAgain {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    NSData *leftID = _left.hardwareID;
    [_bus perform:^{
        self->_left.present = NO;
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 1;
    }];

    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_left.session = 0;
        self->_left.present = YES;
    }];
    QLMSnapshot *found = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, leftID).identified;
    }];
    XCTAssertTrue(QLMFindMonitor(found, leftID).muted);

    [self sendEveryMuteRound];
    NSArray<NSData *> *mutes = [self mutesFrom:before to:[NSIndexSet indexSetWithIndex:QLMFindMonitor(found, leftID).session]];
    XCTAssertGreaterThan(mutes.count, 6u);
    for (NSData *mute in mutes) {
        XCTAssertEqual(((const uint8_t *)mute.bytes)[2], QLMMuteValueMuted, @"%@", mute);
    }
}

// A gap the monitors ride out keeps every lease.
- (void)testAShortGapKeepsTheLeases {
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        [NSThread sleepForTimeInterval:0.05];
    }];
    [self waitUntil:^BOOL {
        return [self countSentTo:0x02 opcode:0x08 from:before] >= 3;
    }];
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:before], 0u);
    QLMSnapshot *snapshot = _system.snapshot;
    XCTAssertEqual(QLMFindMonitor(snapshot, _left.hardwareID).session, 0x02);
    XCTAssertEqual(QLMFindMonitor(snapshot, _right.hardwareID).session, 0x03);
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
// QLMSystemGoldenTests checks the whole sequence against GLM's.
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
}

#pragma mark - Dim

// Section 7, 1F, and section 9, "Mute, Solo & Dim": no dim command, a plain
// volume frame 20 dB down. Dim off restores with an ordinary volume frame.
// captures/mute-dim, 51.24 s: GLM sends each twice.
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
        return [self countSent:minus30 from:before] == 2;
    }];

    before = _bus.sentMessages.count;
    [_system setDimmed:NO];
    [self waitUntil:^BOOL {
        return [self countSent:minus10 from:before] == 2 && !self->_system.snapshot.dimmed;
    }];

    // A volume change while dimmed stores the volume and sends it dimmed.
    [_system setDimmed:YES];
    [_system setVolumeDecibels:-20];
    [self waitUntil:^BOOL {
        QLMSnapshot *snapshot = self->_system.snapshot;
        return [self countSent:minus40 from:before] == 1 && [snapshot.volumeDecibels isEqual:@(-20)] && snapshot.dimmed;
    }];
}

// With no volume set, as in qlmctl dim over a replay, dim sends nothing.
- (void)testDimWithNoVolumeSendsNothing {
    _settings.cycleInterval = 10;
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger before = _bus.sentMessages.count;
    QLMSystem *system = _system;
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.dimmed && snapshot.idle;
    } after:^{
        [system setDimmed:YES];
    }];
    [NSThread sleepForTimeInterval:0.05];
    XCTAssertEqual(_bus.sentMessages.count, before);
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

// Two 8330A, with these hardware IDs and 19 01 serials.
- (void)useMainsMonitorsWithLeftID:(NSData *)leftID
                        leftSerial:(NSString *)leftSerial
                           rightID:(NSData *)rightID
                       rightSerial:(NSString *)rightSerial {
    _left = [[QLMFakeMonitor alloc] initWithHardwareID:leftID serialNumber:leftSerial systemInfo:@"c-1;model-8330A"
                                           deviceClass:QLMTelemetryClassTwoWay];
    _right = [[QLMFakeMonitor alloc] initWithHardwareID:rightID serialNumber:rightSerial systemInfo:@"c-1;model-8330A"
                                            deviceClass:QLMTelemetryClassTwoWay];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _right]];
}

// Two 8330A whose hardware IDs are the fixture's 1000005 and 1000004.
- (void)useMainsMonitors {
    const uint8_t leftID[3] = {0x0F, 0x42, 0x45};
    const uint8_t rightID[3] = {0x0F, 0x42, 0x44};
    [self useMainsMonitorsWithLeftID:QLMBytes(leftID, 3) leftSerial:@"8330AP21001234"
                             rightID:QLMBytes(rightID, 3) rightSerial:@"8330AP21005678"];
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

// A node matches the monitor whose hardware ID is the node's Serial. These
// monitors' 19 01 serials end in the nodes' Serials, but their IDs match
// neither node.
- (void)testApplyRefusesANodeWithNoMonitor {
    _settings.cycleInterval = 10;
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    [self useMainsMonitorsWithLeftID:QLMBytes(leftID, 3) leftSerial:@"8330AP21000005"
                             rightID:QLMBytes(rightID, 3) rightSerial:@"8330AP21000004"];
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

// Two 8330A and a 7370A whose hardware IDs are the fixture's 1000005,
// 1000004, and 1000006: nodes 0, 2, and 3 of each group, all verified.
- (QLMFakeMonitor *)useMainsAndSub {
    [self useMainsMonitors];
    const uint8_t subID[3] = {0x0F, 0x42, 0x46};
    QLMFakeMonitor *sub = [[QLMFakeMonitor alloc] initWithHardwareID:QLMBytes(subID, 3) serialNumber:@"7370AP21009012"
                                                         systemInfo:@"c-1;model-7370A" deviceClass:QLMTelemetryClassSubwoofer];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _right, sub]];
    return sub;
}

// Group `index` of the fixture with only nodes 0, 2, and 3.
- (QLMSetupGroup *)mainsAndSubOf:(NSUInteger)index named:(NSString *)name {
    QLMSetupGroup *source = QLMReadFixtureSetup().groups[index];
    return [self groupNamed:name from:source nodes:@[source.nodes[0], source.nodes[2], source.nodes[3]]];
}

// What System sent from `start` on, less its cycle.
- (NSArray<NSData *> *)applyFramesFrom:(NSUInteger)start {
    NSArray<NSData *> *sent = _bus.sentMessages;
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    QLMApplyFilter *filter = [[QLMApplyFilter alloc] init];
    for (NSUInteger i = start; i < sent.count; i++) {
        if ([filter keeps:sent[i]]) {
            [frames addObject:sent[i]];
        }
    }
    return frames;
}

- (QLMApplySequence *)sequenceFor:(QLMSetupGroup *)group snapshot:(QLMSnapshot *)snapshot {
    NSMutableArray<QLMApplyMonitor *> *monitors = [NSMutableArray array];
    for (QLMMonitorState *state in snapshot.monitors) {
        QLMApplyMonitor *monitor = [[QLMApplyMonitor alloc] initWithHardwareID:state.hardwareID session:state.session];
        monitor.on = state.status == QLMMonitorStatusOn;
        monitor.muted = state.muted;
        [monitors addObject:monitor];
    }
    return [[QLMApplySequence alloc] initWithGroup:group monitors:monitors adapterMuted:NO];
}

- (NSDictionary<NSData *, QLMDSPBlock *> *)blocksOf:(QLMSetupGroup *)group {
    return [QLMDSPBlock blocksByHardwareIDForGroup:group error:NULL];
}

// Waits until the frames System sent from `start` on, less its cycle, are
// at least `count`, then a little longer for one too many to show.
- (NSArray<NSData *> *)waitForApplyFrames:(NSUInteger)count from:(NSUInteger)start {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while ([self applyFramesFrom:start].count < count && [deadline timeIntervalSinceNow] > 0) {
        [NSThread sleepForTimeInterval:0.01];
    }
    [NSThread sleepForTimeInterval:0.1];
    return [self applyFramesFrom:start];
}

// The first apply is GLM's at launch (captures/startup-idle, 8.534 s): each
// monitor's block in turn, then the pair, then each one's state right after
// its next poll. The next is GLM's group switch
// (captures/group-switch-main-4x2-main-2x1, 12.359 s). System sends exactly
// what QLMApplySequence builds, which QLMApplyGoldenTests checks against
// every captured apply. The muted monitor gets 2B 03, so no apply unmutes
// it. Neither apply sends 05 04, which is never-send.
- (void)testTheFirstApplyIsGLMsLaunchAndTheNextIsItsSwitch {
    _settings.cycleInterval = 0.3;
    _settings.ceilingDecibels = 0;
    [self useMainsAndSub];
    [self startSystem];
    QLMSnapshot *discovered = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 3 && snapshot.allIdentified && snapshot.idle;
    }];
    [_system setMuted:YES forMonitorWithHardwareID:_right.hardwareID];
    [_system setVolumeDecibels:-10];
    discovered = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_right.hardwareID).muted && snapshot.volumeDecibels != nil && snapshot.idle;
    }];

    QLMSetupGroup *mains = [self mainsAndSubOf:0 named:@"Mains"];
    QLMApplySequence *launch = [self sequenceFor:mains snapshot:discovered];
    NSMutableArray<NSData *> *expected = [[launch enumerationOf:launch.monitors blocks:[self blocksOf:mains]] mutableCopy];
    for (QLMApplyMonitor *monitor in launch.monitors) {
        [expected addObjectsFromArray:[launch stateOf:monitor firstOfTwo:NO]];
    }
    NSUInteger before = _bus.sentMessages.count;
    XCTAssertNil([self applyGroup:mains]);
    XCTAssertEqualObjects([self waitForApplyFrames:expected.count from:before], expected);
    XCTAssertEqualObjects(_system.snapshot.activeGroupName, @"Mains");

    // The switch to the sub alone: both 8330A leave the group.
    QLMSetupGroup *sub = [self mainsAndSubOf:1 named:@"Sub"];
    QLMSnapshot *applied = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    }];
    QLMApplySequence *switching = [self sequenceFor:sub snapshot:applied];
    expected = [[switching switchWithBlocks:[self blocksOf:sub] volume:QLMCommandVolume(-10, 0)] mutableCopy];
    before = _bus.sentMessages.count;
    XCTAssertNil([self applyGroup:sub]);
    NSArray<NSData *> *sent = [self waitForApplyFrames:expected.count from:before];
    XCTAssertEqualObjects(sent, expected);
    XCTAssertEqual([self sentWithOpcode:0x05 from:0].count, 0u);
    [_bus perform:^{
        XCTAssertEqual(self->_right.muteValue, QLMMuteValueOutside);
    }];

    // Outside the group, a monitor gets 07 in the first round of two, and
    // 05 then 07 in the second (captures/knob-sweep, 19.135 s).
    uint8_t left = QLMFindMonitor(applied, _left.hardwareID).session;
    uint8_t right = QLMFindMonitor(applied, _right.hardwareID).session;
    NSData *subID = _bus.monitors[2].hardwareID;
    uint8_t subwoofer = QLMFindMonitor(applied, subID).session;
    before = _bus.sentMessages.count;
    [_system setMuted:YES forMonitorWithHardwareID:subID];
    const uint8_t rounds[][3] = {
        {left, 0x2B, 0x07}, {right, 0x2B, 0x07}, {subwoofer, 0x2B, 0x03},
        {left, 0x2B, 0x05}, {left, 0x2B, 0x07}, {right, 0x2B, 0x05}, {right, 0x2B, 0x07}, {subwoofer, 0x2B, 0x03},
    };
    NSMutableArray<NSData *> *roundFrames = [NSMutableArray array];
    for (size_t i = 0; i < sizeof rounds / sizeof rounds[0]; i++) {
        [roundFrames addObject:QLMBytes(rounds[i], 3)];
    }
    XCTAssertEqualObjects([self waitForApplyFrames:roundFrames.count from:before], roundFrames);
}

// A monitor leased while a group is active gets its block once the probe
// finds no more, then a round to the others and the pair, then its state
// after its next poll, as GLM's do after a wake
// (captures/group-switch-main-2x2-main-4x2, 11.996 to 12.808 s).
- (void)testAMonitorLeasedLaterGetsTheActiveGroupsBlock {
    _settings.cycleInterval = 0.3;
    _settings.ceilingDecibels = 0;
    [self useMainsAndSub];
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 3 && snapshot.allIdentified && snapshot.idle;
    }];
    [_system setVolumeDecibels:-10];
    QLMSetupGroup *mains = [self mainsAndSubOf:0 named:@"Mains"];
    XCTAssertNil([self applyGroup:mains]);
    // Each monitor's state goes out after its next poll.
    [self waitUntil:^BOOL{
        __block BOOL stated = YES;
        [self->_bus perform:^{
            for (QLMFakeMonitor *monitor in self->_bus.monitors) {
                stated = stated && monitor.muteValue == QLMMuteValueUnmuted;
            }
        }];
        return stated;
    }];
    QLMSnapshot *applied = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    }];

    NSData *leftID = _left.hardwareID;
    uint8_t oldSession = QLMFindMonitor(applied, leftID).session;
    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_left.session = 0;
    }];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *left = QLMFindMonitor(snapshot, leftID);
        return left.session != oldSession && left.status == QLMMonitorStatusOn && snapshot.monitors.count == 3;
    }];
    QLMApplySequence *sequence = [self sequenceFor:mains snapshot:again];
    QLMApplyMonitor *fresh = nil;
    for (QLMApplyMonitor *monitor in sequence.monitors) {
        if ([monitor.hardwareID isEqualToData:leftID]) {
            fresh = monitor;
        }
    }
    fresh.on = NO;
    NSMutableArray<NSData *> *expected = [[sequence enumerationOf:@[fresh] blocks:[self blocksOf:mains]] mutableCopy];
    [expected addObjectsFromArray:[sequence stateOf:fresh firstOfTwo:NO]];
    NSArray<NSData *> *sent = [self waitForApplyFrames:expected.count from:before];
    XCTAssertEqualObjects(sent, expected);
}

// A monitor just switched on plays at its own stored level until a host
// sends one (captures/qlm-control-first/notes.md, after the capture). So
// once a volume is set, it goes out right after a lease, before anything
// reaches the new monitor. With none set, as in info, discover, and poll,
// no volume goes out at all.
- (void)testANewMonitorHearsTheVolumeFirst {
    [_bus perform:^{
        self->_right.present = NO;
    }];
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 1 && snapshot.allIdentified && snapshot.idle;
    }];
    XCTAssertEqual([self sentWithOpcode:0x1F from:0].count, 0u);

    [_system setVolumeDecibels:-30];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_right.present = YES;
    }];
    NSData *rightID = _right.hardwareID;
    QLMSnapshot *joined = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, rightID).identified;
    }];
    uint8_t session = QLMFindMonitor(joined, rightID).session;
    NSArray<NSData *> *all = _bus.sentMessages;
    NSArray<NSData *> *sent = [all subarrayWithRange:NSMakeRange(before, all.count - before)];
    QLMMessage lease = QLMCommandAssignSession(rightID.bytes, session);
    NSUInteger leased = [sent indexOfObject:QLMAdapterRecord(&lease)];
    XCTAssertNotEqual(leased, NSNotFound);
    if (leased == NSNotFound || leased + 1 >= sent.count) {
        return;
    }
    QLMMessage volume = QLMCommandVolume(-30, -20);
    XCTAssertEqualObjects(sent[leased + 1], QLMAdapterRecord(&volume));
}

// The broadcasts that end a wake from `start` on: the level, then 2D 00 and
// 3D 00 00.
- (NSArray<NSData *> *)wakeEndFrom:(NSUInteger)start {
    [self waitUntil:^BOOL {
        return [self sentWithOpcode:0x3D from:start].count > 0;
    }];
    XCTAssertEqual([self sentWithOpcode:0x3A from:start].count, 6u);
    return [self sentFrom:start matching:^BOOL(NSData *message) {
        const uint8_t *bytes = message.bytes;
        return bytes[0] == QLMAddressBroadcast && bytes[1] != 0x3A;
    }];
}

// A wake with no volume set ends with a level all the same, since a woken
// monitor keeps its own level until a host sends one: the knob's position
// under the ceiling, or with no knob the bottom level.
- (void)testAWakeWithNoVolumeSendsTheKnobsLevelOrTheBottom {
    _settings.cycleInterval = 10;
    NSArray<NSData *> *pair = @[QLMBytes((const uint8_t[]){QLMAddressBroadcast, 0x2D, 0x00}, 3),
                                QLMBytes((const uint8_t[]){QLMAddressBroadcast, 0x3D, 0x00, 0x00}, 4)];
    NSArray<NSNumber *> *knobs = @[@(-450), @(-150), @(1)];  // -45 dB, -15 dB above the -20 dB ceiling, and no knob
    NSArray<NSNumber *> *levels = @[@(-45), @(-20), @(QLMVolumeDecibelsMin)];
    for (NSUInteger i = 0; i < knobs.count; i++) {
        NSNumber *knob = knobs[i].integerValue > 0 ? nil : knobs[i];
        [_bus perform:^{
            self->_bus.knobTenths = knob;
            self->_left.session = 0;  // the last pass's leases lapse
            self->_right.session = 0;
        }];
        [self startSystem];
        [self waitForDiscovery];
        NSUInteger before = _bus.sentMessages.count;
        [_system wake];
        QLMMessage level = QLMCommandVolume(levels[i].doubleValue, _settings.ceilingDecibels);
        NSArray<NSData *> *expected = [@[QLMAdapterRecord(&level)] arrayByAddingObjectsFromArray:pair];
        XCTAssertEqualObjects([self wakeEndFrom:before], expected, @"knob %@", knob);
        XCTAssertNil(_system.snapshot.volumeDecibels);
        [_system stop];
    }
}

// The mute record outlives a stop. The next start knows every mute, and a
// monitor leased again hears its mute after its first poll.
- (void)testTheMuteRecordOutlivesAStop {
    [self startSystem];
    [self waitForDiscovery];
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.mutedHardwareIDs containsObject:self->_left.hardwareID] && snapshot.idle;
    }];
    [_system stop];
    // The leases lapse, and the monitor forgets its mute, as one switched
    // off and on would.
    [_bus perform:^{
        self->_left.muteValue = QLMMuteValueUnmuted;
        self->_left.session = 0;
        self->_right.session = 0;
    }];
    [_system start];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.idle;
    }];
    XCTAssertEqualObjects(again.mutedHardwareIDs, [NSSet setWithObject:_left.hardwareID]);
    XCTAssertTrue(QLMFindMonitor(again, _left.hardwareID).muted);
    [_bus perform:^{
        XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted);
    }];
}

// System starts from the record its settings give, and adds to it with
// recordMutedHardwareIDs:, which sends nothing. Every round after says
// muted for those monitors.
- (void)testSystemStartsFromTheMuteRecordItIsGiven {
    _settings.mutedHardwareIDs = [NSSet setWithObject:_left.hardwareID];
    [self startSystem];
    QLMSnapshot *found = [self waitForDiscovery];
    XCTAssertTrue(QLMFindMonitor(found, _left.hardwareID).muted);
    XCTAssertFalse(QLMFindMonitor(found, _right.hardwareID).muted);

    NSUInteger before = _bus.sentMessages.count;
    [_system recordMutedHardwareIDs:[NSSet setWithObject:_right.hardwareID]];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_right.hardwareID).muted && snapshot.idle;
    }];
    XCTAssertEqual([self sentWithOpcode:0x2B from:before].count, 0u);

    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.dimmed;
    } after:^{
        [self->_system setVolumeDecibels:-30];
        [self->_system setDimmed:YES];
    }];
    NSArray<NSData *> *mutes = [self sentWithOpcode:0x2B from:before];
    XCTAssertGreaterThan(mutes.count, 0u);
    for (NSData *mute in mutes) {
        XCTAssertEqual(((const uint8_t *)mute.bytes)[2], QLMMuteValueMuted, @"%@", mute);
    }
}

// Starts System with the knob at `tenths`, or none when nil, at `volume`,
// or none when nil, and returns the snapshot once all is settled.
- (QLMSnapshot *)startWithKnob:(nullable NSNumber *)tenths volume:(nullable NSNumber *)volume {
    _settings.cycleInterval = 10;
    [_bus perform:^{
        self->_bus.knobTenths = tenths;
    }];
    [self startSystem];
    [self waitForDiscovery];
    if (volume != nil) {
        [_system setVolumeDecibels:volume.doubleValue];
    }
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && (volume == nil || snapshot.volumeDecibels != nil);
    }];
}

// Stops System, waits until it has, and returns what it sent meanwhile.
- (NSArray<NSData *> *)stopAndCollect:(QLMSnapshot *_Nullable *_Nonnull)stopped {
    NSUInteger before = _bus.sentMessages.count;
    QLMSystem *system = _system;
    *stopped = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.running;
    } after:^{
        [system stop];
    }];
    return [self sentFrom:before matching:^BOOL(NSData *message) {
        return YES;
    }];
}

// The adapter takes over at the knob's position (captures/qlm-control-first,
// 289.7 and 393.7 s). With the knob at or below the level qlm sends, qlm
// sends the knob's level as it stops, so the take-over changes nothing.
- (void)testAStopSendsTheKnobsLevelWhenItIsNoLouder {
    QLMSnapshot *running = [self startWithKnob:@(-600) volume:@(-40)];
    XCTAssertEqual(running.handBack.kind, QLMHandBackKnobLevel);
    QLMSnapshot *stopped = nil;
    NSArray<NSData *> *sent = [self stopAndCollect:&stopped];
    QLMMessage knob = QLMCommandVolume(-60, _settings.ceilingDecibels);
    XCTAssertEqualObjects(sent, @[QLMAdapterRecord(&knob)]);
    XCTAssertEqual(stopped.handBack.kind, QLMHandBackKnobLevel);
    XCTAssertEqualObjects(stopped.handBack.knobDecibels, @(-60));
    XCTAssertEqualWithAccuracy(stopped.handBack.volumeDecibels.doubleValue, -40, 0.01);
}

// With the knob above the level qlm sends, the take-over makes it louder.
// qlm sends nothing extra, and its snapshot says so, with both levels.
- (void)testAStopSendsNothingWhenTheKnobIsLouder {
    [self startWithKnob:@(-300) volume:@(-40)];
    QLMSnapshot *stopped = nil;
    XCTAssertEqualObjects([self stopAndCollect:&stopped], @[]);
    XCTAssertEqual(stopped.handBack.kind, QLMHandBackLouder);
    XCTAssertEqualObjects(stopped.handBack.knobDecibels, @(-30));
    XCTAssertEqualWithAccuracy(stopped.handBack.volumeDecibels.doubleValue, -40, 0.01);
}

// With no knob, or no volume set, the level at the take-over is unknown.
- (void)testAStopWithNoKnobOrNoVolumeLeavesTheLevelUnknown {
    [self startWithKnob:nil volume:@(-40)];
    QLMSnapshot *stopped = nil;
    XCTAssertEqualObjects([self stopAndCollect:&stopped], @[]);
    XCTAssertEqual(stopped.handBack.kind, QLMHandBackUnknown);
    XCTAssertNil(stopped.handBack.knobDecibels);

    [_bus perform:^{
        self->_left.session = 0;
        self->_right.session = 0;
    }];
    [self startWithKnob:@(-600) volume:nil];
    XCTAssertEqualObjects([self stopAndCollect:&stopped], @[]);
    XCTAssertEqual(stopped.handBack.kind, QLMHandBackUnknown);
    XCTAssertNil(stopped.handBack.volumeDecibels);
}

// A start while the stop sends the knob's level runs once the stop is done.
- (void)testAStartDuringTheHandBackRunsAfterIt {
    [self startWithKnob:@(-600) volume:@(-40)];
    [_bus perform:^{
        self->_left.session = 0;
        self->_right.session = 0;
    }];
    QLMSystem *system = _system;
    __block BOOL stopped = NO;
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        stopped = stopped || !snapshot.running;
        return stopped && snapshot.running && snapshot.monitors.count == 2 && snapshot.allIdentified;
    } after:^{
        [system stop];
        [system start];
    }];
    XCTAssertTrue(again.running);
    QLMMessage knob = QLMCommandVolume(-60, _settings.ceilingDecibels);
    XCTAssertTrue([_bus.sentMessages containsObject:QLMAdapterRecord(&knob)]);
}

// A poll that never went out, while another host held the adapter, says
// nothing of a monitor. So a short outage drops no monitor, and none shows
// offline or a missed poll.
- (void)testPollsThatNeverWentOutDoNotCount {
    [self startSystem];
    [self waitForDiscovery];
    [_bus perform:^{
        self->_bus.busyReason = @"GLM is running.";
    }];
    __block NSUInteger fewest = 2;
    __block BOOL anyMissed = NO;
    QLMSystem *system = _system;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([until timeIntervalSinceNow] > 0) {
        QLMSnapshot *snapshot = system.snapshot;
        fewest = MIN(fewest, snapshot.monitors.count);
        for (QLMMonitorState *monitor in snapshot.monitors) {
            anyMissed = anyMissed || monitor.missedPolls > 0 || monitor.offline;
        }
        [NSThread sleepForTimeInterval:0.01];
    }
    XCTAssertNotNil(system.snapshot.adapterError);
    [_bus perform:^{
        self->_bus.busyReason = nil;
    }];
    QLMSnapshot *back = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError == nil && snapshot.monitors.count == 2;
    }];
    XCTAssertEqual(fewest, 2u);
    XCTAssertFalse(anyMissed);
    XCTAssertEqual(back.adapter.missedPolls, 0u);
}

// The ceiling changes while System runs. The volume goes out again at once
// under it, lower or higher.
- (void)testTheCeilingChangesWhileSystemRuns {
    _settings.cycleInterval = 10;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-10];  // above the -20 dB ceiling
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    for (NSNumber *ceiling in @[@(-40), @(-5)]) {
        NSUInteger before = _bus.sentMessages.count;
        [_system setCeilingDecibels:ceiling.doubleValue];
        QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
            return received.ceilingDecibels == ceiling.doubleValue && received.idle;
        }];
        XCTAssertEqual(snapshot.ceilingDecibels, ceiling.doubleValue);
        XCTAssertEqual(_system.settings.ceilingDecibels, ceiling.doubleValue);
        QLMMessage volume = QLMCommandVolume(-10, ceiling.doubleValue);
        XCTAssertEqualObjects([self sentWithOpcode:0x1F from:before], @[QLMAdapterRecord(&volume)]);
    }
}

// A stop's completion runs on the main queue once System has let go of the
// adapter: after the hand-back level, with the snapshot stopped. A stop
// while not running completes at once.
- (void)testAStopCompletesOnceTheAdapterIsClosed {
    [self startWithKnob:@(-600) volume:@(-40)];
    XCTestExpectation *stopped = [self expectationWithDescription:@"stopped"];
    QLMSystem *system = _system;
    QLMFakeBus *bus = _bus;
    QLMMessage knob = QLMCommandVolume(-60, _settings.ceilingDecibels);
    NSData *knobRecord = QLMAdapterRecord(&knob);
    [_system stopWithCompletion:^{
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertFalse(system.snapshot.running);
        XCTAssertEqualObjects(bus.sentMessages.lastObject, knobRecord);
        [stopped fulfill];
    }];
    [self waitForExpectations:@[stopped] timeout:5];

    XCTestExpectation *again = [self expectationWithDescription:@"again"];
    [_system stopWithCompletion:^{
        [again fulfill];
    }];
    [self waitForExpectations:@[again] timeout:5];
}

// Mute all holds for a monitor that first appears after it: it hears 2B 03
// after its first poll, and every 2B after says muted, while the other
// monitor's mute is lifted and set again.
- (void)testMuteAllHoldsForAMonitorThatAppearsLater {
    _settings.adapterPollInterval = 0.01;
    [_bus perform:^{
        self->_left.present = NO;
    }];
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 1 && snapshot.allIdentified;
    }];
    [_system setVolumeDecibels:-30];
    [_system setAllMuted:YES];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allMuted && snapshot.idle;
    }];

    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_left.present = YES;
    }];
    NSData *leftID = _left.hardwareID;
    QLMSnapshot *joined = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *left = QLMFindMonitor(snapshot, leftID);
        return left.identified && left.muted && snapshot.allMuted;
    }];
    uint8_t session = QLMFindMonitor(joined, leftID).session;
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    } after:^{
        [self sendEveryMuteRound];
    }];
    NSArray<NSData *> *mutes = [self mutesFrom:before to:[NSIndexSet indexSetWithIndex:session]];
    XCTAssertGreaterThan(mutes.count, 6u);
    for (NSData *mute in mutes) {
        XCTAssertEqual(((const uint8_t *)mute.bytes)[2], QLMMuteValueMuted, @"%@", mute);
    }
    [_bus perform:^{
        XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted);
    }];
}

// AGENTS.md's Safety rule refuses a group with an unverified model, the
// 8351B, but for qlmctl's supervised test, which sets allowsUnverifiedRates.
- (void)testOnlyTheSupervisedSettingAppliesAnUnverifiedRate {
    _settings.cycleInterval = 10;
    const uint8_t leftID[3] = {0x0F, 0x42, 0x42};  // the fixture's 1000002, the Left 8351B
    _left = [[QLMFakeMonitor alloc] initWithHardwareID:QLMBytes(leftID, 3) serialNumber:@"8351BP21001234"
                                            systemInfo:@"c-3;model-8351B" deviceClass:QLMTelemetryClassTwoWay];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left]];
    QLMSetupGroup *source = QLMReadFixtureSetup().groups[0];
    QLMSetupGroup *left = [self groupNamed:@"Left" from:source nodes:@[source.nodes[1]]];
    for (NSNumber *allowed in @[@NO, @YES]) {
        _settings.allowsUnverifiedRates = allowed.boolValue;
        [_bus perform:^{
            self->_left.session = 0;
        }];
        [self startSystem];
        [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return snapshot.monitors.count == 1 && snapshot.allIdentified;
        }];
        [_system setVolumeDecibels:-40];
        NSUInteger before = _bus.sentMessages.count;
        NSError *error = [self applyGroup:left];
        if (allowed.boolValue) {
            XCTAssertNil(error);
            XCTAssertEqual([self sentWithOpcode:0x17 from:before].count, 1u);
        } else {
            XCTAssertEqual(error.code, QLMSystemErrorUnverifiedRate);
            XCTAssertEqual([self sentWithOpcode:0x17 from:before].count, 0u);
        }
        [_system stop];
        [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return !snapshot.running;
        }];
    }
}

// switchToGroup: sends GLM's switch even as the first apply.
- (void)testSwitchToGroupSendsTheSwitchFirstTime {
    _settings.cycleInterval = 10;
    _settings.ceilingDecibels = 0;
    [self useMainsMonitors];
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-10];
    QLMSnapshot *ready = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    QLMSetupGroup *group = [self mainsGroup];
    NSArray<NSData *> *expected = [[self sequenceFor:group snapshot:ready] switchWithBlocks:[self blocksOf:group]
                                                                                    volume:QLMCommandVolume(-10, 0)];
    NSUInteger before = _bus.sentMessages.count;
    XCTestExpectation *done = [self expectationWithDescription:@"switch"];
    [_system switchToGroup:group completion:^(NSError *error) {
        XCTAssertNil(error);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5];
    XCTAssertEqualObjects([self waitForApplyFrames:expected.count from:before], expected);
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

// A group whose nodes are all off. The first apply, as GLM's at launch,
// still sends each node its block (captures/startup-idle: Main 2x1's off
// nodes, 8.534 s). The switch after it ducks, wakes, tells each monitor to
// prepare for standby, routes it, and sends no block.
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
    for (QLMSetupNode *node in group.nodes) {
        XCTAssertFalse(node.on);
    }

    NSUInteger before = _bus.sentMessages.count;
    XCTAssertNil([self applyGroup:group]);
    XCTAssertEqual([self sentWithOpcode:0x17 from:before].count, 2u);
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 0u);

    before = _bus.sentMessages.count;
    XCTAssertNil([self applyGroup:group]);
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 5u);  // two duck frames, three restores
    XCTAssertEqual([self sentWithOpcode:0x3A from:before].count, 4u);  // the wake twice, and 03 02 to each
    XCTAssertEqual([self sentWithOpcode:0x10 from:before].count, 0u);
    XCTAssertEqual([self sentWithOpcode:0x04 from:before].count, 2u);
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return !received.applying && [received.activeGroupName isEqualToString:@"Off"];
    }];
    XCTAssertTrue(snapshot.idle);
}

@end
