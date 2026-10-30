#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMFakeBus.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the captures each test names, and docs/protocol.md, "Volume and
// the knob". Each test replays a capture's knob readings through System, on
// a virtual clock, at the capture's own times. System polls the adapter as
// it does in the app, so it sees each reading up to a poll late. The test
// compares the level System sends with GLM's at every rest point, a reading
// held 1.5 s or more.
//
// Until GLM's first knob burst, GLM keeps its own level, and qlm must keep
// its own too. After it, GLM's level is the knob's when it is the nearest
// step of the reading GLM last answered with a burst. Sometimes GLM's burst
// carries the level of the change before (sleep-wake-darkwake, 138.96 s),
// a lag qlm does not copy, so those rest points are only counted.
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

// GLM's level for a word: the nearest step, and the bottom for 00 00 08.
static double QLMLevelOfWord(uint32_t word) {
    double decibels = round(QLMVolumeDecibelsForWord(word) / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
    return fmax(QLMVolumeDecibelsMin, decibels);
}

// The knob's nearest step (docs/adapter-status.md, "The mapping").
static double QLMStepOfTenths(double tenths) {
    return fmin(0, fmax(QLMVolumeDecibelsMin, round(tenths / 5) * QLMVolumeDecibelsStep));
}

static BOOL QLMIsVolumeFrame(const QLMMessage *message) {
    return message->address == QLMAddressBroadcast && message->length == 4 && message->payload[0] == 0x1F;
}

@implementation QLMKnobGoldenTests

// Each pair's first reading, GLM's levels, and GLM's knob bursts: an
// `01 2B` within 150 ms of a change in the reading. GLM reads only the first
// poll of a pair.
- (void)read:(NSString *)scenario
    readings:(NSMutableArray<QLMKnobMoment *> *)readings
      levels:(NSMutableArray<QLMKnobMoment *> *)levels
      bursts:(NSMutableArray<QLMKnobMoment *> *)bursts {
    NSTimeInterval lastPoll = -1;
    NSTimeInterval lastChange = -1;
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (QLMIsVolumeFrame(&message)) {
            uint32_t word = (uint32_t)message.payload[1] << 16 | (uint32_t)message.payload[2] << 8 | message.payload[3];
            [levels addObject:QLMMoment(exchange.time, QLMLevelOfWord(word))];
        }
        if (message.address != QLMAddressAdapter) {
            continue;
        }
        if (message.payload[0] == 0x2B && exchange.time - lastChange <= 0.15) {
            [bursts addObject:QLMMoment(exchange.time, exchange.time)];
        }
        if (message.payload[0] != 0x08 || !exchange.answered) {
            continue;
        }
        BOOL first = exchange.time - lastPoll > 0.03;
        lastPoll = exchange.time;
        QLMMessage reply = exchange.reply;
        QLMAdapterStatus status;
        if (!first || QLMReplyAdapterStatus(&reply, &status) != QLMAdapterStatusOK || !status.hasKnobPosition) {
            continue;
        }
        if (readings.count > 0 && readings.lastObject.value != status.knobTenths) {
            lastChange = exchange.time;
        }
        [readings addObject:QLMMoment(exchange.time, status.knobTenths)];
    }
}

// The level System sent last.
static double QLMLastLevelSent(QLMFakeBus *bus) {
    for (NSData *record in bus.sentMessages.reverseObjectEnumerator) {
        const uint8_t *bytes = record.bytes;
        if (record.length == 5 && bytes[0] == QLMAddressBroadcast && bytes[1] == 0x1F) {
            return QLMLevelOfWord((uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 8 | bytes[4]);
        }
    }
    return NAN;
}

// Replays the capture from GLM's level `decibels`. Checks `compared` rest
// points, and counts `stale` where GLM lagged. Returns how many times
// System's level changed.
- (NSUInteger)replay:(NSString *)scenario from:(double)decibels compared:(NSUInteger)compared stale:(NSUInteger)stale {
    NSMutableArray<QLMKnobMoment *> *readings = [NSMutableArray array];
    NSMutableArray<QLMKnobMoment *> *levels = [NSMutableArray array];
    NSMutableArray<QLMKnobMoment *> *bursts = [NSMutableArray array];
    [self read:scenario readings:readings levels:levels bursts:bursts];

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
    [system setVolumeDecibels:decibels];
    [time settle];

    // System's level as each reading comes, before it polls for it.
    NSTimeInterval offset = time.now - readings.firstObject.time;
    NSMutableArray<NSNumber *> *sent = [NSMutableArray arrayWithObject:@(QLMLastLevelSent(bus))];
    NSUInteger changes = 0;
    for (NSUInteger i = 1; i < readings.count; i++) {
        QLMKnobMoment *reading = readings[i];
        [time advanceBy:reading.time + offset - time.now];
        [bus perform:^{
            bus.knobTenths = @(reading.value);
        }];
        [sent addObject:@(QLMLastLevelSent(bus))];
        changes += ![sent[i] isEqual:sent[i - 1]];
    }
    [system stop];
    [time settle];

    NSUInteger checked = 0;
    NSUInteger lagged = 0;
    for (NSUInteger first = 0, last = 0; first < readings.count; first = last + 1) {
        last = first;
        while (last + 1 < readings.count && readings[last + 1].value == readings[first].value) {
            last += 1;
        }
        NSTimeInterval end = readings[last].time;
        double glm = QLMValueAt(levels, end);
        if (end - readings[first].time < 1.5 || isnan(glm)) {
            continue;
        }
        double burst = QLMValueAt(bursts, end);
        if (!isnan(burst) && glm != QLMStepOfTenths(QLMValueAt(readings, burst))) {
            lagged += 1;
            continue;
        }
        checked += 1;
        XCTAssertEqual(sent[last].doubleValue, glm, @"%@, %.3f s, knob at %.0f", scenario, end, readings[last].value);
    }
    XCTAssertEqual(checked, compared, @"%@", scenario);
    XCTAssertEqual(lagged, stale, @"%@", scenario);
    return changes;
}

// The darkwake drift: over 600 s the reading creeps 7 dB, mostly a tenth at
// a time. GLM follows it in 2.5 s spells, 37 times. So does qlm, and at
// every rest point but GLM's 5 lags, its level is GLM's.
- (void)testTheKnobsSlowDriftIsGLMsInSleepWakeDarkwake {
    NSUInteger changes = [self replay:@"sleep-wake-darkwake" from:-73.0 compared:96 stale:5];
    XCTAssertGreaterThan(changes, 30u);
}

// knob-sweep: GLM opens at -56.5 dB with the knob at -77.5, and keeps its
// level until the knob turns at 18.95 s. Then four sweeps of the whole range.
- (void)testTheKnobsTurnsAreGLMsInKnobSweep {
    [self replay:@"knob-sweep" from:-56.5 compared:6 stale:0];
}

// startup-idle: the knob rests at the bottom until a turn at 38.48 s.
// unplug-proxy-hang: the knob wobbles by up to 0.8 dB from 15.4 to 18.0 s,
// and GLM keeps its level. When the adapter comes back, at 106.2 s, the knob
// reads 55 dB lower, and GLM follows it.
- (void)testTheKnobRestsAtGLMsLevel {
    [self replay:@"startup-idle" from:-56.5 compared:2 stale:0];
    [self replay:@"startup-idle-mic" from:-56.5 compared:1 stale:0];
    [self replay:@"unplug-proxy-hang" from:-56.5 compared:7 stale:0];
}

// sleep-wake-no-sleep: the reading wanders 10 tenths over 130 s, never more
// than a whole dB, and GLM keeps -64.5 dB. So does qlm.
- (void)testAWanderOfADecibelMovesNothingInSleepWakeNoSleep {
    XCTAssertEqual([self replay:@"sleep-wake-no-sleep" from:-64.5 compared:25 stale:0], 0u);
}

// standby-wake: the knob was just plugged in, and its reading settles near
// the bottom.
- (void)testAJustPluggedKnobIsGLMsInStandbyWake {
    [self replay:@"standby-wake" from:QLMVolumeDecibelsMin compared:6 stale:0];
}

@end
