#import <XCTest/XCTest.h>

#import "QLMApplySequence.h"
#import "QLMDSPBlock.h"
#import "QLMFakeBus.h"
#import "QLMHIDAdapterInternal.h"
#import "QLMHostCheck.h"
#import "QLMReplayAdapter.h"
#import "QLMReportLink.h"
#import "QLMSetupInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the hlm protocol spec, revision 13. Section 3 gives the session
// IDs, their start at 02, and re-discovery after four missed polls. Section 9
// gives discovery, enumeration, and the poll loop. The plan's Phase 1 asks
// for fake-bus tests of lease loss, re-discovery, and a lost reply. The
// Phase 2 tests name their sections one by one. System and the bus run on a
// virtual clock, so each test's timing is its own, whatever the host's load.
@interface QLMSystemTests : XCTestCase
@end

// Holds each reply until the test lets it through, so a test can fire a
// timer between any two.
@interface QLMHeldAdapter : NSObject <QLMAdapter>
- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter;
// Hands the oldest reply held over, on the adapter's queue. NO when none is.
- (BOOL)releaseReply;
// The most requests sent since the last start, at once, whose replies
// System had not been handed yet.
@property (atomic, readonly) NSUInteger mostInFlight;
@end

@implementation QLMHeldAdapter {
    id<QLMAdapter> _adapter;
    dispatch_queue_t _queue;
    id<QLMClock> _clock;
    NSMutableArray<dispatch_block_t> *_held;
    NSUInteger _starts;
    NSUInteger _inFlight;  // of this start's
}

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter {
    self = [super init];
    if (self) {
        _adapter = adapter;
        _held = [NSMutableArray array];
    }
    return self;
}

- (NSString *)deviceDescription {
    return _adapter.deviceDescription;
}

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    _queue = queue;
    _clock = clock;
    @synchronized(self) {
        _starts += 1;
        _inFlight = 0;
    }
    [_adapter startOnQueue:queue clock:clock];
}

- (void)stop {
    [_adapter stop];
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    NSUInteger start;
    @synchronized(self) {
        start = _starts;
        _inFlight += 1;
        _mostInFlight = MAX(_mostInFlight, _inFlight);
    }
    __weak QLMHeldAdapter *weakSelf = self;
    [_adapter sendMessage:message replyHandler:^(const QLMMessage *reply, NSError *error) {
        BOOL answered = reply != NULL;
        QLMMessage copy = answered ? *reply : QLMMessageMake(0, NULL, 0);
        @synchronized(self) {
            [self->_held addObject:^{
                [weakSelf replied:start];
                handler(answered ? &copy : NULL, error);
            }];
        }
    }];
}

- (void)replied:(NSUInteger)start {
    @synchronized(self) {
        if (_starts == start) {
            _inFlight -= 1;
        }
    }
}

- (BOOL)releaseReply {
    dispatch_block_t reply = nil;
    @synchronized(self) {
        reply = _held.firstObject;
        if (reply != nil) {
            [_held removeObjectAtIndex:0];
        }
    }
    if (reply == nil) {
        return NO;
    }
    [_clock async:_queue run:reply];
    return YES;
}

@end

// Passes each message on, but while `failure` is set, fails each one it
// matches with that error, and sends nothing. With no `matches`, it matches
// every message.
@interface QLMFailingAdapter : NSObject <QLMAdapter>
- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter;
@property (atomic, nullable) NSError *failure;
@property (atomic, copy, nullable) BOOL (^matches)(const QLMMessage *message);
@end

@implementation QLMFailingAdapter {
    id<QLMAdapter> _adapter;
    dispatch_queue_t _queue;
    id<QLMClock> _clock;
}

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter {
    self = [super init];
    if (self) {
        _adapter = adapter;
    }
    return self;
}

- (NSString *)deviceDescription {
    return _adapter.deviceDescription;
}

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    _queue = queue;
    _clock = clock;
    [_adapter startOnQueue:queue clock:clock];
}

- (void)stop {
    [_adapter stop];
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    NSError *failure = self.failure;
    BOOL (^matches)(const QLMMessage *) = self.matches;
    if (failure != nil && (matches == nil || matches(&message))) {
        [_clock async:_queue run:^{
            handler(NULL, failure);
        }];
        return;
    }
    [_adapter sendMessage:message replyHandler:handler];
}

@end

// Passes everything on to a capture device. While `holds` is set, it holds
// the first QLMAdapterErrorGaveUp System would get, until released, as a
// reply still on its hop when a reopen runs.
@interface QLMLateGaveUpAdapter : NSObject <QLMAdapter>
- (instancetype)initWithDevice:(QLMCaptureDevice *)device;
@property (atomic) BOOL holds;
// Hands the held reply over, on the queue. NO when none is held.
- (BOOL)releaseHeld;
@end

@implementation QLMLateGaveUpAdapter {
    QLMCaptureDevice *_device;
    dispatch_queue_t _queue;
    id<QLMClock> _clock;
    dispatch_block_t _held;
}

- (instancetype)initWithDevice:(QLMCaptureDevice *)device {
    self = [super init];
    if (self) {
        _device = device;
    }
    return self;
}

- (NSString *)deviceDescription {
    return _device.deviceDescription;
}

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    _queue = queue;
    _clock = clock;
    [_device startOnQueue:queue clock:clock];
}

- (void)stop {
    [_device stop];
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    [self sendMessage:message rewrite:nil replyHandler:handler];
}

- (void)sendMessage:(QLMMessage)message rewrite:(nullable QLMAdapterRewrite)rewrite replyHandler:(QLMAdapterReplyHandler)handler {
    [_device sendMessage:message rewrite:rewrite replyHandler:^(const QLMMessage *reply, NSError *error) {
        @synchronized(self) {
            if (self.holds && self->_held == nil && error.code == QLMAdapterErrorGaveUp) {
                self.holds = NO;
                self->_held = ^{
                    handler(NULL, error);
                };
                return;
            }
        }
        handler(reply, error);
    }];
}

- (QLMReconnectResult)reconnect {
    return [_device reconnect];
}

- (BOOL)releaseHeld {
    dispatch_block_t held = nil;
    @synchronized(self) {
        held = _held;
        _held = nil;
    }
    if (held == nil) {
        return NO;
    }
    [_clock async:_queue run:held];
    return YES;
}

@end

@implementation QLMSystemTests {
    QLMFakeMonitor *_left;
    QLMFakeMonitor *_right;
    QLMFakeBus *_bus;
    QLMSystemSettings *_settings;
    QLMSystem *_system;
    QLMVirtualClock *_time;
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
    _time = [[QLMVirtualClock alloc] init];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _right]];
    _settings = [[QLMSystemSettings alloc] init];
    _settings.clock = _time;
    _settings.cycleInterval = 0.02;
    _settings.ceilingDecibels = -20;
    // The adapter polls only at start, so the tests that count frames see
    // none but GLM's opening pair. The adapter's own tests turn them on.
    _settings.adapterPollInterval = 0;
    _snapshots = dispatch_queue_create("qlm.tests.snapshots", DISPATCH_QUEUE_SERIAL);
    _received = [NSMutableArray array];
}

- (void)tearDown {
    [self stopSystem];
    [super tearDown];
}

// Stops System and waits until the stop is done.
- (void)stopSystem {
    if (_system == nil) {
        return;
    }
    __block BOOL stopped = NO;
    [_system stopWithCompletion:^{
        stopped = YES;
    }];
    [self waitUntil:^BOOL {
        return stopped;
    }];
}

// Moves the clock one timer at a time until the condition holds. A minute
// on the clock is a hang.
- (void)waitUntil:(BOOL (^)(void))condition {
    XCTAssertTrue([_time runUntil:condition within:60], @"the condition never held");
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
    __block QLMSnapshot *match = nil;
    NSMutableArray<QLMSnapshot *> *received = _received;
    [_system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        [received addObject:snapshot];
        if (match == nil && predicate(snapshot)) {
            match = snapshot;
        }
    } queue:_snapshots];
    if (action != nil) {
        action();
    }
    [self waitUntil:^BOOL {
        return match != nil;
    }];
    return match;
}

// Waits until nothing is queued for the bus or in flight.
- (void)waitForIdle {
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    }];
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

// Every monitor's lease lapses, so the next probe finds it.
- (void)lapseLeases {
    [_bus perform:^{
        for (QLMFakeMonitor *monitor in self->_bus.monitors) {
            monitor.session = 0;
        }
    }];
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
    [_time advanceBy:0.3];
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
    [_time advanceBy:0.1];
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
    [self waitUntil:^BOOL {
        return [self countSent:poll from:0] >= 10;
    }];
    [self stopSystem];
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

    // The top stop, 0 dB, holds the volume at the -20 dB ceiling.
    XCTAssertEqualObjects([self turnKnobTo:0].volumeDecibels, @(-20));
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

// Waits until the snapshot shows the knob at `tenths`, with nothing queued.
- (QLMSnapshot *)turnKnobTo:(NSInteger)tenths {
    [_bus perform:^{
        self->_bus.knobTenths = @(tenths);
    }];
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.adapter.knobTenths isEqual:@(tenths)] && snapshot.idle;
    }];
}

// In qlm-app-first, System's volume followed the knob above the ceiling, and
// only the frame was capped. So each turn above it sent a burst, 75 in 13.7 s
// with the level held at -35 dB (captures/qlm-app-first/notes.md,
// Surprises). Now the volume stops at the ceiling, and a turn that leaves it
// there sends nothing. Below it, the knob moves the volume again.
- (void)testTheKnobAboveTheCeilingHoldsTheVolumeAtIt {
    _settings.adapterPollInterval = 0.01;
    [self startWithKnob:@(-300) volume:@(-30)];
    XCTAssertEqualObjects([self turnKnobTo:-100].volumeDecibels, @(-20));
    NSUInteger before = _bus.sentMessages.count;
    for (NSNumber *tenths in @[@(-50), @(0), @(-150)]) {
        XCTAssertEqualObjects([self turnKnobTo:tenths.integerValue].volumeDecibels, @(-20));
    }
    XCTAssertEqual([self sentWithOpcode:0x1F from:before].count, 0u);
    XCTAssertEqual([self sentWithOpcode:0x2B from:before].count, 0u);

    XCTAssertEqualObjects([self turnKnobTo:-253].volumeDecibels, @(-25.5));
    QLMMessage level = QLMCommandVolume(-25.5, _settings.ceilingDecibels);
    NSArray<NSData *> *levels = [self sentWithOpcode:0x1F from:before];
    XCTAssertEqual(levels.count, 4u);  // GLM's burst: three, the mute state, then one
    for (NSData *sent in levels) {
        XCTAssertEqualObjects(sent, QLMAdapterRecord(&level));
    }
}

// The reading jumps as the plug slides out, and GLM follows the jump
// (captures/volume-sweep, 25.11 to 25.56 s). Here the knob jumps up, then
// reads absent a poll later. System takes the raise back with one frame at
// the level before it, and stays there. A raise older than a second stands.
- (void)testAKnobPulledOutTakesBackTheRaiseItJustMade {
    _settings.adapterPollInterval = 0.107;
    [self startWithKnob:@(-400) volume:@(-40)];
    QLMMessage raised = QLMCommandVolume(-30, _settings.ceilingDecibels);
    QLMMessage back = QLMCommandVolume(-40, _settings.ceilingDecibels);
    NSData *raisedRecord = QLMAdapterRecord(&raised);
    NSData *backRecord = QLMAdapterRecord(&back);

    NSUInteger before = _bus.sentMessages.count;
    XCTAssertEqualObjects([self turnKnobTo:-300].volumeDecibels, @(-30));
    XCTAssertEqualObjects([self pullKnob].volumeDecibels, @(-40));
    [_time advanceBy:1];
    NSArray<NSData *> *expected = @[raisedRecord, raisedRecord, raisedRecord, raisedRecord, backRecord];
    XCTAssertEqualObjects([self sentWithOpcode:0x1F from:before], expected);

    [self turnKnobTo:-400];
    before = _bus.sentMessages.count;
    XCTAssertEqualObjects([self turnKnobTo:-300].volumeDecibels, @(-30));
    [_time advanceBy:1.1];
    XCTAssertEqualObjects([self pullKnob].volumeDecibels, @(-30));
    [_time advanceBy:1];
    expected = @[raisedRecord, raisedRecord, raisedRecord, raisedRecord];
    XCTAssertEqualObjects([self sentWithOpcode:0x1F from:before], expected);

    // A level the user sets after the raise stands.
    [self turnKnobTo:-400];
    XCTAssertEqualObjects([self turnKnobTo:-300].volumeDecibels, @(-30));
    [_system setVolumeDecibels:-35];
    XCTAssertEqualObjects([self pullKnob].volumeDecibels, @(-35));
}

// Pulls the knob out, and waits until the snapshot shows it, with nothing
// queued.
- (QLMSnapshot *)pullKnob {
    [_bus perform:^{
        self->_bus.knobTenths = nil;
    }];
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.hasStatus && !snapshot.adapter.knobPresent && snapshot.idle;
    }];
}

// The latest snapshot waits until nothing is queued for the bus or in
// flight. A snapshot of now does not, so a stop decided from it sees a level
// that has not gone out yet: here, one below the knob, which makes the
// take-over louder.
- (void)testASnapshotOfNowSeesALevelNotYetPublished {
    XCTAssertEqual([self startWithKnob:@(-500) volume:@(-30)].handBack.kind, QLMHandBackKnobLevel);
    [_system wake];  // its holds keep the bus busy
    [_system setVolumeDecibels:-60];
    [_time settle];
    XCTAssertEqual(_system.snapshot.handBack.kind, QLMHandBackKnobLevel);
    QLMSnapshot *now = [_system snapshotNowWithin:1];
    XCTAssertEqualObjects(now.volumeDecibels, @(-60));
    XCTAssertEqual(now.handBack.kind, QLMHandBackLouder);
}

// System's queue may wait on a report the adapter does not take. A snapshot
// of now then gives up, rather than hold its caller, the main queue.
- (void)testASnapshotOfNowGivesUpOnABusyQueue {
    [self startWithKnob:@(-500) volume:@(-30)];
    dispatch_semaphore_t holding = dispatch_semaphore_create(0);
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    QLMFakeBus *bus = _bus;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [bus perform:^{  // on System's queue
            dispatch_semaphore_signal(holding);
            dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
        }];
    });
    dispatch_semaphore_wait(holding, DISPATCH_TIME_FOREVER);
    XCTAssertNil([_system snapshotNowWithin:0.05]);
    dispatch_semaphore_signal(release);
    XCTAssertNotNil([_system snapshotNowWithin:1]);
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
    [_time advanceBy:0.1];
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
    [self waitUntil:^BOOL {
        return replay.playedCount > 100;
    }];
    [self stopSystem];
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
    [self stopSystem];
    XCTAssertEqual(device.unmatchedReports, 0u);
}

// captures/startup-idle-mic, 7.31 s: GLM's first 01 08 reads 32 34, DE
// 1B AB FB A0, and DD 00 22 4E 4F. The readings' meaning is unconfirmed
// (docs/adapter-status.md), so the snapshot carries them as raw counts.
- (void)testCarriesTheMicsReadingsAsRawCounts {
    _settings.discoversMonitors = NO;
    _settings.adapterPollsPerRound = 1;
    [self startSystemWithAdapter:[[QLMReplayAdapter alloc] initWithCapture:QLMReadCapture(@"startup-idle-mic", NULL)]];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.adapter.hasStatus;
    }];
    XCTAssertTrue(snapshot.adapter.micPresent);
    XCTAssertEqualObjects(snapshot.adapter.micDE, @(0x1BABFBA0));
    XCTAssertEqualObjects(snapshot.adapter.micDD, @(0x00224E4F));
}

// captures/startup-idle, 7.31 s: 33, no mic.
- (void)testCarriesNoReadingsWithoutTheMic {
    _settings.discoversMonitors = NO;
    [self startSystemWithAdapter:[[QLMReplayAdapter alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)]];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.adapter.hasStatus;
    }];
    XCTAssertFalse(snapshot.adapter.micPresent);
    XCTAssertNil(snapshot.adapter.micDE);
    XCTAssertNil(snapshot.adapter.micDD);
}

// The mic in with neither reading, 32 34 alone, then with DE alone: shapes no
// capture has. A missing reading is nil, not 0.
- (void)testCarriesNoReadingWhenTheReplyLacksIt {
    _settings.discoversMonitors = NO;
    _settings.adapterPollInterval = 0.02;
    [_bus perform:^{
        self->_bus.micIn = YES;
    }];
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.adapter.hasStatus;
    }];
    XCTAssertTrue(snapshot.adapter.micPresent);
    XCTAssertNil(snapshot.adapter.micDE);
    XCTAssertNil(snapshot.adapter.micDD);
    snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.adapter.micDE != nil;
    } after:^{
        [self->_bus perform:^{
            self->_bus.micDE = @5;
        }];
    }];
    XCTAssertEqualObjects(snapshot.adapter.micDE, @5);
    XCTAssertNil(snapshot.adapter.micDD);
}

// After lost replies, the snapshot keeps the last readings, as it keeps the
// knob, and missedPolls says they are stale.
- (void)testKeepsTheMicsLastReadingsThroughMissedPolls {
    _settings.discoversMonitors = NO;
    _settings.adapterPollInterval = 0.01;
    [_bus perform:^{
        self->_bus.micDE = @1;
        self->_bus.micDD = @2;
    }];
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.identified;
    }];
    QLMSnapshot *stale = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.missedPolls == 2;
    } after:^{
        [self->_bus perform:^{
            self->_bus.adapterDropReplies = 2;
        }];
    }];
    XCTAssertEqualObjects(stale.adapter.micDE, @1);
    XCTAssertEqualObjects(stale.adapter.micDD, @2);
    XCTAssertEqualObjects(stale.adapter.knobTenths, @(-1004));
}

// A change to the mic's readings alone publishes nothing. With no monitor to
// publish a cycle, the cycle itself brings the new readings.
- (void)testACyclePublishesTheMicsNewReadings {
    _settings.discoversMonitors = NO;
    _settings.adapterPollInterval = 0.02;
    _settings.cycleInterval = 0.5;
    [_bus perform:^{
        self->_bus.micDE = @1;
        self->_bus.micDD = @2;
    }];
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapter.identified && [snapshot.adapter.micDE isEqual:@1] && snapshot.idle;
    }];
    QLMSnapshot *next = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.adapter.micDE isEqual:@3];
    } after:^{
        [self->_bus perform:^{
            self->_bus.micDE = @3;
        }];
    }];
    XCTAssertEqualObjects(next.adapter.micDD, @2);
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
    [_bus perform:^{
        self->_left.session = 0;
        self->_right.session = 0;
    }];
    [_time stallFor:0.05];
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

// Lets the held replies through, one at a time, until the condition holds
// or none is left.
- (BOOL)releaseRepliesOf:(QLMHeldAdapter *)held until:(BOOL (^)(void))condition {
    [_time settle];
    while (!condition()) {
        if (![held releaseReply]) {
            return NO;
        }
        [_time settle];
    }
    return YES;
}

// The cycle fires at the worst moment: the lease chain's next probe is out,
// and the monitor that answers it holds no lease yet. The cycle must not
// probe too, or that monitor answers both probes and gets two leases.
- (void)testACycleInsideTheLeaseChainLeasesNoMonitorTwice {
    QLMHeldAdapter *held = [[QLMHeldAdapter alloc] initWithAdapter:_bus];
    [self startSystemWithAdapter:held];
    XCTAssertTrue([self releaseRepliesOf:held until:^BOOL {
        const uint8_t *last = self->_bus.sentMessages.lastObject.bytes;
        BOOL probeOut = last != NULL && last[0] == QLMAddressBroadcast && last[1] == 0xFE;
        return probeOut && [self countSentTo:QLMAddressMulticast opcode:0x02 from:0] == 1;
    }]);
    [_time advanceBy:_settings.cycleInterval];
    [self releaseRepliesOf:held until:^BOOL {
        return NO;
    }];

    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:0], 2u);
    QLMSnapshot *snapshot = _system.snapshot;
    XCTAssertEqual(snapshot.monitors.count, 2u);
    XCTAssertEqual(QLMFindMonitor(snapshot, _left.hardwareID).session, 0x02);
    XCTAssertEqual(QLMFindMonitor(snapshot, _right.hardwareID).session, 0x03);
}

// A stop with no hand-back lets go at once, with a request in flight, and
// a start right after it sends its own first request. The stopped run's
// reply must end nothing of the new run. If it did, System would send its
// next request while the first is still in flight.
- (void)testAReplyFromBeforeAStopEndsNothingAfterTheStart {
    QLMHeldAdapter *held = [[QLMHeldAdapter alloc] initWithAdapter:_bus];
    [self startSystemWithAdapter:held];
    [_time settle];
    [_system stop];
    [_system start];
    [_time settle];
    XCTAssertEqual(held.mostInFlight, 1u);
    [self releaseRepliesOf:held until:^BOOL {
        return NO;
    }];
    XCTAssertEqual(held.mostInFlight, 1u);
    XCTAssertEqual(_system.snapshot.monitors.count, 2u);
}

// A gap the monitors ride out keeps every lease.
- (void)testAShortGapKeepsTheLeases {
    [self startSystem];
    [self waitForDiscovery];
    NSUInteger before = _bus.sentMessages.count;
    [_time stallFor:0.05];
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
    QLMReplayAdapter *replay = [[QLMReplayAdapter alloc] initWithCapture:capture];
    [self startSystemWithAdapter:replay];
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

    [_system setVolumeDecibels:-10];  // held at the -20 dB ceiling
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return [snapshot.volumeDecibels isEqual:@(-20)];
    }];
    [_time advanceBy:0.1];
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
    [_time advanceBy:0.15];
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

// Waits until the left's and the right's last 2B are these.
- (void)waitForLeftMute:(uint8_t)left rightMute:(uint8_t)right {
    [self waitUntil:^BOOL {
        __block BOOL stated = NO;
        [self->_bus perform:^{
            stated = self->_left.muteValue == left && self->_right.muteValue == right;
        }];
        return stated;
    }];
}

// A lift of one mute under mute all lifts the adapter's own mute too, as
// GLM's unmute all does: the level, 01 2B 00, then two rounds
// (captures/mute-dim, 48.60 s). No capture shows GLM lift one mute under
// mute all. Mute all still holds for the rest, here for the right, which
// appears after it. The lift holds when the left is leased again, and
// after a relaunch from the snapshot's record.
- (void)testLiftingOneMuteUnderMuteAllHolds {
    _settings.cycleInterval = 0.3;
    [_bus perform:^{
        self->_right.present = NO;
    }];
    [self startSystem];
    QLMSnapshot *discovered = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 1 && snapshot.allIdentified && snapshot.idle;
    }];
    uint8_t left = QLMFindMonitor(discovered, _left.hardwareID).session;
    [_system setVolumeDecibels:-30];
    [_system setAllMuted:YES];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allMuted && snapshot.idle;
    }];

    NSUInteger before = _bus.sentMessages.count;
    NSData *leftID = _left.hardwareID;
    NSData *rightID = _right.hardwareID;
    QLMSystem *system = _system;
    QLMSnapshot *lifted = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return !QLMFindMonitor(snapshot, leftID).muted && snapshot.idle;
    } after:^{
        [system setMuted:NO forMonitorWithHardwareID:leftID];
    }];
    XCTAssertTrue(lifted.mutingAll);
    XCTAssertEqualObjects(lifted.liftedHardwareIDs, [NSSet setWithObject:leftID]);
    QLMMessage volume = QLMCommandVolume(-30, _settings.ceilingDecibels);
    NSData *leftUnmuted = QLMBytes((const uint8_t[]){left, 0x2B, QLMMuteValueUnmuted}, 3);
    NSArray<NSData *> *expected = @[
        QLMAdapterRecord(&volume), QLMBytes((const uint8_t[]){QLMAddressAdapter, 0x2B, QLMMuteValueAdapterUnmuted}, 3), leftUnmuted, leftUnmuted
    ];
    XCTAssertEqualObjects([self sentFrom:before matching:^BOOL(NSData *message) {
        return ((const uint8_t *)message.bytes)[1] == 0x1F || ((const uint8_t *)message.bytes)[1] == 0x2B;
    }], expected);

    [_bus perform:^{
        self->_right.present = YES;
        self->_left.session = 0;
    }];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *state = QLMFindMonitor(snapshot, leftID);
        return state.session != left && state.identified && QLMFindMonitor(snapshot, rightID).identified && snapshot.idle;
    }];
    XCTAssertFalse(QLMFindMonitor(again, leftID).muted);
    XCTAssertTrue(QLMFindMonitor(again, rightID).muted);
    [self waitForLeftMute:QLMMuteValueUnmuted rightMute:QLMMuteValueMuted];

    QLMSnapshot *stopped = [self stopAndWait];
    _settings.mutedHardwareIDs = stopped.mutedHardwareIDs;
    _settings.mutingAll = stopped.mutingAll;
    _settings.liftedHardwareIDs = stopped.liftedHardwareIDs;
    [self lapseLeases];
    [self startSystem];
    QLMSnapshot *relaunched = [self waitForDiscovery];
    XCTAssertFalse(QLMFindMonitor(relaunched, leftID).muted);
    XCTAssertTrue(QLMFindMonitor(relaunched, rightID).muted);
    XCTAssertEqualObjects(relaunched.liftedHardwareIDs, [NSSet setWithObject:leftID]);
    before = _bus.sentMessages.count;
    [_system setVolumeDecibels:-30];
    [_system setDimmed:YES];
    [_system setDimmed:NO];
    [self waitForIdle];
    XCTAssertGreaterThan([self sentWithOpcode:0x2B from:before].count, 0u);
    [self waitForLeftMute:QLMMuteValueUnmuted rightMute:QLMMuteValueMuted];
}

// A mute of the last monitor lifted brings mute all back whole: GLM's mute
// all, with 01 2B 01 (captures/mute-dim, 46.19 s), as a relaunch from the
// record would have it.
- (void)testMutingTheLastLiftedMonitorBringsMuteAllBack {
    _settings.cycleInterval = 10;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
    [_system setAllMuted:YES];
    [_system setMuted:NO forMonitorWithHardwareID:_left.hardwareID];
    [self waitForIdle];
    NSUInteger before = _bus.sentMessages.count;
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).muted && snapshot.idle;
    }];
    XCTAssertTrue(again.mutingAll);
    XCTAssertEqualObjects(again.liftedHardwareIDs, [NSSet set]);
    const uint8_t adapterMuted[] = {QLMAddressAdapter, 0x2B, QLMMuteValueAdapterMuted};
    XCTAssertEqual([self countSent:QLMBytes(adapterMuted, 3) from:before], 1u);
    QLMMessage volume = QLMCommandVolume(-30, _settings.ceilingDecibels);
    XCTAssertEqualObjects(_bus.sentMessages[before], QLMAdapterRecord(&volume));
}

// A round waits in line, and the mutes may change meanwhile. Here the user
// mutes the left, lifts mute all, and mutes the left again, quicker than
// the rounds go out (QLMSafetyFuzzTests, seed 0x2095). Each 2B says the
// mute as it is when it goes out, so none lifts the left's.
- (void)testARoundSaysTheMutesAsTheyAreWhenItGoesOut {
    _settings.cycleInterval = 10;
    [self startSystem];
    QLMSnapshot *discovered = [self waitForDiscovery];
    uint8_t left = QLMFindMonitor(discovered, _left.hardwareID).session;
    NSUInteger before = _bus.sentMessages.count;
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [_system setAllMuted:NO];
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [self waitForIdle];
    NSArray<NSData *> *mutes = [self mutesFrom:before to:[NSIndexSet indexSetWithIndex:left]];
    XCTAssertEqual(mutes.count, 6u);
    for (NSData *mute in mutes) {
        XCTAssertEqual(((const uint8_t *)mute.bytes)[2], QLMMuteValueMuted, @"%@", mute);
    }
    const uint8_t adapterUnmuted[] = {QLMAddressAdapter, 0x2B, QLMMuteValueAdapterUnmuted};
    XCTAssertEqual([self countSent:QLMBytes(adapterUnmuted, 3) from:before], 1u);
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
    [_time advanceBy:0.05];
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
    group.groupDelayCompensation = source.groupDelayCompensation;
    group.bassExtensionMode = source.bassExtensionMode;
    group.bassExtensionCrossoverMin = source.bassExtensionCrossoverMin;
    group.bassExtensionCrossoverMax = source.bassExtensionCrossoverMax;
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
    __block BOOL done = NO;
    __block NSError *result = nil;
    [_system applyGroup:group completion:^(NSError *error) {
        XCTAssertTrue([NSThread isMainThread]);
        result = error;
        done = YES;
    }];
    [self waitUntil:^BOOL {
        return done;
    }];
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
    [self waitUntil:^BOOL {
        return [self applyFramesFrom:start].count >= count;
    }];
    [_time advanceBy:0.1];
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

// Every monitor that wakes loses its lease, and GLM sends its apply at wake
// to each (docs/protocol.md, Sleep and wake; captures/standby-wake, 47.70
// to 49.09 s). In qlm-app-first, the app's wake sent none, since no group
// was active. With one active, System's wake does: each monitor leased
// again gets its whole block. The fake bus keeps its sessions over a wake,
// so the test lapses them, as the monitors do.
- (void)testAWakeAppliesTheActiveGroupToEachMonitorLeasedAgain {
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
    [_system sleep];
    QLMSnapshot *asleep = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 3 && !snapshot.anyOn && snapshot.idle;
    }];
    NSMutableIndexSet *oldSessions = [NSMutableIndexSet indexSet];
    for (QLMMonitorState *monitor in asleep.monitors) {
        [oldSessions addIndex:monitor.session];
    }

    NSUInteger before = _bus.sentMessages.count;
    [_system wake];
    [self lapseLeases];
    QLMSnapshot *woken = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        BOOL leasedAgain = snapshot.monitors.count == 3 && snapshot.allIdentified && snapshot.idle;
        for (QLMMonitorState *monitor in snapshot.monitors) {
            leasedAgain = leasedAgain && monitor.status == QLMMonitorStatusOn && ![oldSessions containsIndex:monitor.session];
        }
        return leasedAgain;
    }];
    XCTAssertEqualObjects(woken.activeGroupName, @"Mains");
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = [self blocksOf:mains];
    XCTAssertEqual(blocks.count, 3u);
    for (QLMMonitorState *monitor in woken.monitors) {
        XCTAssertGreaterThan(blocks[monitor.hardwareID].payloads.count, 0u);
        for (NSData *payload in blocks[monitor.hardwareID].payloads) {
            QLMMessage frame = QLMMessageMake(monitor.session, payload.bytes, payload.length);
            XCTAssertGreaterThan([self countSent:QLMAdapterRecord(&frame) from:before], 0u, @"%@ missed %@", monitor.serialNumber, payload);
        }
    }
}

// In qlm-app-first, the app's wake brought the monitors back without the
// group's settings, since it had none active: it refuses every group with
// an 8351B. Both 8330As played hotter until GLM applied the group
// (captures/qlm-app-first/notes.md, Surprises). So the snapshot says so,
// until a group applies, or GLM holds the adapter, whose launch applies its
// group.
- (void)testAWakeWithNoGroupActiveSaysSo {
    [self startWithKnob:nil volume:@(-40)];
    XCTAssertFalse(_system.snapshot.wokeWithoutGroup);
    [_system wake];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.wokeWithoutGroup && snapshot.idle;
    }];
    [self stopSystem];
    XCTAssertTrue(_system.snapshot.wokeWithoutGroup);  // kept across a stop
    [_system start];

    [_bus perform:^{
        self->_bus.busyReason = @"GLM is running (pid 1). Quit GLM first.";
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.busProblem == QLMBusProblemGLM && !snapshot.wokeWithoutGroup;
    }];
}

- (void)testAGroupAppliedAfterAWakeEndsIt {
    _settings.cycleInterval = 0.3;
    _settings.ceilingDecibels = 0;
    [self useMainsAndSub];
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 3 && snapshot.allIdentified && snapshot.idle;
    }];
    [_system setVolumeDecibels:-10];
    [_system wake];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.wokeWithoutGroup && snapshot.idle;
    }];
    XCTAssertNil([self applyGroup:[self mainsAndSubOf:0 named:@"Mains"]]);
    XCTAssertFalse(_system.snapshot.wokeWithoutGroup);

    // Under a group, each monitor leased again gets its block.
    [_system wake];
    QLMSnapshot *woken = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    }];
    XCTAssertFalse(woken.wokeWithoutGroup);
}

// A wake that can't go out wakes nothing.
- (void)testAWakeWhileGLMHoldsTheAdapterSaysNothing {
    _bus.busyReason = @"GLM is running (pid 1). Quit GLM first.";
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.busProblem == QLMBusProblemGLM;
    }];
    [_system wake];
    [_time advanceBy:1];
    XCTAssertFalse(_system.snapshot.wokeWithoutGroup);
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
    NSArray *knobs = @[@(-450), @(-150), NSNull.null];  // -45 dB, -15 dB above the -20 dB ceiling, and no knob
    NSArray<NSNumber *> *levels = @[@(-45), @(-20), @(QLMVolumeDecibelsMin)];
    for (NSUInteger i = 0; i < knobs.count; i++) {
        NSNumber *knob = knobs[i] == NSNull.null ? nil : knobs[i];
        [_bus perform:^{
            self->_bus.knobTenths = knob;
        }];
        [self lapseLeases];  // the last pass's
        [self startSystem];
        [self waitForDiscovery];
        NSUInteger before = _bus.sentMessages.count;
        [_system wake];
        QLMMessage level = QLMCommandVolume(levels[i].doubleValue, _settings.ceilingDecibels);
        NSArray<NSData *> *expected = [@[QLMAdapterRecord(&level)] arrayByAddingObjectsFromArray:pair];
        XCTAssertEqualObjects([self wakeEndFrom:before], expected, @"knob %@", knob);
        XCTAssertNil(_system.snapshot.volumeDecibels);
        [self stopSystem];
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
    [self stopSystem];
    // The leases lapse, and the monitor forgets its mute, as one switched
    // off and on would.
    [_bus perform:^{
        self->_left.muteValue = QLMMuteValueUnmuted;
    }];
    [self lapseLeases];
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

// Stops System and returns its snapshot once it has.
- (QLMSnapshot *)stopAndWait {
    QLMSystem *system = _system;
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.running;
    } after:^{
        [system stop];
    }];
}

// The same, with what System sent meanwhile.
- (NSArray<NSData *> *)stopAndCollect:(QLMSnapshot *_Nullable *_Nonnull)stopped {
    NSUInteger before = _bus.sentMessages.count;
    *stopped = [self stopAndWait];
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

    [self lapseLeases];
    [self startWithKnob:@(-600) volume:nil];
    XCTAssertEqualObjects([self stopAndCollect:&stopped], @[]);
    XCTAssertEqual(stopped.handBack.kind, QLMHandBackUnknown);
    XCTAssertNil(stopped.handBack.volumeDecibels);
}

// A stop no one can answer, such as a restart's, mutes every monitor first
// where the take-over would be louder or is unknown, and the record keeps
// it. A mute outlasts the host (captures/qlm-control-first, 648.7 s). At
// the knob's level, it hands back as any stop does.
- (void)testAStopMutingIfLouderMutesAllWhereTheTakeOverIsLouder {
    for (NSNumber *tenths in @[@(-300), [NSNull null]]) {
        [self startWithKnob:tenths == (id)[NSNull null] ? nil : tenths volume:@(-40)];
        [_bus perform:^{
            self->_left.muteValue = 0;
            self->_right.muteValue = 0;
        }];
        NSUInteger before = _bus.sentMessages.count;
        QLMSystem *system = _system;
        QLMSnapshot *stopped = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return !snapshot.running;
        } after:^{
            [system stopMutingIfLouderWithCompletion:nil];
        }];
        XCTAssertNotEqual(stopped.handBack.kind, QLMHandBackKnobLevel, @"%@", tenths);
        XCTAssertTrue(stopped.mutingAll, @"%@", tenths);
        XCTAssertGreaterThan([self sentWithOpcode:0x2B from:before].count, 0u, @"%@", tenths);
        [_bus perform:^{
            XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted, @"%@", tenths);
            XCTAssertEqual(self->_right.muteValue, QLMMuteValueMuted, @"%@", tenths);
        }];
        [self lapseLeases];
    }

    [self startWithKnob:@(-600) volume:@(-40)];
    NSUInteger before = _bus.sentMessages.count;
    QLMSystem *system = _system;
    QLMSnapshot *stopped = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.running;
    } after:^{
        [system stopMutingIfLouderWithCompletion:nil];
    }];
    QLMMessage knob = QLMCommandVolume(-60, _settings.ceilingDecibels);
    XCTAssertEqualObjects([self sentFrom:before matching:^BOOL(NSData *message) {
        return YES;
    }], @[QLMAdapterRecord(&knob)]);
    XCTAssertFalse(stopped.mutingAll);
}

// A start while the stop sends the knob's level runs once the stop is done.
- (void)testAStartDuringTheHandBackRunsAfterIt {
    [self startWithKnob:@(-600) volume:@(-40)];
    [self lapseLeases];
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
    [_time runUntil:^BOOL {
        QLMSnapshot *snapshot = system.snapshot;
        fewest = MIN(fewest, snapshot.monitors.count);
        for (QLMMonitorState *monitor in snapshot.monitors) {
            anyMissed = anyMissed || monitor.missedPolls > 0 || monitor.offline;
        }
        return NO;
    } within:0.5];
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

// The ceiling changes while System runs. A lowered one takes the volume
// down with it, and a raised one leaves it there. Either way, the volume
// goes out again at once.
- (void)testTheCeilingChangesWhileSystemRuns {
    _settings.cycleInterval = 10;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-30];
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
        XCTAssertEqualObjects(snapshot.volumeDecibels, @(-40));
        QLMMessage volume = QLMCommandVolume(-40, ceiling.doubleValue);
        XCTAssertEqualObjects([self sentWithOpcode:0x1F from:before], @[QLMAdapterRecord(&volume)]);
    }
}

// The Safety rule holds for frames already in line: a ceiling lowered after
// the wake queues its level caps that level too, when it goes out.
- (void)testALoweredCeilingCapsTheVolumeFramesAlreadyQueued {
    _settings.cycleInterval = 10;
    [self startSystem];
    [self waitForDiscovery];
    [_system setVolumeDecibels:-20];  // at the -20 dB ceiling
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    NSUInteger before = _bus.sentMessages.count;
    [_system wake];
    [_system setCeilingDecibels:-40];
    [self waitUntil:^BOOL {
        return [self sentWithOpcode:0x1F from:before].count >= 2;
    }];
    [_time advanceBy:0.1];
    QLMMessage capped = QLMCommandVolume(-20, -40);
    NSArray<NSData *> *levels = [self sentWithOpcode:0x1F from:before];
    XCTAssertEqual(levels.count, 2u);  // the wake's, then the ceiling's own
    for (NSData *level in levels) {
        XCTAssertEqualObjects(level, QLMAdapterRecord(&capped));
    }
}

// The same when the report link holds the frame. After a reopen, the link
// holds the first request behind its sync, and the ceiling falls meanwhile
// (QLMSafetyFuzzTests, seed 0xE6635237C78ED983). The frame goes out under
// the ceiling in force when the link writes it.
- (void)testALoweredCeilingCapsAVolumeFrameTheLinkHolds {
    _settings.cycleInterval = 10;
    QLMCaptureDevice *device = [[QLMCaptureDevice alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)];
    [self startSystemWithAdapter:device];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle;
    }];
    // The clock stands still, so nothing else touches the link meanwhile.
    [device.link closeWithError:QLMAdapterErrorMake(QLMAdapterErrorBusy, @"GLM is running.")];
    [device.link reopen];
    NSUInteger before = device.writtenReports.count;
    [_system setVolumeDecibels:0];
    [_system setCeilingDecibels:-44.5];
    [self waitForIdle];
    [_time advanceBy:0.1];
    NSData *capped = QLMReportFor(QLMCommandVolume(0, -44.5));
    NSArray<NSData *> *written = device.writtenReports;
    NSUInteger volumes = 0;
    for (NSUInteger i = before; i < written.count; i++) {
        const uint8_t *bytes = written[i].bytes;
        if (bytes[1] == QLMAddressBroadcast && bytes[2] == 0x1F) {
            volumes += 1;
            XCTAssertEqualObjects(written[i], capped);
        }
    }
    XCTAssertEqual(volumes, 2u);  // the volume's, then the ceiling's own
}

// A stop's completion runs on the main queue once System has let go of the
// adapter: after the hand-back level, with the snapshot stopped. A stop
// while not running completes at once.
- (void)testAStopCompletesOnceTheAdapterIsClosed {
    [self startWithKnob:@(-600) volume:@(-40)];
    __block BOOL stopped = NO;
    QLMSystem *system = _system;
    QLMFakeBus *bus = _bus;
    QLMMessage knob = QLMCommandVolume(-60, _settings.ceilingDecibels);
    NSData *knobRecord = QLMAdapterRecord(&knob);
    [_system stopWithCompletion:^{
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertFalse(system.snapshot.running);
        XCTAssertEqualObjects(bus.sentMessages.lastObject, knobRecord);
        stopped = YES;
    }];
    [self waitUntil:^BOOL {
        return stopped;
    }];
    [self stopSystem];
}

// After a restart, a monitor that still holds its lease never answers the
// probe. System asks each monitor it knew for its serial at its old
// session, and takes the lease back at once when the serial is the same.
// One whose old session now answers with another serial is not taken: the
// session is another monitor's.
- (void)testARestartTakesBackLeasesStillHeld {
    _settings.cycleInterval = 10;
    [self startSystem];
    QLMSnapshot *first = [self waitForDiscovery];
    uint8_t leftSession = QLMFindMonitor(first, _left.hardwareID).session;
    uint8_t rightSession = QLMFindMonitor(first, _right.hardwareID).session;
    [self stopAndWait];

    NSUInteger before = _bus.sentMessages.count;
    [_system start];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.running && snapshot.monitors.count == 2 && snapshot.allIdentified;
    }];
    XCTAssertEqual(QLMFindMonitor(again, _left.hardwareID).session, leftSession);
    XCTAssertEqual(QLMFindMonitor(again, _right.hardwareID).session, rightSession);
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:before], 0u);

    // The left lets its lease lapse, and the right now holds the left's old
    // session.
    [self stopAndWait];
    [_bus perform:^{
        self->_left.session = 0;
        self->_right.session = leftSession;
    }];
    [_system start];
    QLMSnapshot *moved = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *left = QLMFindMonitor(snapshot, self->_left.hardwareID);
        return snapshot.running && left.identified;
    }];
    XCTAssertNotEqual(QLMFindMonitor(moved, _left.hardwareID).session, leftSession);
    XCTAssertNil(QLMFindMonitor(moved, _right.hardwareID));
}

// No capture has a frame to a session above 19, from GLM or qlm. The
// highest is GLM's lease of 19 in unplug, at 69.241 s. GLM leases from 02 at
// each launch: in startup-idle, startup-idle-mic, and knob-sweep. So System
// counts from 02 at each start, and wraps after 19.
- (void)testGLMCountsFrom02AtLaunchAndNoCaptureGoesAbove19 {
    uint8_t highest = 0;
    for (NSString *scenario in QLMCaptureScenarios()) {
        NSNumber *firstLease = nil;
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            QLMMessage message = exchange.message;
            if (QLMAddressIsLeasable(message.address)) {
                highest = MAX(highest, message.address);
            }
            if (QLMIsLease(message)) {
                highest = MAX(highest, message.payload[4]);
                firstLease = firstLease ?: @(message.payload[4]);
            }
        }
        if ([@[@"startup-idle", @"startup-idle-mic", @"knob-sweep"] containsObject:scenario]) {
            XCTAssertEqualObjects(firstLease, @(QLMAddressSessionFirst), @"%@", scenario);
        }
    }
    XCTAssertEqual(highest, 0x19);
}

// Both leases lapse, and System waits until the probe has found both
// monitors again, at new sessions.
- (QLMSnapshot *)lapseAndFindAgain:(QLMSnapshot *)last {
    uint8_t left = QLMFindMonitor(last, _left.hardwareID).session;
    uint8_t right = QLMFindMonitor(last, _right.hardwareID).session;
    [self lapseLeases];
    return [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        QLMMonitorState *newLeft = QLMFindMonitor(snapshot, self->_left.hardwareID);
        QLMMonitorState *newRight = QLMFindMonitor(snapshot, self->_right.hardwareID);
        return newLeft.identified && newRight.identified && newLeft.session != left && newRight.session != right;
    }];
}

// One System runs all week. Over an hour on the clock here, the leases lapse
// 40 times, so the count goes round from 02 to 19 more than three times.
// No frame goes to a session above 19, the highest any capture shows.
- (void)testALongRunNeverSendsASessionAbove19 {
    _settings.cycleInterval = 0.57;
    [self startSystem];
    [_system setVolumeDecibels:-40];
    QLMSnapshot *snapshot = [self waitForDiscovery];
    NSMutableIndexSet *leased = [NSMutableIndexSet indexSet];
    for (int i = 0; i < 40; i++) {
        snapshot = [self lapseAndFindAgain:snapshot];
        [_time advanceBy:90];
    }
    for (NSData *record in _bus.sentMessages) {
        const uint8_t *bytes = record.bytes;
        if (bytes[0] == QLMAddressMulticast && record.length == 6 && bytes[1] == 0x02) {
            [leased addIndex:bytes[5]];
            XCTAssertLessThanOrEqual(bytes[5], 0x19, @"%@", record);
        } else if (QLMAddressIsLeasable(bytes[0])) {
            XCTAssertLessThanOrEqual(bytes[0], 0x19, @"%@", record);
        }
    }
    XCTAssertEqualObjects(leased, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0x02, 0x18)]);
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:0], 82u);
}

// GLM counts from 02 at each launch, and each start does too. Here the
// count has reached 09 when System stops. The right's lease lapses, and the
// left still holds its own. At the restart, System asks each old session
// for its serial before it leases anything, takes the left back at its
// session, and leases the right 02.
- (void)testARestartBeginsAgainAtTheFirstSession {
    _settings.cycleInterval = 0.57;
    [self startSystem];
    QLMSnapshot *snapshot = [self waitForDiscovery];
    for (int i = 0; i < 3; i++) {
        snapshot = [self lapseAndFindAgain:snapshot];
    }
    uint8_t leftSession = QLMFindMonitor(snapshot, _left.hardwareID).session;
    uint8_t rightSession = QLMFindMonitor(snapshot, _right.hardwareID).session;
    XCTAssertEqual(MAX(leftSession, rightSession), 0x09);
    [self stopAndWait];
    [_bus perform:^{
        self->_right.session = 0;
    }];

    NSUInteger before = _bus.sentMessages.count;
    [_system start];
    QLMSnapshot *again = [self waitForSnapshot:^BOOL(QLMSnapshot *received) {
        return received.running && received.monitors.count == 2 && received.allIdentified;
    }];
    XCTAssertEqual(QLMFindMonitor(again, _left.hardwareID).session, leftSession);
    XCTAssertEqual(QLMFindMonitor(again, _right.hardwareID).session, QLMAddressSessionFirst);
    NSArray<NSData *> *sent = [self sentFrom:before matching:^BOOL(NSData *message) {
        const uint8_t *bytes = message.bytes;
        return bytes[0] == QLMAddressMulticast || (bytes[0] != QLMAddressAdapter && message.length == 3 && bytes[1] == 0x19);
    }];
    QLMMessage firstCheck = QLMCommandSerialNumber(MIN(leftSession, rightSession));
    QLMMessage secondCheck = QLMCommandSerialNumber(MAX(leftSession, rightSession));
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    QLMMessage lease = QLMCommandAssignSession(rightID, QLMAddressSessionFirst);
    XCTAssertGreaterThanOrEqual(sent.count, 3u);
    XCTAssertEqualObjects([sent subarrayWithRange:NSMakeRange(0, 3)],
                          (@[QLMAdapterRecord(&firstCheck), QLMAdapterRecord(&secondCheck), QLMAdapterRecord(&lease)]));
}

// A monitor whose replies are lost takes its lease all the same, and hides
// from the probe while it holds it. Here the right's serial is never read,
// so no check finds it after the restart. The count starts at 02 again, but
// the session the right last held goes to no other monitor.
- (void)testARestartLeasesNoOneTheSessionAMonitorMayStillHold {
    const uint8_t thirdID[3] = {0x77, 0x88, 0x99};
    QLMFakeMonitor *third = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:thirdID length:3] serialNumber:@"8320apm21009999"
                                                            systemInfo:@"c-1;model-8320A" deviceClass:QLMTelemetryClassTwoWay];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _right, third]];
    _right.dropReplies = 1000;
    [self startSystem];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).identified && QLMFindMonitor(snapshot, third.hardwareID).identified &&
               QLMFindMonitor(snapshot, self->_right.hardwareID) == nil;
    }];
    [self stopAndWait];
    __block uint8_t hidden = 0;
    [_bus perform:^{
        hidden = self->_right.session;
        self->_left.session = 0;
        third.session = 0;
    }];
    XCTAssertNotEqual(hidden, 0);

    NSUInteger before = _bus.sentMessages.count;
    [_system start];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.running && QLMFindMonitor(snapshot, self->_left.hardwareID).identified &&
               QLMFindMonitor(snapshot, third.hardwareID).identified;
    }];
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:before], 2u);
    XCTAssertEqual([self sentFrom:before to:[NSIndexSet indexSetWithIndex:hidden]].count, 0u);
    [_bus perform:^{
        XCTAssertEqual(self->_left.session, QLMAddressSessionFirst);
        XCTAssertNotEqual(third.session, hidden);
        XCTAssertEqual(self->_right.session, hidden);
    }];
}

// Every frame sent from `start` on to any of `sessions`.
- (NSArray<NSData *> *)sentFrom:(NSUInteger)start to:(NSIndexSet *)sessions {
    return [self sentFrom:start matching:^BOOL(NSData *message) {
        return [sessions containsIndex:((const uint8_t *)message.bytes)[0]];
    }];
}

// GLM leases from 02 in its own probe order, and a host that quits leaves
// its leases: in captures/qlm-first-discover they held for up to 42 s after
// GLM quit. Here GLM takes the bus, leases each monitor the other's
// session, and quits. When the bus comes back, System drops its records and
// asks each old session for its serial. Each answers with the other
// monitor's, so System sends nothing more to either session, and leases
// neither. Once GLM's leases lapse, the probe finds both monitors, and each
// hears its own mute.
- (void)testABusThatComesBackChecksEveryLeaseBeforeUsingIt {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    QLMSnapshot *first = [self waitForDiscovery];
    uint8_t leftSession = QLMFindMonitor(first, _left.hardwareID).session;
    uint8_t rightSession = QLMFindMonitor(first, _right.hardwareID).session;
    NSMutableIndexSet *oldSessions = [NSMutableIndexSet indexSetWithIndex:leftSession];
    [oldSessions addIndex:rightSession];
    [_system setVolumeDecibels:-30];
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).muted && snapshot.idle;
    }];

    [_bus perform:^{
        self->_bus.busyReason = @"GLM is running (pid 1). Quit GLM first.";
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.busProblem == QLMBusProblemGLM;
    }];
    [_bus perform:^{
        self->_left.session = rightSession;
        self->_right.session = leftSession;
        self->_left.muteValue = QLMMuteValueUnmuted;
        self->_right.muteValue = QLMMuteValueUnmuted;
        self->_bus.busyReason = nil;
    }];
    NSUInteger before = _bus.sentMessages.count;
    [_time advanceBy:0.3];
    QLMSnapshot *back = _system.snapshot;
    XCTAssertEqual(back.busProblem, QLMBusProblemNone);
    XCTAssertEqual(back.monitors.count, 0u);
    QLMMessage leftCheck = QLMCommandSerialNumber(leftSession);
    QLMMessage rightCheck = QLMCommandSerialNumber(rightSession);
    NSSet<NSData *> *checks = [NSSet setWithObjects:QLMAdapterRecord(&leftCheck), QLMAdapterRecord(&rightCheck), nil];
    XCTAssertEqualObjects([NSSet setWithArray:[self sentFrom:before to:oldSessions]], checks);
    XCTAssertEqual([self sentFrom:before to:oldSessions].count, 2u);

    [self lapseLeases];
    QLMSnapshot *found = [self waitForDiscovery];
    for (QLMMonitorState *monitor in found.monitors) {
        XCTAssertFalse([oldSessions containsIndex:monitor.session], @"%02X", monitor.session);
    }
    [self sendEveryMuteRound];
    XCTAssertEqual([self sentFrom:before to:oldSessions].count, 2u);
    [_bus perform:^{
        XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted);
        XCTAssertEqual(self->_right.muteValue, QLMMuteValueUnmuted);
    }];
}

// The same, with the leases where System left them. Each monitor is taken
// back at once, with no lease, and hears its own state after its first
// poll, since the other host changed both mutes.
- (void)testABusThatComesBackTakesBackTheLeasesStillHeld {
    _settings.adapterPollInterval = 0.01;
    [self startSystem];
    QLMSnapshot *first = [self waitForDiscovery];
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).muted && snapshot.idle;
    }];
    [_bus perform:^{
        self->_bus.busyReason = @"GLM is running (pid 1). Quit GLM first.";
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil;
    }];
    [_bus perform:^{
        self->_left.muteValue = QLMMuteValueUnmuted;
        self->_right.muteValue = QLMMuteValueMuted;
        self->_bus.busyReason = nil;
    }];
    NSUInteger before = _bus.sentMessages.count;
    [self waitForLeftMute:QLMMuteValueMuted rightMute:QLMMuteValueUnmuted];
    QLMSnapshot *back = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.idle;
    }];
    for (QLMMonitorState *monitor in first.monitors) {
        XCTAssertEqual(QLMFindMonitor(back, monitor.hardwareID).session, monitor.session);
    }
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:before], 0u);
}

// The app makes a new System at each launch, which knows no leases of its
// own, so it gives the new one the last snapshot's. Across a quick relaunch
// here, the right's lease lapses, and the muted left still holds its own.
// The new System takes the left back at its session, and leases the right
// another, so no 2B reaches both.
- (void)testANewSystemChecksTheLeasesItIsGivenBeforeLeasing {
    [self startSystem];
    QLMSnapshot *first = [self waitForDiscovery];
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).muted && snapshot.idle;
    }];
    QLMSnapshot *stopped = [self stopAndWait];
    XCTAssertEqual(stopped.knownLeases.count, 2u);
    uint8_t lastSession = 0;
    for (QLMKnownLease *lease in stopped.knownLeases) {
        QLMMonitorState *monitor = QLMFindMonitor(first, lease.hardwareID);
        XCTAssertEqual(lease.session, monitor.session);
        XCTAssertEqualObjects(lease.serialNumber, monitor.serialNumber);
        XCTAssertGreaterThan(lease.session, lastSession);
        lastSession = lease.session;
    }
    uint8_t leftSession = QLMFindMonitor(first, _left.hardwareID).session;
    [_bus perform:^{
        self->_right.session = 0;
    }];

    _settings.knownLeases = stopped.knownLeases;
    _settings.mutedHardwareIDs = stopped.mutedHardwareIDs;
    NSUInteger before = _bus.sentMessages.count;
    [self startSystem];
    QLMSnapshot *again = [self waitForDiscovery];
    XCTAssertEqual(QLMFindMonitor(again, _left.hardwareID).session, leftSession);
    XCTAssertNotEqual(QLMFindMonitor(again, _right.hardwareID).session, leftSession);
    XCTAssertEqual([self countSentTo:QLMAddressMulticast opcode:0x02 from:before], 1u);
    [_bus perform:^{
        XCTAssertNotEqual(self->_right.session, self->_left.session);
        XCTAssertEqual(self->_left.muteValue, QLMMuteValueMuted);
    }];
}

// The adapter goes silent, through the report link the HID adapter uses.
// About 2.6 s after the host goes quiet, the adapter takes over at the
// knob's level (captures/qlm-control-first/notes.md), so the snapshot says
// it stopped answering, apart from no adapter, and keeps the last knob
// reading for the warning. Once it answers again, the link resyncs, and
// System takes every lease back.
- (void)testASilentAdapterShowsAsItsOwnProblemWithTheKnobKept {
    _settings.cycleInterval = 0.05;
    _settings.adapterPollInterval = 0.02;
    QLMCaptureDevice *device = [[QLMCaptureDevice alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)];
    [self startSystemWithAdapter:device];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.adapter.identified && snapshot.idle;
    }];
    device.silent = YES;
    QLMSnapshot *silent = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil;
    }];
    XCTAssertEqual(silent.adapterProblem, QLMAdapterProblemUnresponsive);
    XCTAssertEqual(silent.busProblem, QLMBusProblemNoAdapter);
    XCTAssertEqual(silent.adapterError.code, QLMAdapterErrorUnresponsive);
    XCTAssertEqualObjects(silent.handBack.knobDecibels, @(-100.4));
    XCTAssertTrue(silent.adapter.identified);

    device.silent = NO;
    QLMSnapshot *back = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError == nil && snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle;
    }];
    XCTAssertEqual(back.adapterProblem, QLMAdapterProblemNone);
    [self stopSystem];
    // Every report is GLM's, but the state each monitor taken back hears:
    // GLM sent 2B 04 only to Main 2x1's members, and no group is active here.
    NSMutableSet<NSData *> *captured = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"startup-idle", NULL).exchanges) {
        [captured addObject:exchange.outputReport];
    }
    for (NSData *report in device.writtenReports) {
        const uint8_t *bytes = report.bytes;
        BOOL state = bytes[2] == 0x2B && bytes[3] == QLMMuteValueUnmuted;
        XCTAssertTrue([captured containsObject:report] || state, @"%@", report);
    }
}

// A link that lost track is a problem of its own too, and keeps the knob.
- (void)testALinkThatLostTrackShowsAsItsOwnProblem {
    QLMFailingAdapter *failing = [[QLMFailingAdapter alloc] initWithAdapter:_bus];
    [self startSystemWithAdapter:failing];
    [self waitForDiscovery];
    failing.failure = QLMAdapterErrorMake(QLMAdapterErrorLostTrack, @"qlm lost track of the GLM adapter's replies.");
    QLMSnapshot *lost = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil;
    }];
    XCTAssertEqual(lost.adapterProblem, QLMAdapterProblemLostTrack);
    XCTAssertEqual(lost.busProblem, QLMBusProblemNoAdapter);
    XCTAssertEqualObjects(lost.handBack.knobDecibels, @(-100.4));
}

// A System on the capture device, behind the report link the HID adapter
// uses, with startup-idle's six monitors found. Then the adapter goes
// silent. It is polled every 0.1 s, so System hears within 0.1 s that the
// link gave up.
- (QLMCaptureDevice *)startOnASilentLink {
    _settings.cycleInterval = 0.05;
    _settings.adapterPollInterval = 0.1;
    QLMCaptureDevice *device = [[QLMCaptureDevice alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)];
    [self startSystemWithAdapter:device];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.adapter.identified && snapshot.idle;
    }];
    device.silent = YES;
    return device;
}

// The link gives up on a silent adapter 7.5 s after its first sync
// (QLMReportLinkTests). System reopens the adapter 1 s after it hears so,
// and the link syncs again. Each wait is twice the one before, up to 30 s.
// Once the adapter answers, the reopen's own sync brings the link back in
// step. System takes every lease back by serial, as after any gap, and the
// knob reading stays meanwhile for the take-over's warning
// (captures/qlm-control-first/notes.md). A mute just after a reopen goes
// out only once the link is back, and reopens nothing early: its 2B is
// refused with System's own error, the old one. Every report is GLM's but
// the 2Bs, so the syncs are frames a start sends too.
- (void)testALinkThatGaveUpReopensAtABackoffUntilTheAdapterAnswers {
    QLMCaptureDevice *device = [self startOnASilentLink];
    QLMSnapshot *gaveUp = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError.code == QLMAdapterErrorGaveUp;
    }];
    XCTAssertEqual(gaveUp.adapterProblem, QLMAdapterProblemUnresponsive);
    XCTAssertEqual(gaveUp.busProblem, QLMBusProblemNoAdapter);
    XCTAssertEqual(gaveUp.reconnects, 0u);
    XCTAssertEqualObjects(gaveUp.handBack.knobDecibels, @(-100.4));
    XCTAssertTrue(gaveUp.adapter.identified);
    XCTAssertEqual(device.reconnectTimes.count, 0u);
    NSData *muted = gaveUp.monitors.firstObject.hardwareID;
    NSTimeInterval heard = _time.now;

    NSArray<NSNumber *> *waits = @[@1, @2, @4, @8, @16, @30, @30];
    for (NSUInteger attempt = 1; attempt < waits.count; attempt++) {
        QLMSnapshot *snapshot = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return snapshot.reconnects == attempt;
        }];
        XCTAssertEqual(snapshot.adapterProblem, QLMAdapterProblemUnresponsive);
        XCTAssertEqualObjects(snapshot.handBack.knobDecibels, @(-100.4));
        if (attempt == 1) {
            [_system setMuted:YES forMonitorWithHardwareID:muted];
        }
    }
    [self waitUntil:^BOOL {
        return device.link.gaveUp;
    }];
    device.silent = NO;
    QLMSnapshot *back = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError == nil && snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle;
    }];
    XCTAssertEqual(back.reconnects, 0u);
    XCTAssertEqual(back.adapterProblem, QLMAdapterProblemNone);
    XCTAssertTrue(QLMFindMonitor(back, muted).muted);
    uint8_t mutedSession = QLMFindMonitor(back, muted).session;

    // The first wait runs from when System heard the link gave up, at most
    // one adapter poll before its snapshot. Between reopens: the link's
    // 7.5 s of syncs, at most one adapter poll until System hears it gave
    // up, then the wait.
    NSArray<NSNumber *> *times = device.reconnectTimes;
    XCTAssertEqual(times.count, waits.count);
    for (NSUInteger i = 0; i < MIN(times.count, waits.count); i++) {
        NSTimeInterval gap = times[i].doubleValue - (i == 0 ? heard : times[i - 1].doubleValue);
        NSTimeInterval syncs = i == 0 ? -0.1 : 7.5;
        XCTAssertGreaterThanOrEqual(gap, syncs + waits[i].doubleValue - 1e-6, @"reopen %lu", (unsigned long)i + 1);
        XCTAssertLessThanOrEqual(gap, syncs + waits[i].doubleValue + 0.1 + 1e-6, @"reopen %lu", (unsigned long)i + 1);
    }
    [self stopSystem];
    NSMutableSet<NSData *> *captured = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"startup-idle", NULL).exchanges) {
        [captured addObject:exchange.outputReport];
    }
    BOOL mutedHeard = NO;
    for (NSData *report in device.writtenReports) {
        const uint8_t *bytes = report.bytes;
        BOOL state = bytes[2] == 0x2B && (bytes[3] == QLMMuteValueUnmuted || bytes[3] == QLMMuteValueMuted);
        XCTAssertTrue([captured containsObject:report] || state, @"%@", report);
        mutedHeard = mutedHeard || (state && bytes[1] == mutedSession && bytes[3] == QLMMuteValueMuted);
    }
    XCTAssertTrue(mutedHeard);
}

// The adapter is unplugged while System reopens it, and IOKit says so. The
// link closes, and the adapter shows as no adapter. System reopens nothing
// more, and the HID adapter waits for the adapter to arrive anew.
- (void)testAnUnpluggedAdapterEndsTheReconnects {
    QLMCaptureDevice *device = [self startOnASilentLink];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.reconnects == 1;
    }];
    [device unplug];
    QLMSnapshot *gone = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError.code == QLMAdapterErrorDisconnected;
    }];
    XCTAssertEqual(gone.busProblem, QLMBusProblemNoAdapter);
    XCTAssertEqual(gone.adapterProblem, QLMAdapterProblemNone);
    XCTAssertEqual(gone.reconnects, 0u);
    [_time advanceBy:120];
    XCTAssertEqual(device.reconnectTimes.count, 1u);
}

// A reopen that fails leaves the link given up. Each failure counts as an
// attempt, and the next comes after the next wait, with no syncs between.
// Once the device opens, the link syncs again and comes back.
- (void)testAFailedReopenIsTriedAgainAfterTheNextWait {
    QLMCaptureDevice *device = [self startOnASilentLink];
    device.refusesOpen = YES;
    for (NSUInteger attempt = 1; attempt <= 2; attempt++) {
        QLMSnapshot *failed = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return snapshot.reconnects == attempt;
        }];
        XCTAssertEqual(failed.adapterProblem, QLMAdapterProblemUnresponsive);
        XCTAssertEqual(failed.adapterError.code, QLMAdapterErrorGaveUp);
    }
    device.refusesOpen = NO;
    device.silent = NO;
    QLMSnapshot *back = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError == nil && snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle;
    }];
    XCTAssertEqual(back.reconnects, 0u);
    NSArray<NSNumber *> *times = device.reconnectTimes;
    XCTAssertEqual(times.count, 3u);
    if (times.count == 3) {
        XCTAssertEqualWithAccuracy(times[1].doubleValue - times[0].doubleValue, 2, 1e-6);
        XCTAssertEqualWithAccuracy(times[2].doubleValue - times[1].doubleValue, 4, 1e-6);
    }
}

// A QLMAdapterErrorGaveUp that reaches System only after a reopen is stale:
// the link syncs again by then. It schedules no early reopen. The next comes
// only once the link gives up again.
- (void)testAGaveUpFromBeforeAReopenReopensNothingEarly {
    _settings.cycleInterval = 0.05;
    _settings.adapterPollInterval = 0.1;
    QLMCaptureDevice *device = [[QLMCaptureDevice alloc] initWithCapture:QLMReadCapture(@"startup-idle", NULL)];
    QLMLateGaveUpAdapter *late = [[QLMLateGaveUpAdapter alloc] initWithDevice:device];
    [self startSystemWithAdapter:late];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle;
    }];
    device.silent = YES;
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError.code == QLMAdapterErrorGaveUp;
    }];
    late.holds = YES;
    [self waitUntil:^BOOL {
        return device.reconnectTimes.count == 1;
    }];
    XCTAssertTrue([late releaseHeld]);
    [self waitUntil:^BOOL {
        return device.reconnectTimes.count == 2;
    }];
    NSArray<NSNumber *> *times = device.reconnectTimes;
    XCTAssertGreaterThanOrEqual(times[1].doubleValue - times[0].doubleValue, 7.5 + 2 - 1e-6);
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.reconnects == 2;
    }];
}

// The adapter took the first sync, then stopped taking reports, as when
// IOKit times out on its OUT endpoint after 5 s. Each reopen would block
// System's queue for seconds, so System reopens nothing, and the snapshot
// says the adapter stopped taking reports.
- (void)testALinkWhoseSyncsWereNotTakenIsNotReopened {
    QLMCaptureDevice *device = [self startOnASilentLink];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError.code == QLMAdapterErrorUnresponsive;
    }];
    device.refusesReports = YES;
    QLMSnapshot *stopped = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError.code == QLMAdapterErrorStoppedTaking;
    }];
    XCTAssertEqual(stopped.adapterProblem, QLMAdapterProblemNotTaking);
    XCTAssertEqual(stopped.busProblem, QLMBusProblemNoAdapter);
    XCTAssertEqualObjects(stopped.handBack.knobDecibels, @(-100.4));
    NSUInteger written = device.writtenReports.count;
    [_time advanceBy:120];
    XCTAssertEqual(device.reconnectTimes.count, 0u);
    XCTAssertEqual(device.writtenReports.count, written);
}

// A stop while System waits to reopen the adapter ends the wait. Nothing is
// reopened, and nothing more is written.
- (void)testAStopDuringTheWaitEndsTheReconnects {
    QLMCaptureDevice *device = [self startOnASilentLink];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError.code == QLMAdapterErrorGaveUp;
    }];
    [self stopAndWait];
    NSUInteger written = device.writtenReports.count;
    [_time advanceBy:120];
    XCTAssertEqual(device.reconnectTimes.count, 0u);
    XCTAssertEqual(device.writtenReports.count, written);
}

// IOHIDDeviceSetReport blocks up to the device's 5 s timeout when the
// adapter stops taking reports (QLMHIDAdapter.m), and then nothing went out.
// So a poll IOKit never took is no missed poll, and drops no monitor that
// still holds its lease.
- (void)testAPollIOKitDidNotTakeIsNoMissedPoll {
    QLMFailingAdapter *failing = [[QLMFailingAdapter alloc] initWithAdapter:_bus];
    [self startSystemWithAdapter:failing];
    [self waitForDiscovery];
    failing.matches = ^BOOL(const QLMMessage *message) {
        return QLMAddressIsLeasable(message->address) && message->payload[0] == 0x08;
    };
    failing.failure = QLMHIDWriteError(kIOReturnTimeout);
    __block NSUInteger fewest = 2;
    __block NSUInteger mostMissed = 0;
    QLMSystem *system = _system;
    [_time runUntil:^BOOL {
        QLMSnapshot *snapshot = system.snapshot;
        fewest = MIN(fewest, snapshot.monitors.count);
        for (QLMMonitorState *monitor in snapshot.monitors) {
            mostMissed = MAX(mostMissed, monitor.missedPolls);
        }
        return NO;
    } within:1];
    XCTAssertEqual(fewest, 2u);
    XCTAssertEqual(mostMissed, 0u);
}

// A mute whose 2B never went out still reaches the monitor. As GLM states a
// new monitor's mute right after its first poll (captures/startup-idle,
// 9.861 s), each monitor whose 2B IOKit did not take hears its state after
// its next poll: the left its mute, and the right the lift of its own.
- (void)testAMuteWhose2BDidNotGoOutIsStatedAfterTheNextPoll {
    QLMFailingAdapter *failing = [[QLMFailingAdapter alloc] initWithAdapter:_bus];
    [self startSystemWithAdapter:failing];
    [self waitForDiscovery];
    [_system setMuted:YES forMonitorWithHardwareID:_right.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_right.hardwareID).muted && snapshot.idle;
    }];
    failing.matches = ^BOOL(const QLMMessage *message) {
        return QLMAddressIsLeasable(message->address) && message->payload[0] == 0x2B;
    };
    failing.failure = QLMHIDWriteError(kIOReturnTimeout);
    [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    [_system setMuted:NO forMonitorWithHardwareID:_right.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_left.hardwareID).muted && !QLMFindMonitor(snapshot, self->_right.hardwareID).muted &&
               snapshot.idle;
    }];
    [_bus perform:^{
        XCTAssertEqual(self->_right.muteValue, QLMMuteValueMuted);
    }];
    failing.failure = nil;
    [self waitForLeftMute:QLMMuteValueMuted rightMute:QLMMuteValueUnmuted];
}

// A stop drops the rounds still queued. A mute lifted just before a stop
// reaches the monitor at the next start, after its first poll. The round
// goes to the left first, so only the right's 2B is dropped here.
- (void)testAMuteLiftedJustBeforeAStopReachesTheMonitorAtTheNextStart {
    [self startSystem];
    [self waitForDiscovery];
    [_system setMuted:YES forMonitorWithHardwareID:_right.hardwareID];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return QLMFindMonitor(snapshot, self->_right.hardwareID).muted && snapshot.idle;
    }];
    [_system setMuted:NO forMonitorWithHardwareID:_right.hardwareID];
    [self stopSystem];
    [_bus perform:^{
        XCTAssertEqual(self->_right.muteValue, QLMMuteValueMuted);
    }];
    [_system start];
    [self waitForLeftMute:QLMMuteValueUnmuted rightMute:QLMMuteValueUnmuted];
    XCTAssertFalse(QLMFindMonitor(_system.snapshot, _right.hardwareID).muted);
}

// The snapshot says why nothing reaches the bus, typed: no adapter, GLM, or
// another host. GLM's case is pinned to the sentence QLMHostCheck writes.
- (void)testTheSnapshotSaysWhoHoldsTheBus {
    [self startSystem];
    [self waitForDiscovery];
    NSDictionary *glmClient = @{
        @"IOUserClientCreator": @"pid 74853, GLMv5",
        @"DebugState": @{@"ClientSeized": @NO, @"ClientOptions": @1, @"Privileged": @NO, @"ClientOpened": @YES, @"ClientSuspended": @NO},
    };
    NSString *glm = QLMHostCheckClientHolder(@"IOHIDLibUserClient", glmClient, 4242);
    XCTAssertNotNil(glm);
    NSDictionary<NSString *, NSNumber *> *cases = @{glm: @(QLMBusProblemGLM), @"Spotify (pid 7) holds the GLM adapter.": @(QLMBusProblemOtherHost)};
    for (NSString *reason in cases) {
        [_bus perform:^{
            self->_bus.busyReason = reason;
        }];
        QLMSnapshot *refused = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return snapshot.busProblem == cases[reason].integerValue;
        }];
        XCTAssertEqualObjects(refused.adapterError.localizedDescription, reason);
        [_bus perform:^{
            self->_bus.busyReason = nil;
        }];
        [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
            return snapshot.busProblem == QLMBusProblemNone && snapshot.adapterError == nil;
        }];
    }
    [_bus perform:^{
        self->_bus.disconnected = YES;
    }];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.busProblem == QLMBusProblemNoAdapter;
    }];
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
// The setting is off by default. The supervised test's block carries 43 00 02
// and 4B 00 00 00 01, as GLM's does. The refused apply sends neither.
- (void)testOnlyTheSupervisedSettingAppliesAnUnverifiedRate {
    XCTAssertFalse([[QLMSystemSettings alloc] init].allowsUnverifiedRates);
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
        uint8_t session = QLMFindMonitor(_system.snapshot, _left.hardwareID).session;
        if (allowed.boolValue) {
            XCTAssertNil(error);
            XCTAssertEqual([self sentWithOpcode:0x17 from:before].count, 1u);
            const uint8_t frame43[] = {session, 0x43, 0x00, 0x02};
            const uint8_t frame4B[] = {session, 0x4B, 0x00, 0x00, 0x00, 0x01};
            XCTAssertEqualObjects([self sentWithOpcode:0x43 from:before], @[QLMBytes(frame43, sizeof frame43)]);
            XCTAssertEqualObjects([self sentWithOpcode:0x4B from:before], @[QLMBytes(frame4B, sizeof frame4B)]);
        } else {
            XCTAssertEqual(error.code, QLMSystemErrorUnverifiedRate);
            XCTAssertEqual([self sentWithOpcode:0x17 from:before].count, 0u);
            XCTAssertEqual([self sentWithOpcode:0x43 from:before].count, 0u);
            XCTAssertEqual([self sentWithOpcode:0x4B from:before].count, 0u);
        }
        [self stopAndWait];
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
    __block BOOL done = NO;
    [_system switchToGroup:group completion:^(NSError *error) {
        XCTAssertNil(error);
        done = YES;
    }];
    [self waitUntil:^BOOL {
        return done;
    }];
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
    __block NSUInteger done = 0;
    __block NSError *firstError = nil;
    __block NSError *secondError = nil;
    [_system applyGroup:group completion:^(NSError *error) {
        firstError = error;
        done += 1;
    }];
    [_system applyGroup:group completion:^(NSError *error) {
        secondError = error;
        done += 1;
    }];
    [self waitUntil:^BOOL {
        return done == 2;
    }];
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

#pragma mark - Call numbers

// The numbers run in their order on System's queue, whatever thread calls.
// So the snapshot that carries the last number holds the level that call
// set, and no snapshot carries a lower number than one before it.
- (void)testCallsFromManyThreadsRunInTheOrderOfTheirNumbers {
    [self startSystem];
    [self waitForIdle];
    QLMSystem *system = _system;
    QLMCallNumber first = system.snapshot.lastCall + 1;
    NSMutableDictionary<NSNumber *, NSNumber *> *levels = [NSMutableDictionary dictionary];
    dispatch_apply(64, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t i) {
        double level = -30 - (double)i * 0.5;
        QLMCallNumber call = [system setVolumeDecibels:level];
        @synchronized(levels) {
            levels[@(call)] = @(level);
        }
    });
    XCTAssertEqual(levels.count, 64u);
    QLMCallNumber last = first + 63;
    for (QLMCallNumber call = first; call <= last; call++) {
        XCTAssertNotNil(levels[@(call)], @"call %llu", call);
    }
    QLMSnapshot *shown = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.lastCall == last;
    }];
    XCTAssertEqualObjects(shown.volumeDecibels, levels[@(last)]);
    dispatch_sync(_snapshots, ^{
        for (NSUInteger i = 1; i < self->_received.count; i++) {
            XCTAssertGreaterThanOrEqual(self->_received[i].lastCall, self->_received[i - 1].lastCall);
        }
    });
}

// A volume set within volumeInterval of the last frame waits on a timer,
// with nothing queued for the bus. No snapshot that carries its call is idle
// until its frame is out.
- (void)testACoalescedVolumeIsNotIdleUntilItsFrameIsOut {
    _settings.cycleInterval = 10;
    _settings.volumeInterval = 0.05;
    [self startSystem];
    [self waitForIdle];
    QLMSystem *system = _system;
    QLMCallNumber first = [system setVolumeDecibels:-40];
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.lastCall >= first;
    }];
    NSTimeInterval firstSent = _time.now;
    NSUInteger before = _bus.sentMessages.count;
    QLMMessage level = QLMCommandVolume(-45, _settings.ceilingDecibels);
    NSData *frame = QLMAdapterRecord(&level);
    QLMFakeBus *bus = _bus;
    __block QLMCallNumber call = 0;
    __block BOOL outWhenShown = NO;
    [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        if (call == 0 || snapshot.lastCall < call || !snapshot.idle) {
            return NO;
        }
        outWhenShown = [bus.sentMessages containsObject:frame];
        return YES;
    } after:^{
        call = [system setVolumeDecibels:-45];
        [self->_time settle];
        XCTAssertEqual([self countSent:frame from:before], 0u);  // coalesced
        XCTAssertFalse([system snapshotNowWithin:1].idle);
    }];
    XCTAssertTrue(outWhenShown);
    XCTAssertEqualWithAccuracy(_time.now - firstSent, _settings.volumeInterval, 1e-9);
    XCTAssertEqual([self countSent:frame from:before], 1u);
}

// So a wait for a call's number ends, even for a call that sends nothing.
- (void)testACallThatChangesNothingStillPublishesItsNumber {
    [self startSystem];
    [self waitForIdle];
    QLMCallNumber call = [_system setDimmed:NO];
    QLMSnapshot *shown = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.lastCall >= call;
    }];
    XCTAssertEqual(shown.lastCall, call);
    XCTAssertFalse(shown.dimmed);

    [self stopSystem];
    call = [_system setMuted:YES forMonitorWithHardwareID:_left.hardwareID];
    shown = [self waitForSnapshot:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.lastCall >= call;
    }];
    XCTAssertEqual(shown.lastCall, call);
    XCTAssertFalse(shown.running);
    XCTAssertEqual(shown.mutedHardwareIDs.count, 0u);
}

@end
