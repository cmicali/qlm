#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMKnob.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the captures each test names, and docs/adapter-status.md, which
// decodes the knob's reading in the adapter's reply to 01 08 and says what
// GLM does with it. The capture tests feed QLMKnob every reading in a
// capture, at the capture's own times, starting from GLM's own level, and
// compare the volume it sets with the level GLM sent.
@interface QLMKnobTests : XCTestCase
@end

// One reading of the knob in a capture.
@interface QLMKnobReading : NSObject
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) NSInteger tenths;
@property (nonatomic) double volume;     // qlm's after this reading
@property (nonatomic) uint32_t glmWord;  // GLM's last level, 0 before its first
@end

@implementation QLMKnobReading
@end

@implementation QLMKnobTests

#pragma mark - The rule

- (void)testTheFirstReadingIsWhereTheKnobRests {
    QLMKnob *knob = [[QLMKnob alloc] init];
    XCTAssertNil([knob volumeForReading:-300 atTime:0 volume:@(-56.5)]);
    XCTAssertNil([knob volumeForReading:-300 atTime:0.1 volume:@(-56.5)]);
    // A reconnect keeps the rest point, so a turn while away moves the volume.
    XCTAssertEqualObjects([knob volumeForReading:-739 atTime:88 volume:@(-56.5)], @(-74.0));
    [knob reset];
    XCTAssertNil([knob volumeForReading:-200 atTime:89 volume:@(-74.0)]);
}

- (void)testATurnSetsTheNearestStep {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-775 atTime:0 volume:@(-56.5)];
    XCTAssertNil([knob volumeForReading:-766 atTime:0.1 volume:@(-56.5)]);  // 0.9 dB is no turn
    XCTAssertEqualObjects([knob volumeForReading:-732 atTime:0.2 volume:@(-56.5)], @(-73.0));
    XCTAssertEqualObjects([knob volumeForReading:-123 atTime:0.3 volume:@(-73.0)], @(-12.5));
    XCTAssertEqualObjects([knob volumeForReading:5 atTime:0.4 volume:@(-12.5)], @(0.0));
    XCTAssertEqualObjects([knob volumeForReading:-1004 atTime:0.5 volume:@(0.0)], @(QLMVolumeDecibelsMin));
    XCTAssertNil([knob volumeForReading:-999 atTime:0.6 volume:@(QLMVolumeDecibelsMin)]);
}

- (void)testWithNoVolumeTheKnobSetsNone {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-775 atTime:0 volume:nil];
    XCTAssertNil([knob volumeForReading:-300 atTime:0.1 volume:nil]);
}

// For 2 s after a turn, a reading 4 tenths from the volume moves it, and one
// at 3 tenths, just past the edge of the volume's step, does not.
- (void)testAfterATurnTheVolumeFollowsEveryStep {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-500 atTime:0 volume:@(-30)];
    XCTAssertEqualObjects([knob volumeForReading:-400 atTime:0.1 volume:@(-30)], @(-40.0));
    XCTAssertNil([knob volumeForReading:-403 atTime:0.2 volume:@(-40.0)]);
    XCTAssertEqualObjects([knob volumeForReading:-404 atTime:0.3 volume:@(-40.0)], @(-40.5));
    XCTAssertEqualObjects([knob volumeForReading:-409 atTime:2.0 volume:@(-40.5)], @(-41.0));
    XCTAssertNil([knob volumeForReading:-415 atTime:2.4 volume:@(-41.0)]);
}

// At rest the reading wanders a tenth or two. A wander slower than a whole
// dB in half a second is no turn, so it never moves qlm's own volume.
- (void)testJitterAndWanderAtRestMoveNothing {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-640 atTime:0 volume:@(-30)];
    NSInteger tenths = -640;
    for (int i = 1; i <= 40; i++) {
        tenths += (i % 4 == 0) ? -1 : 1;  // up 20 tenths in 24 s
        XCTAssertNil([knob volumeForReading:tenths atTime:i * 0.6 volume:@(-30)], @"%ld", (long)tenths);
    }
}

// Once the volume is the knob's, a wander of a whole dB moves it, and less
// does not. A volume set elsewhere is not the knob's.
- (void)testAVolumeThatIsTheKnobsFollowsAWholeDecibel {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-300 atTime:0 volume:@(-30)];
    XCTAssertEqualObjects([knob volumeForReading:-640 atTime:0.1 volume:@(-30)], @(-64.0));
    XCTAssertNil([knob volumeForReading:-649 atTime:10 volume:@(-64.0)]);
    XCTAssertEqualObjects([knob volumeForReading:-650 atTime:11 volume:@(-64.0)], @(-65.0));
    XCTAssertNil([knob volumeForReading:-659 atTime:12 volume:@(-50.0)]);
}

#pragma mark - The captures

// Every knob reading in captures/<scenario>, fed to a knob from `volume`,
// GLM's own level there.
- (NSArray<QLMKnobReading *> *)run:(NSString *)scenario from:(double)volume {
    QLMKnob *knob = [[QLMKnob alloc] init];
    NSNumber *current = @(volume);
    uint32_t glmWord = 0;
    NSMutableArray<QLMKnobReading *> *readings = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (message.address == QLMAddressBroadcast && message.length == 4 && message.payload[0] == 0x1F) {
            glmWord = (uint32_t)message.payload[1] << 16 | (uint32_t)message.payload[2] << 8 | message.payload[3];
        }
        if (message.address != QLMAddressAdapter || message.payload[0] != 0x08 || !exchange.answered) {
            continue;
        }
        QLMMessage reply = exchange.reply;
        QLMAdapterStatus status;
        if (QLMReplyAdapterStatus(&reply, &status) != QLMAdapterStatusOK || !status.hasKnobPosition) {
            continue;
        }
        NSNumber *set = [knob volumeForReading:status.knobTenths atTime:exchange.time volume:current];
        if (set != nil) {
            current = set;
        }
        QLMKnobReading *reading = [[QLMKnobReading alloc] init];
        reading.time = exchange.time;
        reading.tenths = status.knobTenths;
        reading.volume = current.doubleValue;
        reading.glmWord = glmWord;
        [readings addObject:reading];
    }
    XCTAssertGreaterThan(readings.count, 0u, @"%@", scenario);
    return readings;
}

// At every rest point from `start` on, a reading held 1.5 s or more, qlm's
// volume is GLM's level at the hold's end, within `decibels`.
- (NSUInteger)assertRestPointsOf:(NSArray<QLMKnobReading *> *)readings from:(NSTimeInterval)start within:(double)decibels {
    NSUInteger checked = 0;
    NSUInteger i = 0;
    while (i < readings.count) {
        NSUInteger end = i;
        while (end + 1 < readings.count && readings[end + 1].tenths == readings[i].tenths) {
            end++;
        }
        QLMKnobReading *last = readings[end];
        if (readings[i].time >= start && last.time - readings[i].time >= 1.5 && last.glmWord != 0) {
            checked++;
            uint32_t qlm = QLMVolumeWordForDecibels(last.volume);
            if (decibels == 0) {
                XCTAssertEqual(qlm, last.glmWord, @"%.3f s, knob at %ld", last.time, (long)last.tenths);
            } else {
                // GLM's words lie within a count of their steps.
                double glm = round(QLMVolumeDecibelsForWord(last.glmWord) / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
                glm = fmax(QLMVolumeDecibelsMin, glm);
                XCTAssertLessThanOrEqual(fabs(glm - last.volume), decibels, @"%.3f s, knob at %ld", last.time, (long)last.tenths);
            }
        }
        i = end + 1;
    }
    return checked;
}

// The first reading after which the volume is no longer `from`.
static QLMKnobReading *_Nullable QLMFirstChange(NSArray<QLMKnobReading *> *readings, double from) {
    for (QLMKnobReading *reading in readings) {
        if (reading.volume != from) {
            return reading;
        }
    }
    return nil;
}

// knob-sweep: GLM opens at -56.5 dB with the knob at -77.5, and keeps its
// level until the knob turns at 18.95 s, to -73.0 dB. Then the knob sweeps
// the whole range four times. At every stop, qlm's level is GLM's.
- (void)testTheKnobFollowsGLMInKnobSweep {
    NSArray<QLMKnobReading *> *readings = [self run:@"knob-sweep" from:-56.5];
    QLMKnobReading *first = QLMFirstChange(readings, -56.5);
    XCTAssertEqualWithAccuracy(first.time, 18.945912, 0.0005);
    XCTAssertEqual(QLMVolumeWordForDecibels(first.volume), 0x000755u);
    XCTAssertGreaterThanOrEqual([self assertRestPointsOf:readings from:0 within:0], 6u);
}

// startup-idle: the knob rests at the bottom until a turn at 38.48 s, up and
// back down. unplug-proxy-hang: the knob wobbles by up to 0.8 dB from 15.4 to
// 18.0 s, and GLM keeps its level. After the adapter comes back, at 106.2 s,
// the knob reads 55 dB lower, and GLM follows it.
- (void)testTheKnobRestsAtGLMsLevel {
    NSArray<QLMKnobReading *> *startup = [self run:@"startup-idle" from:-56.5];
    XCTAssertEqualWithAccuracy(QLMFirstChange(startup, -56.5).time, 38.590, 0.001);
    XCTAssertGreaterThanOrEqual([self assertRestPointsOf:startup from:0 within:0], 2u);

    NSArray<QLMKnobReading *> *hang = [self run:@"unplug-proxy-hang" from:-56.5];
    XCTAssertEqualWithAccuracy(QLMFirstChange(hang, -56.5).time, 106.237, 0.001);
    XCTAssertGreaterThanOrEqual([self assertRestPointsOf:hang from:0 within:0], 6u);
}

// sleep-wake-no-sleep: the reading wanders from -64.7 to -63.7 dB over 130 s,
// and GLM keeps -64.5 dB. So does qlm.
- (void)testAWanderAtRestMovesNothingInSleepWakeNoSleep {
    NSArray<QLMKnobReading *> *readings = [self run:@"sleep-wake-no-sleep" from:-64.5];
    XCTAssertNil(QLMFirstChange(readings, -64.5));
    XCTAssertGreaterThanOrEqual([self assertRestPointsOf:readings from:0 within:0], 1u);
}

// standby-wake: the knob was just plugged in, and its reading settles near
// the bottom. sleep-wake-darkwake: the reading wanders over 7 dB in 600 s,
// mostly a tenth at a time, and GLM follows much of it. qlm takes none of
// that wander until a turn at 165.7 s. From then on, a volume that is the
// knob's stays within 1 dB of GLM's.
- (void)testTheKnobStaysWithinADecibelOfGLM {
    NSArray<QLMKnobReading *> *standby = [self run:@"standby-wake" from:QLMVolumeDecibelsMin];
    XCTAssertGreaterThanOrEqual([self assertRestPointsOf:standby from:0 within:1.0], 6u);

    NSArray<QLMKnobReading *> *darkwake = [self run:@"sleep-wake-darkwake" from:-73.0];
    NSTimeInterval first = QLMFirstChange(darkwake, -73.0).time;
    XCTAssertEqualWithAccuracy(first, 165.688, 0.001);
    XCTAssertGreaterThanOrEqual([self assertRestPointsOf:darkwake from:first within:1.0], 20u);
}

@end
