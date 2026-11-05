#import <XCTest/XCTest.h>

#import "QLMKnobControl.h"
#import "QLMTestSupport.h"

// The knob's step, which its arrow keys, its scroll wheel, VoiceOver, and
// the menu's Volume Up and Down take: one of GLM's 0.5 dB steps, inside the
// range, so never past the ceiling. Source: docs/ui.md, The menu.
@interface QLMKnobControlTests : XCTestCase
@end

@implementation QLMKnobControlTests {
    QLMKnobControl *_knob;
    NSMutableArray<NSNumber *> *_sent;
}

- (void)setUp {
    [super setUp];
    _knob = [[QLMKnobControl alloc] initWithSkin:QLMBuiltInSkin(@"modern")];
    _knob.minValue = -60;
    _knob.maxValue = -30;
    _knob.target = self;
    _knob.action = @selector(turned:);
    _sent = [NSMutableArray array];
}

- (void)turned:(QLMKnobControl *)knob {
    [_sent addObject:@(knob.doubleValue)];
}

// From `from`, `steps` lands on `to`, or on nothing for nil, sending only
// what it lands on.
- (void)assertStepFrom:(double)from by:(int)steps to:(nullable NSNumber *)to {
    _knob.doubleValue = from;
    [_sent removeAllObjects];
    XCTAssertEqual([_knob canStepBy:steps], to != nil, @"%g by %d", from, steps);
    XCTAssertEqual([_knob stepBy:steps], to != nil, @"%g by %d", from, steps);
    XCTAssertEqualObjects(_sent, to != nil ? @[to] : @[], @"%g by %d", from, steps);
    XCTAssertEqual(_knob.doubleValue, to != nil ? to.doubleValue : from, @"%g by %d", from, steps);
}

- (void)testAStepMovesOneStepInsideTheRange {
    [self assertStepFrom:-40 by:1 to:@(-39.5)];
    [self assertStepFrom:-40 by:-1 to:@(-40.5)];
    [self assertStepFrom:-40.2 by:1 to:@(-39.5)];
    [self assertStepFrom:-30.5 by:1 to:@(-30)];
    [self assertStepFrom:-30 by:1 to:nil];
    [self assertStepFrom:-60 by:-1 to:nil];
    [self assertStepFrom:-60 by:1 to:@(-59.5)];
}

// Disabled, or while its level waits for the knob's first reading, from
// which a step would send a level the monitors don't have.
- (void)testAKnobThatTakesNoTurnTakesNoStep {
    _knob.enabled = NO;
    [self assertStepFrom:-40 by:1 to:nil];
    [self assertStepFrom:-40 by:-1 to:nil];
    _knob.enabled = YES;
    _knob.waitsForLevel = YES;
    [self assertStepFrom:-40 by:1 to:nil];
    XCTAssertFalse([_knob accessibilityPerformIncrement]);
    XCTAssertEqualObjects(_sent, @[]);
    _knob.waitsForLevel = NO;
    [self assertStepFrom:-40 by:1 to:@(-39.5)];
}

@end
