#import <XCTest/XCTest.h>

#import "QLMKnob.h"
#include "QLMCommands.h"

// Sources: docs/protocol.md, "Volume and the knob", and the captures each
// test names. QLMKnobGoldenTests replays whole captures through System.
@interface QLMKnobTests : XCTestCase
@end

@implementation QLMKnobTests

- (void)testTheFirstReadingIsWhereTheKnobRests {
    QLMKnob *knob = [[QLMKnob alloc] init];
    XCTAssertNil([knob volumeForReading:-300 atTime:0 volume:@(-56.5)]);
    XCTAssertNil([knob volumeForReading:-300 atTime:0.1 volume:@(-56.5)]);
    // A reconnect keeps the rest point, so a turn while away moves the volume.
    XCTAssertEqualObjects([knob volumeForReading:-739 atTime:88 volume:@(-56.5)], @(-74.0));
    [knob reset];
    XCTAssertNil([knob volumeForReading:-200 atTime:89 volume:@(-74.0)]);
}

// A move of more than a whole dB moves the volume, to the nearest step. A
// whole dB does not.
- (void)testAMoveOfMoreThanADecibelMovesTheVolume {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-775 atTime:0 volume:@(-56.5)];
    XCTAssertNil([knob volumeForReading:-765 atTime:0.1 volume:@(-56.5)]);
    XCTAssertEqualObjects([knob volumeForReading:-764 atTime:0.2 volume:@(-56.5)], @(-76.5));
    XCTAssertEqualObjects([knob volumeForReading:-123 atTime:0.3 volume:@(-76.5)], @(-12.5));
    XCTAssertEqualObjects([knob volumeForReading:5 atTime:0.4 volume:@(-12.5)], @(0.0));
    XCTAssertEqualObjects([knob volumeForReading:-1004 atTime:0.5 volume:@(0.0)], @(QLMVolumeDecibelsMin));
    XCTAssertNil([knob volumeForReading:-999 atTime:0.6 volume:@(QLMVolumeDecibelsMin)]);
}

- (void)testWithNoVolumeTheKnobSetsNone {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-775 atTime:0 volume:nil];
    XCTAssertNil([knob volumeForReading:-300 atTime:0.1 volume:nil]);
}

// For 2.54 s after that move, the volume follows every change, however
// small, to the nearest step. Then a change of a dB or less moves nothing.
// GLM followed a change 2.53 s on, and none from 2.55 s
// (sleep-wake-darkwake, 132.02 and 28.88 s).
- (void)testThenTheVolumeFollowsEveryChange {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-500 atTime:0 volume:@(-30)];
    XCTAssertEqualObjects([knob volumeForReading:-400 atTime:1 volume:@(-30)], @(-40.0));
    XCTAssertEqualObjects([knob volumeForReading:-403 atTime:1.1 volume:@(-40.0)], @(-40.5));
    XCTAssertNil([knob volumeForReading:-404 atTime:1.2 volume:@(-40.5)]);
    XCTAssertEqualObjects([knob volumeForReading:-408 atTime:3.53 volume:@(-40.5)], @(-41.0));
    XCTAssertNil([knob volumeForReading:-414 atTime:3.55 volume:@(-41.0)]);
    XCTAssertNil([knob volumeForReading:-418 atTime:9 volume:@(-41.0)]);
}

// Each move of more than a whole dB starts the 2.54 s again, so a turn is
// followed to its end (knob-sweep, 26.5 to 30.5 s).
- (void)testAMoveOfMoreThanADecibelStartsTheTimeAgain {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-400 atTime:0 volume:@(-40)];
    XCTAssertEqualObjects([knob volumeForReading:-420 atTime:1 volume:@(-40)], @(-42.0));
    XCTAssertEqualObjects([knob volumeForReading:-432 atTime:3 volume:@(-42.0)], @(-43.0));
    XCTAssertEqualObjects([knob volumeForReading:-433 atTime:5 volume:@(-43.0)], @(-43.5));
    XCTAssertNil([knob volumeForReading:-434 atTime:5.6 volume:@(-43.5)]);
}

// A slow drift of more than a whole dB moves the volume, as in
// sleep-wake-darkwake from 26.33 s, where the reading had crept 11 tenths in
// 20 s. Before that, a whole dB moved nothing.
- (void)testASlowDriftOfMoreThanADecibelMovesTheVolume {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-731 atTime:0 volume:@(-73.0)];
    NSInteger tenths = -731;
    for (int i = 1; i <= 10; i++) {
        tenths += 1;
        XCTAssertNil([knob volumeForReading:tenths atTime:i * 2.0 volume:@(-73.0)], @"%ld", (long)tenths);
    }
    XCTAssertEqualObjects([knob volumeForReading:-720 atTime:22 volume:@(-73.0)], @(-72.0));
    XCTAssertEqualObjects([knob volumeForReading:-717 atTime:23 volume:@(-72.0)], @(-71.5));
}

// As the plug slides out, the reading jumps, and the first poll of a pair
// reads it out 0.44 s after it first moved (volume-sweep, 25.11 to
// 25.56 s). So a knob that comes out takes back its raises of the last
// second, to the lowest the volume was before any of them. A follow from
// before that stands. Then the knob rests again.
- (void)testAKnobPulledOutTakesBackItsLastSecond {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-400 atTime:0 volume:@(-40)];
    XCTAssertEqualObjects([knob volumeForReading:-300 atTime:0.5 volume:@(-40)], @(-30.0));
    XCTAssertEqualObjects([knob volumeForReading:-250 atTime:1.6 volume:@(-30.0)], @(-25.0));
    XCTAssertEqualObjects([knob volumeForReading:-200 atTime:1.7 volume:@(-25.0)], @(-20.0));
    XCTAssertEqualObjects([knob volumeAtUnplugAtTime:2.0 volume:@(-20.0)], @(-30.0));
    XCTAssertNil([knob volumeForReading:-500 atTime:3 volume:@(-30.0)]);

    [knob volumeForReading:-400 atTime:10 volume:@(-40)];
    XCTAssertEqualObjects([knob volumeForReading:-300 atTime:11 volume:@(-40)], @(-30.0));
    XCTAssertNil([knob volumeAtUnplugAtTime:12.01 volume:@(-30.0)]);
}

// In volume-sweep, the knob came out at its bottom stop, with GLM's level
// above it. The jump took GLM's level down, from -56.5 dB to -99.0 at
// 25.23 s, then up to -97.5 at 25.34 s. The lowering stands, and the raise
// after it is taken back.
- (void)testAKnobPulledOutKeepsALowerVolumeAndTakesBackARaiseAfterIt {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-1004 atTime:0 volume:@(-56.5)];
    XCTAssertEqualObjects([knob volumeForReading:-992 atTime:0.11 volume:@(-56.5)], @(-99.0));
    XCTAssertNil([knob volumeAtUnplugAtTime:0.2 volume:@(-99.0)]);

    [knob volumeForReading:-1004 atTime:1 volume:@(-56.5)];
    XCTAssertEqualObjects([knob volumeForReading:-992 atTime:1.11 volume:@(-56.5)], @(-99.0));
    XCTAssertEqualObjects([knob volumeForReading:-974 atTime:1.22 volume:@(-99.0)], @(-97.5));
    XCTAssertEqualObjects([knob volumeAtUnplugAtTime:1.33 volume:@(-97.5)], @(-99.0));
}

@end
