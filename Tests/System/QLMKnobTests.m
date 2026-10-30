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

// A turn of small steps keeps going: each move of more than a whole dB from
// the last reading followed starts the 2.54 s again (qlm-control-first,
// 373.11 to 377.50 s).
- (void)testATurnIsFollowedToItsEnd {
    QLMKnob *knob = [[QLMKnob alloc] init];
    [knob volumeForReading:-400 atTime:0 volume:@(-40)];
    NSNumber *volume = @(-40);
    NSInteger tenths = -400;
    for (int i = 1; i <= 60; i++) {
        tenths -= 6;  // 6 tenths each 0.1 s, for 6 s
        NSNumber *set = [knob volumeForReading:tenths atTime:i * 0.1 volume:volume];
        volume = set ?: volume;
    }
    XCTAssertEqualObjects(volume, @(-76.0));
}

// A slow drift of more than a whole dB moves the volume, as in
// sleep-wake-darkwake from 26.33 s, where the reading had crept 11 tenths in
// 20 s. A wander of a whole dB or less never does, however long it takes, as
// in sleep-wake-no-sleep, where 10 tenths over 130 s never moved GLM.
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

    QLMKnob *still = [[QLMKnob alloc] init];
    [still volumeForReading:-640 atTime:0 volume:@(-30)];
    for (int i = 1; i <= 40; i++) {
        tenths = -640 + (i * 7) % 11;  // up to 10 tenths away, and back
        XCTAssertNil([still volumeForReading:tenths atTime:i * 0.6 volume:@(-30)], @"%ld", (long)tenths);
    }
}

@end
