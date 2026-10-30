#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMFakeBus.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the captures each test names, and their notes.md. Each test runs
// one action through System over a fake bus of six monitors, and checks the
// frames System sends against the frames GLM sent for it, byte for byte. The
// session IDs differ, so both sides number them in the order each first
// appears. The adapter's 01 08 polls run on their own timer, so both sides
// leave them out. System runs on a virtual clock, so each gap between sends
// is the one System schedules, whatever the host's load.
@interface QLMSystemGoldenTests : XCTestCase
@end

// An adapter that notes when each message reaches it, then passes it on.
@interface QLMClockedAdapter : NSObject <QLMAdapter>
- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter clock:(id<QLMClock>)clock;
@property (nonatomic, readonly) NSArray<NSNumber *> *sendTimes;  // on the clock, in seconds
@end

@implementation QLMClockedAdapter {
    id<QLMAdapter> _adapter;
    id<QLMClock> _clock;
    NSMutableArray<NSNumber *> *_times;
}

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter clock:(id<QLMClock>)clock {
    self = [super init];
    if (self) {
        _adapter = adapter;
        _clock = clock;
        _times = [NSMutableArray array];
    }
    return self;
}

- (NSString *)deviceDescription {
    return _adapter.deviceDescription;
}

- (NSArray<NSNumber *> *)sendTimes {
    @synchronized(self) {
        return [_times copy];
    }
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    [_adapter startOnQueue:queue];
}

- (void)stop {
    [_adapter stop];
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    @synchronized(self) {
        [_times addObject:@(_clock.now)];
    }
    [_adapter sendMessage:message replyHandler:handler];
}

@end

@implementation QLMSystemGoldenTests {
    QLMFakeBus *_bus;
    QLMVirtualClock *_time;
    QLMClockedAdapter *_clocked;
    QLMSystemSettings *_settings;
    QLMSystem *_system;
}

- (void)setUp {
    [super setUp];
    NSMutableArray<QLMFakeMonitor *> *monitors = [NSMutableArray array];
    for (uint8_t i = 0; i < 6; i++) {
        const uint8_t hardwareID[3] = {0x12, 0x2F, (uint8_t)(0xA0 + i)};
        NSString *serial = [NSString stringWithFormat:@"8330AP2100000%u", i];
        [monitors addObject:[[QLMFakeMonitor alloc] initWithHardwareID:QLMBytes(hardwareID, 3) serialNumber:serial
                                                            systemInfo:@"c-2;model-8330A" deviceClass:QLMTelemetryClassTwoWay]];
    }
    _time = [[QLMVirtualClock alloc] init];
    _bus = [[QLMFakeBus alloc] initWithMonitors:monitors];
    _bus.clock = _time;
    _clocked = [[QLMClockedAdapter alloc] initWithAdapter:_bus clock:_time];
    _settings = [[QLMSystemSettings alloc] init];
    _settings.clock = _time;
    // No cycle may fire inside an action.
    _settings.cycleInterval = 1000;
    _settings.ceilingDecibels = 0;
    _settings.adapterPollInterval = 0;
}

- (void)tearDown {
    [_system stop];
    [_time settle];
    [super tearDown];
}

// Starts System, finds all six monitors, and sets GLM's level in mute-dim.
- (NSArray<QLMMonitorState *> *)startSystem {
    return [self startSystemAt:@(-56.5)];
}

// The same, at `decibels`, or with no volume set when it is nil.
- (NSArray<QLMMonitorState *> *)startSystemAt:(nullable NSNumber *)decibels {
    _system = [[QLMSystem alloc] initWithAdapter:_clocked settings:_settings];
    [_system start];
    [_time settle];
    QLMSnapshot *snapshot = _system.snapshot;
    XCTAssertTrue(snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle);
    if (decibels != nil) {
        [_system setVolumeDecibels:decibels.doubleValue];
        [_time settle];
        QLMMessage volume = QLMCommandVolume(decibels.doubleValue, _settings.ceilingDecibels);
        XCTAssertEqualObjects(_bus.sentMessages.lastObject, QLMAdapterRecord(&volume));
    }
    return _system.snapshot.monitors;
}

static BOOL QLMIsAdapterPoll(NSData *record) {
    QLMMessage poll = QLMCommandPoll(QLMAddressAdapter);
    return [record isEqualToData:QLMAdapterRecord(&poll)];
}

// What System sent from `start` on, less the adapter's polls.
- (NSArray<NSData *> *)sentFrom:(NSUInteger)start {
    NSArray<NSData *> *sent = _bus.sentMessages;
    NSMutableArray<NSData *> *found = [NSMutableArray array];
    for (NSUInteger i = start; i < sent.count; i++) {
        if (!QLMIsAdapterPoll(sent[i])) {
            [found addObject:sent[i]];
        }
    }
    return found;
}

// `count` frames of captures/<scenario>, from the one at `time` to the half
// millisecond, less the adapter's polls.
- (NSArray<QLMCaptureExchange *> *)frames:(NSUInteger)count of:(NSString *)scenario from:(NSTimeInterval)time {
    NSMutableArray<QLMCaptureExchange *> *run = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        if (run.count == 0 && fabs(exchange.time - time) >= 0.0005) {
            continue;
        }
        QLMMessage message = exchange.message;
        if (QLMIsAdapterPoll(QLMAdapterRecord(&message))) {
            continue;
        }
        [run addObject:exchange];
        if (run.count == count) {
            return run;
        }
    }
    XCTFail(@"%@ has %lu of %lu frames from %.6f s", scenario, (unsigned long)run.count, (unsigned long)count, time);
    return @[];
}

// Each session ID becomes 02 for the first to appear, 03 for the next, and
// so on, so the capture's sessions and System's compare.
static NSArray<NSData *> *QLMRenumberSessions(NSArray<NSData *> *frames) {
    NSMutableDictionary<NSNumber *, NSNumber *> *order = [NSMutableDictionary dictionary];
    NSMutableArray<NSData *> *renumbered = [NSMutableArray arrayWithCapacity:frames.count];
    for (NSData *frame in frames) {
        NSMutableData *copy = [frame mutableCopy];
        uint8_t *bytes = copy.mutableBytes;
        if (QLMAddressIsLeasable(bytes[0])) {
            NSNumber *session = order[@(bytes[0])];
            if (session == nil) {
                session = @(QLMAddressSessionFirst + order.count);
                order[@(bytes[0])] = session;
            }
            bytes[0] = session.unsignedCharValue;
        }
        [renumbered addObject:copy];
    }
    return renumbered;
}

// Checks what System sent from `start` on against the captured frames, and
// returns them.
- (NSArray<QLMCaptureExchange *> *)assertSentFrom:(NSUInteger)start
                                         isCapture:(NSString *)scenario
                                              from:(NSTimeInterval)time
                                             count:(NSUInteger)count {
    NSArray<QLMCaptureExchange *> *captured = [self frames:count of:scenario from:time];
    [self assertSentFrom:start are:captured];
    return captured;
}

// Checks what System sent from `start` on against `captured`, in order.
- (void)assertSentFrom:(NSUInteger)start are:(NSArray<QLMCaptureExchange *> *)captured {
    NSMutableArray<NSData *> *expected = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in captured) {
        QLMMessage message = exchange.message;
        [expected addObject:QLMAdapterRecord(&message)];
    }
    // Every hold and every hop the action starts has run.
    [_time advanceBy:1];
    XCTAssertEqualObjects(QLMRenumberSessions([self sentFrom:start]), QLMRenumberSessions(expected));
}

// The gaps between System's sends from `start` on are exactly `scheduled`,
// on its clock.
- (void)assertGapsFrom:(NSUInteger)start are:(NSArray<NSNumber *> *)scheduled {
    NSArray<NSNumber *> *times = _clocked.sendTimes;
    XCTAssertEqual(times.count, start + scheduled.count + 1);
    for (NSUInteger i = 0; i < scheduled.count && start + i + 1 < times.count; i++) {
        NSTimeInterval qlm = times[start + i + 1].doubleValue - times[start + i].doubleValue;
        XCTAssertEqualWithAccuracy(qlm, scheduled[i].doubleValue, 1e-9, @"gap %lu", (unsigned long)i);
    }
}

// GLM's gaps between the captured frames are `scheduled`, within `slack`.
// This checks the capture against the spacing System copies.
- (void)assertGLMGaps:(NSArray<QLMCaptureExchange *> *)captured are:(NSArray<NSNumber *> *)scheduled slack:(NSTimeInterval)slack {
    XCTAssertEqual(captured.count, scheduled.count + 1);
    for (NSUInteger i = 0; i < scheduled.count && i + 1 < captured.count; i++) {
        NSTimeInterval glm = captured[i + 1].time - captured[i].time;
        XCTAssertEqualWithAccuracy(glm, scheduled[i].doubleValue, slack, @"GLM gap %lu", (unsigned long)i);
    }
}

#pragma mark - Power

// Standby, standby-wake, 34.86 s: broadcast `3A 03 02` twice, then
// `3A 03 00` twice, 21.6 to 22.0 ms apart.
- (void)testSleepIsGLMs {
    [self startSystem];
    NSUInteger before = _bus.sentMessages.count;
    NSUInteger clocked = _clocked.sendTimes.count;
    [_system sleep];
    NSArray<QLMCaptureExchange *> *captured = [self assertSentFrom:before isCapture:@"standby-wake" from:34.855835 count:4];
    NSArray<NSNumber *> *scheduled = @[@0.022, @0.022, @0.022];
    [self assertGapsFrom:clocked are:scheduled];
    [self assertGLMGaps:captured are:scheduled slack:0.001];
}

// Wake, startup-idle, 7.33 s: broadcast `3A 03 7F` then `3A 03 01`, back to
// back, three times, 0.20 to 0.21 s apart. Then standby-wake, 47.24 s: the
// level, 0.235 s after the last pair, then broadcast `2D 00` and `3D 00 00`.
// GLM's level there is the knob's bottom stop, so System's is set to it.
- (void)testWakeIsGLMs {
    [self startSystemAt:@(QLMVolumeDecibelsMin)];
    NSUInteger before = _bus.sentMessages.count;
    NSUInteger clocked = _clocked.sendTimes.count;
    [_system wake];

    NSArray<QLMCaptureExchange *> *pairs = [self frames:6 of:@"startup-idle" from:7.331654];
    NSArray<QLMCaptureExchange *> *level = [self frames:3 of:@"standby-wake" from:47.243052];
    [self assertSentFrom:before are:[pairs arrayByAddingObjectsFromArray:level]];
    // Each pair back to back, 0.2 s between pairs, the level 0.235 s after
    // the last, and the broadcast pair right after it.
    NSArray<NSNumber *> *pairGaps = @[@0, @0.2, @0, @0.2, @0];
    [self assertGapsFrom:clocked are:[pairGaps arrayByAddingObjectsFromArray:@[@0.235, @0, @0]]];
    // GLM's pairs are startup-idle's, and its level's delay standby-wake's.
    // 47.0087 s picks its last 3A 03 01, at 47.008437 s, and not the 3A 03 7F
    // 0.27 ms before it. GLM's broadcast pair came 23 ms after its level,
    // which System does not copy.
    [self assertGLMGaps:pairs are:pairGaps slack:0.01];
    [self assertGLMGaps:[self frames:2 of:@"standby-wake" from:47.0087] are:@[@0.235] slack:0.001];
}

// A wake with no volume set ends with the knob's level. The fake bus's knob
// sits at its bottom stop, as standby-wake's did, so the frames are GLM's.
- (void)testWakeWithNoVolumeEndsWithTheKnobsLevel {
    [self startSystemAt:nil];
    NSUInteger before = _bus.sentMessages.count;
    [_system wake];
    NSArray<QLMCaptureExchange *> *pairs = [self frames:6 of:@"startup-idle" from:7.331654];
    NSArray<QLMCaptureExchange *> *level = [self frames:3 of:@"standby-wake" from:47.243052];
    [self assertSentFrom:before are:[pairs arrayByAddingObjectsFromArray:level]];
}

#pragma mark - The knob

// A knob turn, standby-wake, 0.99 s: the level three times, `2B 00` to the
// adapter at 01, two rounds of 2B to every monitor, then the level again.
// The knob turns to its bottom, so the level is 00 00 08.
- (void)testAKnobTurnIsGLMs {
    _settings.adapterPollInterval = 0.02;
    [_bus perform:^{
        self->_bus.knobTenths = @(-900);
    }];
    [self startSystem];

    NSUInteger before = _bus.sentMessages.count;
    [_bus perform:^{
        self->_bus.knobTenths = @(-1002);
    }];
    [self assertSentFrom:before isCapture:@"standby-wake" from:0.988149 count:17];
    XCTAssertEqualObjects(_system.snapshot.volumeDecibels, @(QLMVolumeDecibelsMin));
}

#pragma mark - Mute

// Mute one monitor, mute-dim, 19.19 s, and unmute it, 22.74 s: two rounds of
// 2B to every monitor, 03 to the muted one and 04 to the rest. GLM muted
// 0B, last in its round.
- (void)testMutingOneMonitorIsGLMs {
    NSArray<QLMMonitorState *> *monitors = [self startSystem];
    NSData *last = monitors.lastObject.hardwareID;

    NSUInteger before = _bus.sentMessages.count;
    [_system setMuted:YES forMonitorWithHardwareID:last];
    [self assertSentFrom:before isCapture:@"mute-dim" from:19.186196 count:12];

    before = _bus.sentMessages.count;
    [_system setMuted:NO forMonitorWithHardwareID:last];
    [self assertSentFrom:before isCapture:@"mute-dim" from:22.739597 count:12];
}

// Mute all, mute-dim, 46.19 s, and unmute all, 48.60 s: the level, then
// `2B 01` or `2B 00` to the adapter at 01, then two rounds of 2B to every
// monitor.
- (void)testMutingAllIsGLMs {
    [self startSystem];

    NSUInteger before = _bus.sentMessages.count;
    [_system setAllMuted:YES];
    [self assertSentFrom:before isCapture:@"mute-dim" from:46.188342 count:14];
    XCTAssertTrue(_system.snapshot.allMuted);

    before = _bus.sentMessages.count;
    [_system setAllMuted:NO];
    [self assertSentFrom:before isCapture:@"mute-dim" from:48.595249 count:14];
    XCTAssertFalse(_system.snapshot.allMuted);
}

#pragma mark - Dim

// Dim, mute-dim, 51.24 s on and 54.77 s off: the level twice, one round of
// 2B to every monitor, then broadcast `2D 00` and `3D 00 00`.
- (void)testDimIsGLMs {
    [self startSystem];

    NSUInteger before = _bus.sentMessages.count;
    [_system setDimmed:YES];
    [self assertSentFrom:before isCapture:@"mute-dim" from:51.240592 count:10];
    XCTAssertTrue(_system.snapshot.dimmed);

    before = _bus.sentMessages.count;
    [_system setDimmed:NO];
    [self assertSentFrom:before isCapture:@"mute-dim" from:54.774959 count:10];
    XCTAssertFalse(_system.snapshot.dimmed);
}

@end
