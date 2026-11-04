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

// A drag points the knob at the mouse, snapped. Below the knob it holds the
// nearer end, so the pointer never jumps across.
- (void)testADrag {
    XCTAssertEqual(QLMKnobDecibelsForDrag(0, -50, -70, -80, -30), -55);
    XCTAssertEqual(QLMKnobDecibelsForDrag(50, 0, -70, -80, -30), QLMKnobSnap(-80 + 225.0 / 270 * 50, -80, -30));
    XCTAssertEqual(QLMKnobDecibelsForDrag(1, 50, -35, -80, -30), -30);
    XCTAssertEqual(QLMKnobDecibelsForDrag(-1, 50, -35, -80, -30), -30);
    XCTAssertEqual(QLMKnobDecibelsForDrag(1, 50, -75, -80, -30), -80);
}

@end
