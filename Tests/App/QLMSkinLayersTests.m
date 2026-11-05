#import <XCTest/XCTest.h>

#import "QLMSkinControls.h"
#import "QLMSkinDrawing.h"
#import "QLMSkinView.h"
#import "QLMTestSupport.h"

// Each skin's window and OSD as their layers composite them, against the
// same views drawn, as drawRect: drew every image before. At 2x, as on a
// Retina display, hostless. A composite that matches its drawing keeps the
// text over the material, the overlay over a disabled display, and every
// image right side up, at the reference size and stretched.
@interface QLMSkinLayersTests : XCTestCase
@end

static const CGFloat QLMTestScale = 2;

static void QLMTestEachLayer(CALayer *layer, void (^each)(CALayer *layer)) {
    each(layer);
    for (CALayer *sublayer in layer.sublayers) {
        QLMTestEachLayer(sublayer, each);
    }
}

static void QLMTestEachView(NSView *view, void (^each)(NSView *view)) {
    each(view);
    for (NSView *subview in view.subviews) {
        QLMTestEachView(subview, each);
    }
}

static NSBitmapImageRep *QLMTestBitmap(NSSize points) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                   pixelsWide:(NSInteger)(points.width * QLMTestScale)
                                                   pixelsHigh:(NSInteger)(points.height * QLMTestScale)
                                                bitsPerSample:8
                                              samplesPerPixel:4
                                                     hasAlpha:YES
                                                     isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace
                                                  bytesPerRow:0
                                                 bitsPerPixel:0];
}

// As a window shows it: each view's update, then each layer's drawing.
static NSBitmapImageRep *QLMTestComposite(NSView *view) {
    view.wantsLayer = YES;  // as every view in a window is
    QLMTestEachView(view, ^(NSView *each) {
        each.layer.contentsScale = QLMTestScale;
        each.needsDisplay = YES;
    });
    [view displayIfNeeded];
    QLMTestEachLayer(view.layer, ^(CALayer *layer) {
        [layer displayIfNeeded];
    });
    NSBitmapImageRep *bitmap = QLMTestBitmap(view.bounds.size);
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
    CGContextScaleCTM(cg, QLMTestScale, QLMTestScale);
    // Out of a window, AppKit puts no view's layer in its superview's, so
    // each renders in its place, in the views' order. A flipped view's
    // layer renders y down.
    CGFloat height = view.bounds.size.height;
    QLMTestEachView(view, ^(NSView *each) {
        if (each.hiddenOrHasHiddenAncestor) {
            return;
        }
        NSRect frame = [each convertRect:each.bounds toView:view];
        CGContextSaveGState(cg);
        CGContextTranslateCTM(cg, NSMinX(frame), height - NSMinY(frame));
        CGContextScaleCTM(cg, 1, -1);
        [each.layer renderInContext:cg];
        CGContextRestoreGState(cg);
    });
    return bitmap;
}

// Each view's drawRect:, in its place, in the views' order. It draws the
// material as drawRect: drew it before the layers, its shadows as they fall
// on the screen. TRAP: not displayRectIgnoringOpacity:, which renders the
// layers too.
static NSBitmapImageRep *QLMTestDrawn(NSView *view) {
    NSBitmapImageRep *bitmap = QLMTestBitmap(view.bounds.size);
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
    CGContextScaleCTM(cg, QLMTestScale, QLMTestScale);
    CGContextTranslateCTM(cg, 0, view.bounds.size.height);
    CGContextScaleCTM(cg, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = QLMSkinBitmapGraphicsContext(cg, QLMTestScale);
    QLMTestEachView(view, ^(NSView *each) {
        if (each.hiddenOrHasHiddenAncestor) {
            return;
        }
        NSRect frame = [each convertRect:each.bounds toView:view];
        CGContextSaveGState(cg);
        CGContextTranslateCTM(cg, NSMinX(frame), NSMinY(frame));
        [each drawRect:each.bounds];
        CGContextRestoreGState(cg);
    });
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

// The share of pixels within 2 levels in every channel.
static double QLMTestMatch(NSBitmapImageRep *a, NSBitmapImageRep *b) {
    if (a.pixelsWide != b.pixelsWide || a.pixelsHigh != b.pixelsHigh) {
        return 0;
    }
    const uint8_t *pa = a.bitmapData;
    const uint8_t *pb = b.bitmapData;
    NSInteger matched = 0;
    for (NSInteger y = 0; y < a.pixelsHigh; y++) {
        for (NSInteger x = 0; x < a.pixelsWide; x++) {
            const uint8_t *u = pa + y * a.bytesPerRow + x * 4;
            const uint8_t *v = pb + y * b.bytesPerRow + x * 4;
            BOOL same = YES;
            for (int k = 0; k < 4; k++) {
                same = same && abs((int)u[k] - (int)v[k]) <= 2;
            }
            matched += same;
        }
    }
    return (double)matched / (double)(a.pixelsWide * a.pixelsHigh);
}

typedef NS_ENUM(NSInteger, QLMTestLook) {
    QLMTestLookHovered,  // a group button and the knob under the pointer
    QLMTestLookPressed,  // a group button, Dim, and the knob pressed
    QLMTestLookDisabled,
};

static QLMSkinView *QLMTestWindowView(QLMSkin *skin, NSSize size, QLMTestLook look) {
    QLMSkinView *view = [[QLMSkinView alloc] initWithSkin:skin];
    view.frame = NSMakeRect(0, 0, size.width, size.height);
    view.knobMin = @"−80";
    view.knobMax = @"−30";
    view.status.text = @"6 ONLINE";
    view.status.lit = YES;
    [view setGroupTitles:@[@"MAIN 4X2", @"MAIN 2X2", @"MAIN 2X1"] prefixes:@[@"A", @"B", @"C"]];
    view.groupButtons[0].selected = YES;
    view.groupButtons[1].hovered = YES;
    view.muteButton.selected = YES;
    view.muteButton.ledLit = YES;
    view.display.caption = @"MAIN";
    view.display.level = @"−59.0";
    view.display.output = @"OUTPUT −59.0";
    view.display.max = @"MAX −30";
    view.knob.minValue = -80;
    view.knob.maxValue = -30;
    view.knob.doubleValue = -59;
    view.powerButton.title = @"Standby";
    if (look == QLMTestLookHovered) {
        view.knob.hovered = YES;
    }
    if (look == QLMTestLookPressed) {
        view.groupButtons[2].pressed = YES;
        view.dimButton.pressed = YES;
        view.knob.pressed = YES;
    }
    if (look == QLMTestLookDisabled) {
        NSArray<QLMSkinControl *> *others = @[view.muteButton, view.dimButton, view.knob, view.monitorsButton,
                                              view.powerButton];
        for (QLMSkinControl *control in [others arrayByAddingObjectsFromArray:view.groupButtons]) {
            control.enabled = NO;
        }
        view.status.enabled = NO;
        view.display.disabled = YES;
    }
    return view;
}

@implementation QLMSkinLayersTests

- (void)testEachSkinsWindowCompositesAsItDraws {
    for (NSString *name in @[@"modern", @"vintage", @"retro"]) {
        NSError *error = nil;
        QLMSkin *skin = [QLMSkin skinAtURL:[QLMBuiltInSkinsURL() URLByAppendingPathComponent:name] error:&error];
        XCTAssertNotNil(skin, @"%@", error);
        for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(640, 480)], [NSValue valueWithSize:NSMakeSize(900, 640)]]) {
            for (QLMTestLook look = QLMTestLookHovered; look <= QLMTestLookDisabled; look++) {
                QLMSkinView *view = QLMTestWindowView(skin, size.sizeValue, look);
                // The composite first: the drawing reads the scale it sets.
                NSBitmapImageRep *composite = QLMTestComposite(view);
                double match = QLMTestMatch(composite, QLMTestDrawn(view));
                XCTAssertGreaterThanOrEqual(match, 0.999, @"%@ at %@, look %ld", name, NSStringFromSize(size.sizeValue),
                                            (long)look);
            }
        }
    }
}

- (void)testEachSkinsOSDCompositesAsItDraws {
    for (NSString *name in @[@"modern", @"vintage", @"retro"]) {
        QLMSkin *skin = [QLMSkin skinAtURL:[QLMBuiltInSkinsURL() URLByAppendingPathComponent:name] error:NULL];
        QLMSkinOSDView *view = [[QLMSkinOSDView alloc] initWithSkin:skin];
        view.level = @"−59.0";
        view.title = @"Main monitors";
        view.fraction = 0.42;
        NSBitmapImageRep *composite = QLMTestComposite(view);
        double match = QLMTestMatch(composite, QLMTestDrawn(view));
        XCTAssertGreaterThanOrEqual(match, 0.999, @"%@", name);
    }
}

// The rows a modern button's face and shadow ink below and above it, in
// points, from an image of it at `scale`.
static void QLMTestShadowReach(QLMSkin *skin, CGFloat scale, CGFloat *below, CGFloat *above) {
    NSRect face = NSMakeRect(10, 20, 60, 20);
    CGImageRef image = QLMSkinRenderImage(NSMakeSize(80, 60), scale, ^{
        QLMSkinDrawStyle(skin, skin.button.style, QLMSkinStateNormal, face, NO);
    });
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSInteger first = -1;
    NSInteger last = -1;
    NSInteger x = (NSInteger)(NSMidX(face) * scale);
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        if ([bitmap colorAtX:x y:y].alphaComponent > 0.02) {
            first = first < 0 ? y : first;
            last = y;
        }
    }
    *below = (CGFloat)(last + 1) / scale - NSMaxY(face);
    *above = NSMinY(face) - (CGFloat)first / scale;
}

// A shadow falls as far, in points, at every scale, as on the screen: modern's
// buttons cast 1.5 points down with a 2 point blur.
- (void)testAShadowFallsInPointsAtEveryScale {
    QLMSkin *skin = [QLMSkin skinAtURL:QLMModernSkinURL() error:NULL];
    CGFloat below1, above1, below2, above2;
    QLMTestShadowReach(skin, 1, &below1, &above1);
    QLMTestShadowReach(skin, 2, &below2, &above2);
    XCTAssertEqualWithAccuracy(below1, below2, 1);
    XCTAssertEqualWithAccuracy(above1, above2, 1);
    XCTAssertGreaterThan(below2, above2 + 1);
    XCTAssertGreaterThan(below2, 2.5);
}

@end
