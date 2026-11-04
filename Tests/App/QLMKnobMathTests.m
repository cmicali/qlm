#import <XCTest/XCTest.h>

#import "QLMKnobMath.h"

// The knob's angle math. Sources: the pack's README-pack.txt, Knob
// composition: -135 to +135 degrees clockwise from straight up, with
// angle = -135 + fraction * 270. And docs/protocol.md: GLM's volume moves in
// 0.5 dB steps.
@interface QLMKnobMathTests : XCTestCase
@end

@implementation QLMKnobMathTests

- (void)testTheSweepsEnds {
    XCTAssertEqual(QLMKnobAngleForDecibels(-80, -80, -30), -135);
    XCTAssertEqual(QLMKnobAngleForDecibels(-30, -80, -30), 135);
    XCTAssertEqual(QLMKnobAngleForDecibels(-55, -80, -30), 0);
    // Outside the range, the nearer end.
    XCTAssertEqual(QLMKnobAngleForDecibels(-90, -80, -30), -135);
    XCTAssertEqual(QLMKnobAngleForDecibels(0, -80, -30), 135);
    // An empty range, or no level, sits at the start.
    XCTAssertEqual(QLMKnobAngleForDecibels(-40, -30, -30), -135);
    XCTAssertEqual(QLMKnobAngleForDecibels(NAN, -80, -30), -135);
}

// The pack's sample: -42 dB on -80 to -30 is 70.2 degrees.
- (void)testThePacksSample {
    XCTAssertEqualWithAccuracy(QLMKnobAngleForDecibels(-42, -80, -30), 70.2, 1e-9);
}

- (void)testAngleBackToDecibels {
    XCTAssertEqual(QLMKnobDecibelsForAngle(-135, -80, -30), -80);
    XCTAssertEqual(QLMKnobDecibelsForAngle(135, -80, -30), -30);
    XCTAssertEqual(QLMKnobDecibelsForAngle(0, -80, -30), -55);
    XCTAssertEqual(QLMKnobDecibelsForAngle(170, -80, -30), -30);
    XCTAssertEqual(QLMKnobDecibelsForAngle(-170, -80, -30), -80);
    for (double decibels = -80; decibels <= -30; decibels += 0.5) {
        double angle = QLMKnobAngleForDecibels(decibels, -80, -30);
        XCTAssertEqualWithAccuracy(QLMKnobDecibelsForAngle(angle, -80, -30), decibels, 1e-9);
    }
}

- (void)testTheStepSnap {
    XCTAssertEqual(QLMKnobSnap(-42.2, -80, -30), -42);
    XCTAssertEqual(QLMKnobSnap(-42.3, -80, -30), -42.5);
    XCTAssertEqual(QLMKnobSnap(-42.75, -80, -30), -43);  // half away from zero
    XCTAssertEqual(QLMKnobSnap(-12, -80, -30), -30);
    XCTAssertEqual(QLMKnobSnap(-95, -80, -30), -80);
    // A ceiling off the steps gives the step below it, never above.
    XCTAssertEqual(QLMKnobSnap(-30, -80, -30.2), -30.5);
    XCTAssertEqual(QLMKnobSnap(-80, -80.3, -30), -80);
}

- (void)testAStep {
    XCTAssertEqual(QLMKnobStep(-42, 1, -80, -30), -41.5);
    XCTAssertEqual(QLMKnobStep(-42, -1, -80, -30), -42.5);
    XCTAssertEqual(QLMKnobStep(-42.2, 1, -80, -30), -41.5);
    XCTAssertEqual(QLMKnobStep(-30, 1, -80, -30), -30);
    XCTAssertEqual(QLMKnobStep(-80, -3, -80, -30), -80);
}

- (void)testTheTicks {
    XCTAssertEqual(QLMKnobTickAngle(0, 11), -135);
    XCTAssertEqual(QLMKnobTickAngle(5, 11), 0);
    XCTAssertEqual(QLMKnobTickAngle(10, 11), 135);
    XCTAssertEqual(QLMKnobTickAngle(1, 11), -108);
    XCTAssertEqual(QLMKnobTickAngle(1, 3), 0);
    XCTAssertEqual(QLMKnobTickAngle(0, 1), 0);
}

// The vintage pack's tick ring has the first tick at (36.381, 139.619) to
// (32.846, 143.154) around (88, 88): -135 degrees, from 73 to 78.
- (void)testATickPointMatchesThePacksRing {
    double x = 0, y = 0;
    QLMKnobPointAt(88, 88, 73, QLMKnobTickAngle(0, 11), &x, &y);
    XCTAssertEqualWithAccuracy(x, 36.381, 1e-3);
    XCTAssertEqualWithAccuracy(y, 139.619, 1e-3);
    QLMKnobPointAt(88, 88, 78, QLMKnobTickAngle(0, 11), &x, &y);
    XCTAssertEqualWithAccuracy(x, 32.846, 1e-3);
    XCTAssertEqualWithAccuracy(y, 143.154, 1e-3);
}

// Up is 0, right is 90, left is -90, y down.
- (void)testTheAngleOfAnOffset {
    XCTAssertEqual(QLMKnobAngleOfOffset(0, -10), 0);
    XCTAssertEqual(QLMKnobAngleOfOffset(10, 0), 90);
    XCTAssertEqual(QLMKnobAngleOfOffset(-10, 0), -90);
    XCTAssertEqualWithAccuracy(QLMKnobAngleOfOffset(-10, 10), -135, 1e-9);
}

// A drag is relative: the level moves by the angle the mouse turned, at
// the sweep's rate, wherever the drag began. The listener comes first, so
// no turn moves nothing, and nothing in the dead zone moves it.
- (void)testADrag {
    // 270 degrees is the whole range, 50 dB here.
    XCTAssertEqualWithAccuracy(QLMKnobDragStep(-70, 0, 27, -80, -30), -65, 1e-9);
    XCTAssertEqualWithAccuracy(QLMKnobDragStep(-70, 90, 63, -80, -30), -75, 1e-9);
    XCTAssertEqual(QLMKnobDragStep(-70, -100, -100, -80, -30), -70);
    // From anywhere: a press far from the pointer jumps nothing.
    XCTAssertEqual(QLMKnobDragStep(-70, 120, 120, -80, -30), -70);
    XCTAssertEqualWithAccuracy(QLMKnobDragStep(-70, 120, 121, -80, -30), -70 + 50.0 / 270, 1e-9);
    // The ends hold.
    XCTAssertEqual(QLMKnobDragStep(-32, 0, 45, -80, -30), -30);
    XCTAssertEqual(QLMKnobDragStep(-78, 0, -45, -80, -30), -80);
    // In the dead zone, or into it, or out of it, the level stays.
    XCTAssertEqual(QLMKnobDragStep(-70, 170, -170, -80, -30), -70);
    XCTAssertEqual(QLMKnobDragStep(-70, 130, 140, -80, -30), -70);
    XCTAssertEqual(QLMKnobDragStep(-70, 140, 130, -80, -30), -70);
    // An empty range moves nothing.
    XCTAssertEqual(QLMKnobDragStep(-30, 0, 30, -30, -30), -30);
}

// A slow drag adds up, unsnapped, before a step goes out.
- (void)testASlowDragAddsUp {
    // 0.27 degrees is 0.05 dB.
    double level = -70;
    for (int i = 0; i < 10; i++) {
        level = QLMKnobDragStep(level, i * 0.27, (i + 1) * 0.27, -80, -30);
        if (i == 2) {
            XCTAssertEqual(QLMKnobSnap(level, -80, -30), -70);
        }
    }
    XCTAssertEqualWithAccuracy(level, -69.5, 1e-9);
    XCTAssertEqual(QLMKnobSnap(level, -80, -30), -69.5);
}

// One event that crosses the gap below the knob, or passes over its center,
// keeps the level: it is never a jump, louder or quieter.
- (void)testAJumpInOneEventKeepsTheLevel {
    XCTAssertEqual(QLMKnobDragStep(-40, 135, -135, -80, 0), -40);
    XCTAssertEqual(QLMKnobDragStep(-40, -135, 135, -80, 0), -40);
    XCTAssertEqual(QLMKnobDragStep(-40, -90, 90, -80, 0), -40);
    XCTAssertEqual(QLMKnobDragStep(-40, 90, -90, -80, 0), -40);
    XCTAssertEqual(QLMKnobDragStep(-40, 0, 45.5, -80, 0), -40);
}

// A large turn within the cap moves the level by its share of the sweep.
- (void)testALargeLegalStepMoves {
    XCTAssertEqualWithAccuracy(QLMKnobDragStep(-40, 0, 45, -80, 0), -40 + 45.0 / 270 * 80, 1e-9);
    XCTAssertEqualWithAccuracy(QLMKnobDragStep(-40, 100, 135, -80, 0), -40 + 35.0 / 270 * 80, 1e-9);
    XCTAssertEqualWithAccuracy(QLMKnobDragStep(-40, -100, -135, -80, 0), -40 - 35.0 / 270 * 80, 1e-9);
}

@end
