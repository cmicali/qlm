#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>

#import "QLMKnobControl.h"
#import "QLMKnobMath.h"
#import "QLMSkinControls.h"
#import "QLMSkinLayers.h"
#import "QLMTestSupport.h"

// The knob's pointer and arc, and the OSD's bar, ease to each new level in
// their own layers, from where they show, and never while the knob is
// dragged, the user asks for less motion, the window isn't seen, or a view
// shows its first level. A step draws nothing. Source: docs/ui.md, The
// layers.
@interface QLMSkinEaseTests : XCTestCase
@end

static BOOL QLMTestSeen = NO;
static BOOL QLMTestReduced = NO;
static BOOL (*QLMTestRealSeen)(NSWindow *);
static BOOL (*QLMTestRealReduced)(void);

static BOOL QLMTestWindowIsSeen(NSWindow *window) {
    return QLMTestSeen;
}

static BOOL QLMTestMotionIsReduced(void) {
    return QLMTestReduced;
}

// A knob that counts its layers' updates.
@interface QLMTestCountingKnob : QLMKnobControl
@property (nonatomic) NSInteger updates;
@end

@implementation QLMTestCountingKnob
- (void)updateLayer {
    self.updates++;
    [super updateLayer];
}
@end

static NSWindow *QLMTestEaseWindow(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 400) styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView.wantsLayer = YES;
    return window;
}

// TRAP: here, a window's displayIfNeeded draws nothing. The transaction's
// commit draws, and gives each layer its presentation.
static void QLMTestPump(NSWindow *window) {
    [window displayIfNeeded];
    [CATransaction flush];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static CAShapeLayer *QLMTestPointer(QLMKnobControl *knob) {
    return (CAShapeLayer *)knob.layers.movingLayers.lastObject;
}

static NSString *const QLMTestTurn = @"transform.rotation.z";

@implementation QLMSkinEaseTests {
    NSWindow *_window;
    QLMTestCountingKnob *_knob;
}

- (void)setUp {
    [super setUp];
    QLMTestRealSeen = QLMSkinEaseWindowIsSeen;
    QLMTestRealReduced = QLMSkinEaseMotionIsReduced;
    QLMTestSeen = YES;
    QLMTestReduced = NO;
    QLMSkinEaseWindowIsSeen = QLMTestWindowIsSeen;
    QLMSkinEaseMotionIsReduced = QLMTestMotionIsReduced;
    _window = QLMTestEaseWindow();
    _knob = [[QLMTestCountingKnob alloc] initWithSkin:QLMBuiltInSkin(@"modern")];
    _knob.frame = NSMakeRect(20, 20, 200, 200);
    _knob.minValue = -80;
    _knob.maxValue = -30;
    _knob.doubleValue = -59;
    [_window.contentView addSubview:_knob];
    QLMTestPump(_window);
}

- (void)tearDown {
    [_window close];
    QLMSkinEaseWindowIsSeen = QLMTestRealSeen;
    QLMSkinEaseMotionIsReduced = QLMTestRealReduced;
    [super tearDown];
}

- (double)turnAt:(double)decibels {
    double radians = QLMKnobAngleForDecibels(decibels, -80, -30) * M_PI / 180;
    return QLMTestPointer(_knob).contentsAreFlipped ? radians : -radians;
}

// The pointer's turn and the arc's end hold the level, at once, whether or
// not they ease, and the step draws nothing.
- (void)testAStepSetsTheLayersAndDrawsNothing {
    _knob.updates = 0;
    XCTAssertTrue([_knob stepBy:1]);
    QLMTestPump(_window);
    XCTAssertEqual(_knob.updates, 0);
    CAShapeLayer *arc = (CAShapeLayer *)_knob.layers.movingLayers.firstObject;
    XCTAssertEqualWithAccuracy([[QLMTestPointer(_knob) valueForKeyPath:QLMTestTurn] doubleValue], [self turnAt:-58.5], 1e-9);
    XCTAssertEqualWithAccuracy(arc.strokeEnd, QLMKnobFraction(-58.5, -80, -30), 1e-6);
    XCTAssertNotNil([QLMTestPointer(_knob) animationForKey:QLMTestTurn]);
    XCTAssertNotNil([arc animationForKey:@"strokeEnd"]);
}

// It eases from where the pointer shows now, so a turn during an ease
// turns on from there, rather than from the level before.
- (void)testAnEaseStartsWhereThePointerShows {
    CAShapeLayer *pointer = QLMTestPointer(_knob);
    // Held halfway between -59 and -45.
    CABasicAnimation *held = [CABasicAnimation animationWithKeyPath:QLMTestTurn];
    held.fromValue = @([self turnAt:-59]);
    held.toValue = @([self turnAt:-45]);
    held.duration = 1;
    held.speed = 0;
    held.timeOffset = 0.5;
    [pointer addAnimation:held forKey:QLMTestTurn];
    QLMTestPump(_window);
    double shown = [[pointer.presentationLayer valueForKeyPath:QLMTestTurn] doubleValue];
    XCTAssertEqualWithAccuracy(shown, ([self turnAt:-59] + [self turnAt:-45]) / 2, 1e-6);

    _knob.doubleValue = -40;
    CABasicAnimation *ease = (CABasicAnimation *)[pointer animationForKey:QLMTestTurn];
    XCTAssertEqualWithAccuracy([ease.fromValue doubleValue], shown, 1e-6);
    XCTAssertEqualWithAccuracy([ease.toValue doubleValue], [self turnAt:-40], 1e-9);
    XCTAssertEqual(ease.duration, QLMSkinEaseSeconds);
}

- (void)assertTakesTheLevelAtOnce:(NSString *)why {
    XCTAssertTrue([_knob stepBy:-1], @"%@", why);
    XCTAssertNil([QLMTestPointer(_knob) animationForKey:QLMTestTurn], @"%@", why);
    XCTAssertEqualWithAccuracy([[QLMTestPointer(_knob) valueForKeyPath:QLMTestTurn] doubleValue], [self turnAt:-59.5], 1e-9,
                               @"%@", why);
}

- (void)testAWindowNotSeenTakesTheLevelAtOnce {
    QLMTestSeen = NO;
    [self assertTakesTheLevelAtOnce:@"not seen"];
}

- (void)testReducedMotionTakesTheLevelAtOnce {
    QLMTestReduced = YES;
    [self assertTakesTheLevelAtOnce:@"reduced motion"];
}

- (void)testACatchUpTakesTheLevelAtOnce {
    QLMSkinWithoutEase(^{
        [self assertTakesTheLevelAtOnce:@"catching up"];
    });
}

// A view's first level, as a new skin's knob takes, has nothing to ease
// from.
- (void)testANewKnobTakesItsFirstLevelAtOnce {
    QLMKnobControl *knob = [[QLMKnobControl alloc] initWithSkin:QLMBuiltInSkin(@"vintage")];
    knob.frame = NSMakeRect(20, 20, 200, 200);
    [_window.contentView addSubview:knob];
    knob.doubleValue = -20;
    XCTAssertNil([QLMTestPointer(knob) animationForKey:QLMTestTurn]);
    QLMTestPump(_window);
    XCTAssertNil([QLMTestPointer(knob) animationForKey:QLMTestTurn]);
}

// A drag tracks the mouse exactly.
- (void)testADragTakesEachLevelAtOnce {
    NSPoint center = [_knob convertPoint:NSMakePoint(100, 100) toView:nil];
    NSEvent * (^mouse)(NSEventType, CGFloat) = ^NSEvent *(NSEventType type, CGFloat dy) {
        return [NSEvent mouseEventWithType:type location:NSMakePoint(center.x, center.y + dy) modifierFlags:0 timestamp:0
                              windowNumber:self->_window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    };
    [NSApplication sharedApplication];
    [NSApp postEvent:mouse(NSEventTypeLeftMouseDragged, 20) atStart:NO];
    [NSApp postEvent:mouse(NSEventTypeLeftMouseUp, 20) atStart:NO];
    [_knob mouseDown:mouse(NSEventTypeLeftMouseDown, 0)];
    XCTAssertGreaterThan(_knob.doubleValue, -59);
    XCTAssertNil([QLMTestPointer(_knob) animationForKey:QLMTestTurn]);
    // After it, a step eases again.
    XCTAssertTrue([_knob stepBy:1]);
    XCTAssertNotNil([QLMTestPointer(_knob) animationForKey:QLMTestTurn]);
}

// The OSD's fill shows to the level's whole point, and eases there.
- (void)testTheOSDsBarEasesToItsWidth {
    QLMSkin *skin = QLMBuiltInSkin(@"retro");
    NSWindow *window = QLMTestEaseWindow();
    QLMSkinOSDView *osd = [[QLMSkinOSDView alloc] initWithSkin:skin];
    [window setContentSize:osd.frame.size];
    [window.contentView addSubview:osd];
    osd.fraction = 0.25;
    QLMTestPump(window);
    CALayer *clip = osd.layers.movingLayers.firstObject;
    XCTAssertNil([clip animationForKey:@"bounds"]);
    osd.fraction = 0.42;
    XCTAssertEqual(clip.bounds.size.width, round(skin.osd.bar.frame.size.width * 0.42));
    XCTAssertNotNil([clip animationForKey:@"bounds"]);
    QLMTestSeen = NO;
    osd.fraction = 0.5;
    XCTAssertNil([clip animationForKey:@"bounds"]);
    XCTAssertEqual(clip.bounds.size.width, round(skin.osd.bar.frame.size.width * 0.5));
    [window close];
}

@end
