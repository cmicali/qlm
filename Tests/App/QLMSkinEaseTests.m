#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>

#import "QLMKnobControl.h"
#import "QLMKnobMath.h"
#import "QLMSkinControls.h"
#import "QLMSkinLayers.h"
#import "QLMSkinLayersTesting.h"
#import "QLMSkinTestBitmaps.h"
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
    _window = QLMTestOffscreenWindow(NSMakeSize(400, 400));
    _knob = [[QLMTestCountingKnob alloc] initWithSkin:QLMBuiltInSkin(@"modern")];
    _knob.frame = NSMakeRect(20, 20, 200, 200);
    _knob.minValue = -80;
    _knob.maxValue = -30;
    _knob.doubleValue = -59;
    [_window.contentView addSubview:_knob];
    QLMTestPumpWindow(_window);
}

- (void)tearDown {
    [_window close];
    QLMSkinEaseWindowIsSeen = QLMTestRealSeen;
    QLMSkinEaseMotionIsReduced = QLMTestRealReduced;
    [super tearDown];
}

- (double)turnAt:(double)decibels {
    double radians = QLMKnobRadians(QLMKnobAngleForDecibels(decibels, -80, -30));
    return QLMTestPointer(_knob).contentsAreFlipped ? radians : -radians;
}

// The pointer's turn and the arc's end hold the level, at once, whether or
// not they ease, and the step draws nothing.
- (void)testAStepSetsTheLayersAndDrawsNothing {
    _knob.updates = 0;
    XCTAssertTrue([_knob stepBy:1]);
    QLMTestPumpWindow(_window);
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
    QLMTestPumpWindow(_window);
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
    QLMTestPumpWindow(_window);
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
    NSWindow *window = QLMTestOffscreenWindow(NSMakeSize(400, 400));
    QLMSkinOSDView *osd = [[QLMSkinOSDView alloc] initWithSkin:skin];
    [window setContentSize:osd.frame.size];
    [window.contentView addSubview:osd];
    osd.fraction = 0.25;
    QLMTestPumpWindow(window);
    CALayer *clip = osd.layers.movingLayers.firstObject;
    XCTAssertNil([clip animationForKey:@"bounds.size.width"]);
    osd.fraction = 0.42;
    XCTAssertEqual(clip.bounds.size.width, round(skin.osd.bar.frame.size.width * 0.42));
    XCTAssertNotNil([clip animationForKey:@"bounds.size.width"]);
    QLMTestSeen = NO;
    osd.fraction = 0.5;
    XCTAssertNil([clip animationForKey:@"bounds.size.width"]);
    XCTAssertEqual(clip.bounds.size.width, round(skin.osd.bar.frame.size.width * 0.5));
    [window close];
}

// Without focus the knob's content draws nothing, so a hover draws no
// content layer.
- (void)testAnUnfocusedKnobDrawsNoContent {
    _knob.hovered = YES;
    QLMTestPumpWindow(_window);
    XCTAssertFalse([_knob drawsSkinContent]);
    XCTAssertNil(_knob.layer.sublayers.lastObject.contents);
}

// A screenshot shows the level, not the way there.
- (void)testFinishingTheEasesShowsTheLevel {
    XCTAssertTrue([_knob stepBy:1]);
    XCTAssertNotNil([QLMTestPointer(_knob) animationForKey:QLMTestTurn]);
    QLMSkinFinishEases();
    XCTAssertNil([QLMTestPointer(_knob) animationForKey:QLMTestTurn]);
    XCTAssertEqualWithAccuracy([[QLMTestPointer(_knob).presentationLayer valueForKeyPath:QLMTestTurn] doubleValue],
                               [self turnAt:-58.5], 1e-9);
}

// How many of the layer's pixels show ink, as it renders alone.
static NSInteger QLMTestInk(CALayer *layer) {
    NSBitmapImageRep *bitmap = QLMTestBitmap(layer.bounds.size);
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
    CGContextScaleCTM(cg, QLMTestScale, QLMTestScale);
    [layer renderInContext:cg];
    NSRect ink = QLMTestPixelBounds(bitmap, bitmap, ^BOOL(const uint8_t *u, const uint8_t *v) {
        return u[3] > 0;
    });
    return (NSInteger)(ink.size.width * ink.size.height);
}

// At the range's bottom, the lit arc draws nothing, not even its round
// cap. A step up draws some.
- (void)testTheArcDrawsNothingAtTheBottom {
    QLMTestSeen = NO;
    CAShapeLayer *arc = (CAShapeLayer *)_knob.layers.movingLayers.firstObject;
    _knob.doubleValue = -80;
    QLMTestPumpWindow(_window);
    XCTAssertEqual(arc.lineCap, kCALineCapRound);
    XCTAssertEqual(QLMTestInk(arc), 0);
    _knob.doubleValue = -79.5;
    QLMTestPumpWindow(_window);
    XCTAssertGreaterThan(QLMTestInk(arc), 0);
}

// The middle of the box around the pointer's ink, in points from the
// knob's center, y down, as AppKit draws the view: where the knob differs
// from itself without the pointer. AppKit's own drawing, not the layers'
// flip rule, places it.
- (NSPoint)pointerInkAt:(double)decibels {
    _knob.doubleValue = decibels;
    QLMTestPumpWindow(_window);
    NSBitmapImageRep *(^draw)(void) = ^NSBitmapImageRep * {
        NSBitmapImageRep *bitmap = [self->_knob bitmapImageRepForCachingDisplayInRect:self->_knob.bounds];
        [self->_knob cacheDisplayInRect:self->_knob.bounds toBitmapImageRep:bitmap];
        return bitmap;
    };
    NSBitmapImageRep *with = draw();
    QLMTestPointer(_knob).hidden = YES;
    NSBitmapImageRep *without = draw();
    QLMTestPointer(_knob).hidden = NO;
    XCTAssertEqual(with.bitsPerPixel, 32);
    NSRect ink = QLMTestPixelBounds(with, without, ^BOOL(const uint8_t *u, const uint8_t *v) {
        for (int k = 0; k < 4; k++) {
            if (abs((int)u[k] - (int)v[k]) > 25) {
                return YES;
            }
        }
        return NO;
    });
    if (NSIsEmptyRect(ink)) {
        return NSMakePoint(NAN, NAN);
    }
    CGFloat scale = with.pixelsWide / _knob.bounds.size.width;
    return NSMakePoint(NSMidX(ink) / scale - NSMidX(_knob.bounds), NSMidY(ink) / scale - NSMidY(_knob.bounds));
}

// The bottom of the range points down and left, its middle up, and its
// top down and right.
- (void)testThePointerPointsWhereTheLevelIs {
    QLMTestSeen = NO;
    NSPoint bottom = [self pointerInkAt:-80];
    NSPoint middle = [self pointerInkAt:-55];
    NSPoint top = [self pointerInkAt:-30];
    XCTAssertLessThan(bottom.x, -10, @"%@", NSStringFromPoint(bottom));
    XCTAssertGreaterThan(bottom.y, 10, @"%@", NSStringFromPoint(bottom));
    XCTAssertEqualWithAccuracy(middle.x, 0, 2, @"%@", NSStringFromPoint(middle));
    XCTAssertLessThan(middle.y, -10, @"%@", NSStringFromPoint(middle));
    XCTAssertGreaterThan(top.x, 10, @"%@", NSStringFromPoint(top));
    XCTAssertGreaterThan(top.y, 10, @"%@", NSStringFromPoint(top));
}

@end
