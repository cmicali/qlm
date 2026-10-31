#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMFakeBus.h"
#import "QLMKnob.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the captures each test names, and docs/protocol.md, "Volume and
// the knob". Each test replays a capture's knob readings through System, on
// a virtual clock, at the capture's own times, from GLM's first level.
// System polls the adapter as it does in the app, so it sees each reading
// up to a poll late. The test compares the level System sends with GLM's at
// every rest point, a reading held 1.5 s or more.
//
// Until GLM's first knob burst, GLM keeps its own level, and qlm must keep
// its own too. After it, GLM's level is the knob's when it is the level of
// the reading GLM last answered with a burst. Sometimes GLM's burst carries
// the level of the change before (sleep-wake-darkwake, 138.96 s), a lag qlm
// does not copy, so those rest points are only counted.
@interface QLMKnobGoldenTests : XCTestCase
@end

// A moment in a capture: a knob reading in tenths, or a level in dB.
@interface QLMKnobMoment : NSObject
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) double value;
@end

@implementation QLMKnobMoment
@end

static QLMKnobMoment *QLMMoment(NSTimeInterval time, double value) {
    QLMKnobMoment *moment = [[QLMKnobMoment alloc] init];
    moment.time = time;
    moment.value = value;
    return moment;
}

// The value of the last moment at or before `time`, or NAN.
static double QLMValueAt(NSArray<QLMKnobMoment *> *moments, NSTimeInterval time) {
    double value = NAN;
    for (QLMKnobMoment *moment in moments) {
        if (moment.time > time) {
            break;
        }
        value = moment.value;
    }
    return value;
}

// The level of a volume frame, as QLMAdapterRecord gives it, at the nearest
// step, or NAN for any other record. 00 00 08 is the bottom.
static double QLMLevelOfRecord(NSData *record) {
    const uint8_t *bytes = record.bytes;
    if (record.length != 5 || bytes[0] != QLMAddressBroadcast || bytes[1] != 0x1F) {
        return NAN;
    }
    uint32_t word = (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 8 | bytes[4];
    double decibels = round(QLMVolumeDecibelsForWord(word) / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
    return fmax(QLMVolumeDecibelsMin, decibels);
}

// GLM's level for a knob reading (testTheKnobNamesTheSteps).
static double QLMLevelOfTenths(double tenths) {
    QLMMessage volume = QLMCommandVolume(tenths / 10.0, 0);
    return QLMLevelOfRecord(QLMAdapterRecord(&volume));
}

static double QLMLastLevelSent(NSArray<NSData *> *sent) {
    for (NSData *record in sent.reverseObjectEnumerator) {
        double level = QLMLevelOfRecord(record);
        if (!isnan(level)) {
            return level;
        }
    }
    return NAN;
}

// The knob's position in an answered 01 08, the first of its pair, the only
// one GLM reads, or NO. `lastPoll` is the time of the poll before.
static BOOL QLMFirstKnobReading(QLMCaptureExchange *exchange, NSTimeInterval *lastPoll, NSInteger *tenths) {
    QLMMessage message = exchange.message;
    if (message.address != QLMAddressAdapter || message.payload[0] != 0x08 || !exchange.answered) {
        return NO;
    }
    BOOL first = exchange.time - *lastPoll > 0.03;
    *lastPoll = exchange.time;
    QLMMessage reply = exchange.reply;
    QLMAdapterStatus status;
    if (!first || QLMReplyAdapterStatus(&reply, &status) != QLMAdapterStatusOK || !status.hasKnobPosition) {
        return NO;
    }
    *tenths = status.knobTenths;
    return YES;
}

// An 01 2B within 150 ms of the change in the reading at `changed`, as each
// of GLM's knob bursts has. `changed` is below 0 before any change.
static BOOL QLMIsKnobBurst(QLMCaptureExchange *exchange, NSTimeInterval changed) {
    QLMMessage message = exchange.message;
    return message.address == QLMAddressAdapter && message.payload[0] == 0x2B && changed >= 0 && exchange.time - changed <= 0.15;
}

// The level of a volume frame, as QLMLevelOfRecord gives it, or NAN.
static double QLMLevelOfMessage(QLMMessage message) {
    if (message.address != QLMAddressBroadcast || message.payload[0] != 0x1F) {
        return NAN;
    }
    return QLMLevelOfRecord(QLMAdapterRecord(&message));
}

@implementation QLMKnobGoldenTests

// Replays the capture's knob readings. Checks `compared` rest points, and
// counts `stale` where GLM lagged. Returns how many times System's level
// changed.
- (NSUInteger)replay:(NSString *)scenario compared:(NSUInteger)compared stale:(NSUInteger)stale {
    // The first reading of each pair, the only one GLM reads; GLM's levels;
    // and GLM's knob bursts, each an `01 2B` within 150 ms of a change in the
    // reading, as the level of the reading it answered.
    NSMutableArray<QLMKnobMoment *> *readings = [NSMutableArray array];
    NSMutableArray<QLMKnobMoment *> *levels = [NSMutableArray array];
    NSMutableArray<QLMKnobMoment *> *bursts = [NSMutableArray array];
    NSTimeInterval lastPoll = -1;
    NSTimeInterval lastChange = -1;
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        double level = QLMLevelOfMessage(exchange.message);
        if (!isnan(level)) {
            [levels addObject:QLMMoment(exchange.time, level)];
        }
        if (QLMIsKnobBurst(exchange, lastChange)) {
            [bursts addObject:QLMMoment(exchange.time, QLMLevelOfTenths(readings.lastObject.value))];
        }
        NSInteger tenths = 0;
        if (!QLMFirstKnobReading(exchange, &lastPoll, &tenths)) {
            continue;
        }
        if (readings.count > 0 && readings.lastObject.value != tenths) {
            lastChange = exchange.time;
        }
        [readings addObject:QLMMoment(exchange.time, tenths)];
    }

    // Each rest point, as the index of its last reading.
    NSMutableIndexSet *rests = [NSMutableIndexSet indexSet];
    for (NSUInteger first = 0, last = 0; first < readings.count; first = last + 1) {
        last = first;
        while (last + 1 < readings.count && readings[last + 1].value == readings[first].value) {
            last += 1;
        }
        if (readings[last].time - readings[first].time >= 1.5 && !isnan(QLMValueAt(levels, readings[last].time))) {
            [rests addIndex:last];
        }
    }

    QLMVirtualClock *time = [[QLMVirtualClock alloc] init];
    QLMFakeMonitor *monitor = [[QLMFakeMonitor alloc] initWithHardwareID:QLMBytes((const uint8_t[]){0x12, 0x2F, 0xA0}, 3)
                                                             serialNumber:@"8330AP21000000"
                                                               systemInfo:@"c-2;model-8330A"
                                                              deviceClass:QLMTelemetryClassTwoWay];
    QLMFakeBus *bus = [[QLMFakeBus alloc] initWithMonitors:@[monitor]];
    bus.knobTenths = @(readings.firstObject.value);
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = time;
    settings.ceilingDecibels = 0;
    settings.cycleInterval = 1000;  // no cycle restates the level
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    [system start];
    [time settle];
    [system setVolumeDecibels:levels.firstObject.value];
    [time settle];

    NSTimeInterval offset = time.now - readings.firstObject.time;
    NSUInteger checked = 0;
    NSUInteger lagged = 0;
    for (NSUInteger i = 1; i < readings.count; i++) {
        QLMKnobMoment *reading = readings[i];
        [time advanceBy:reading.time + offset - time.now];
        [bus perform:^{
            bus.knobTenths = @(reading.value);
        }];
        if (![rests containsIndex:i]) {
            continue;
        }
        double glm = QLMValueAt(levels, reading.time);
        double answered = QLMValueAt(bursts, reading.time);
        if (!isnan(answered) && glm != answered) {
            lagged += 1;
            continue;
        }
        checked += 1;
        XCTAssertEqual(QLMLastLevelSent(bus.sentMessages), glm, @"%@, %.3f s, knob at %.0f", scenario, reading.time, reading.value);
    }
    XCTAssertEqual(checked, compared, @"%@", scenario);
    XCTAssertEqual(lagged, stale, @"%@", scenario);

    NSArray<NSData *> *sent = bus.sentMessages;
    [system stop];
    [time settle];
    NSUInteger changes = 0;
    double previous = NAN;
    for (NSData *record in sent) {
        double level = QLMLevelOfRecord(record);
        if (isnan(level)) {
            continue;
        }
        changes += !isnan(previous) && level != previous;
        previous = level;
    }
    return changes;
}

// The darkwake drift: over 600 s the reading creeps 7 dB, mostly a tenth at
// a time. GLM follows it in 2.5 s spells, 37 times. So does qlm, and at
// every rest point but GLM's 5 lags, its level is GLM's.
- (void)testTheKnobsSlowDriftIsGLMsInSleepWakeDarkwake {
    XCTAssertGreaterThan([self replay:@"sleep-wake-darkwake" compared:96 stale:5], 30u);
}

// knob-sweep: GLM opens at -56.5 dB with the knob at -77.5, and keeps its
// level until the knob turns at 18.95 s. Then four sweeps of the whole range.
- (void)testTheKnobsTurnsAreGLMsInKnobSweep {
    [self replay:@"knob-sweep" compared:6 stale:0];
}

// startup-idle: the knob rests at the bottom until a turn at 38.59 s.
// unplug-proxy-hang: the knob wobbles by up to 0.8 dB from 15.4 to 18.0 s,
// and GLM keeps its level. When the adapter comes back, at 106.2 s, the knob
// reads 55 dB lower, and GLM follows it.
- (void)testTheKnobRestsAtGLMsLevel {
    [self replay:@"startup-idle" compared:2 stale:0];
    [self replay:@"startup-idle-mic" compared:1 stale:0];
    [self replay:@"unplug-proxy-hang" compared:7 stale:0];
}

// sleep-wake-no-sleep: the reading wanders 10 tenths over 130 s, never more
// than a whole dB, and GLM keeps -64.5 dB. So does qlm.
- (void)testAWanderOfADecibelMovesNothingInSleepWakeNoSleep {
    XCTAssertEqual([self replay:@"sleep-wake-no-sleep" compared:25 stale:0], 0u);
}

// standby-wake: the knob was just plugged in, and its reading settles near
// the bottom.
- (void)testAJustPluggedKnobIsGLMsInStandbyWake {
    [self replay:@"standby-wake" compared:6 stale:0];
}

// GLM's knob bursts in `scenario`: the level frames, then 01 2B, within
// 150 ms of a change in the reading. Each carries the level of the reading
// it answers, or the level of the reading GLM answered before it, or rested
// at. Counts the second kind in `lagged`.
- (NSUInteger)burstsIn:(NSString *)scenario lagged:(NSUInteger *)lagged {
    NSUInteger bursts = 0;
    NSTimeInterval lastPoll = -1;
    NSTimeInterval changed = -1;
    NSInteger tenths = 0;
    double followed = NAN;
    double level = NAN;
    BOOL afterLevel = NO;
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        double sent = QLMLevelOfMessage(exchange.message);
        if (!isnan(sent)) {
            level = sent;
            afterLevel = YES;
            continue;
        }
        NSInteger reading = 0;
        if (QLMFirstKnobReading(exchange, &lastPoll, &reading)) {
            if (isnan(followed)) {
                followed = QLMLevelOfTenths(reading);
            } else if (reading != tenths) {
                changed = exchange.time;
            }
            tenths = reading;
        } else if (afterLevel && QLMIsKnobBurst(exchange, changed)) {
            double answered = QLMLevelOfTenths(tenths);
            if (level != answered) {
                XCTAssertEqual(level, followed, @"%@, %.3f s", scenario, exchange.time);
                *lagged += 1;
            }
            followed = answered;
            bursts += 1;
        }
        afterLevel = NO;
    }
    return bursts;
}

// Across the seven captures with the knob, no burst carries a level but the
// reading's or the one GLM answered before it. That lag is GLM's, and comes
// most in a fast turn: 52 of knob-sweep's 168 bursts.
- (void)testEachBurstCarriesTheReadingsLevelOrTheOneBefore {
    NSUInteger lagged = 0;
    NSUInteger bursts = [self burstsIn:@"knob-sweep" lagged:&lagged];
    XCTAssertEqual(bursts, 168u);
    XCTAssertEqual(lagged, 52u);
    for (NSString *scenario in @[@"sleep-wake-darkwake", @"sleep-wake-no-sleep", @"startup-idle", @"startup-idle-mic",
                                 @"standby-wake", @"unplug-proxy-hang"]) {
        bursts += [self burstsIn:scenario lagged:&lagged];
    }
    XCTAssertEqual(bursts, 308u);
    XCTAssertEqual(lagged, 72u);
}

// standby-wake starts with the knob just plugged in, reading -1001. GLM
// bursts for a change of one tenth at 0.983 s, not for the changes at 1.335,
// 1.548, and 1.657 s, and again at 1.766 s, 20 tenths on. That is GLM's rule
// if the plug's first reading started a spell 1.21 to 1.55 s before the
// capture: it is 13 tenths from -988, the last reading GLM followed before
// the knob came out in volume-sweep, at 25.44 s.
- (void)testAKnobJustPluggedInIsTheTailOfASpell {
    NSMutableArray<NSNumber *> *changes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *readings = [NSMutableArray array];
    NSMutableSet<NSNumber *> *answered = [NSMutableSet set];
    NSTimeInterval lastPoll = -1;
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"standby-wake", NULL).exchanges) {
        if (exchange.time > 1.8) {
            break;
        }
        NSInteger reading = 0;
        if (QLMFirstKnobReading(exchange, &lastPoll, &reading)) {
            if (readings.count == 0 || readings.lastObject.integerValue != reading) {
                [changes addObject:@(exchange.time)];
                [readings addObject:@(reading)];
            }
        } else if (changes.count > 1 && QLMIsKnobBurst(exchange, changes.lastObject.doubleValue)) {
            [answered addObject:changes.lastObject];
        }
    }
    XCTAssertEqualObjects(readings, (@[@-1001, @-1002, @-1001, @-1000, @-993, @-982]));
    XCTAssertEqual(answered.count, 2u);

    for (NSNumber *plug in @[@-1.0, @-1.22, @-1.54, @-1.7]) {
        QLMKnob *knob = [[QLMKnob alloc] init];
        [knob volumeForReading:-988 atTime:-60 volume:@(-50)];
        [knob volumeForReading:-1001 atTime:plug.doubleValue volume:@(-50)];
        NSMutableSet<NSNumber *> *followed = [NSMutableSet set];
        for (NSUInteger i = 1; i < readings.count; i++) {
            if ([knob volumeForReading:readings[i].integerValue atTime:changes[i].doubleValue volume:@(-50)] != nil) {
                [followed addObject:changes[i]];
            }
        }
        BOOL inSpell = plug.doubleValue < -1.2 && plug.doubleValue > -1.56;
        XCTAssertEqual([followed isEqualToSet:answered], inSpell, @"a plug at %@ s", plug);
    }
}

@end
