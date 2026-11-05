#import <XCTest/XCTest.h>

#import "QLMSkinControls.h"
#import "QLMSkinDrawing.h"
#import "QLMSkinTestBitmaps.h"
#import "QLMSkinView.h"
#import "QLMTestSupport.h"

// Each skin's window and OSD as their layers composite them, against the
// same views drawn, as drawRect: drew every image before. At 2x, as on a
// Retina display, hostless. A composite that matches its drawing keeps the
// text over the material, the overlay over a disabled display, and every
// image right side up, at the reference size and stretched.
@interface QLMSkinLayersTests : XCTestCase
@end

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

// As a window shows it: each view's update, then each layer's drawing.
// Out of a window, this view tree's content layers came back drawn whole
// at the render, so a test here can't show what a partial redraw left. A
// standalone layer's render showed its partial state.
static NSBitmapImageRep *QLMTestComposite(NSView *view) {
    view.wantsLayer = YES;  // as every view in a window is
    QLMTestEachView(view, ^(NSView *each) {
        each.layer.contentsScale = QLMTestScale;
        each.needsDisplay = YES;
    });
    [view displayIfNeeded];
    QLMTestEachView(view, ^(NSView *each) {
        QLMTestEachLayer(each.layer, ^(CALayer *layer) {
            [layer displayIfNeeded];
        });
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

// Each view's reference drawing, in its place, in the views' order. It
// draws the material as drawRect: drew it before the layers, its shadows
// as they fall on the screen.
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
        if ([each respondsToSelector:@selector(layers)]) {
            [[(id)each layers] drawReference:each.bounds];
        }
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

// The ink outside `rect`, in pixels, of what `draw` draws in a bitmap
// `size` points big at `scale`.
static NSInteger QLMTestInkOutside(NSSize size, CGFloat scale, NSRect rect, void (^draw)(void)) {
    NSBitmapImageRep *bitmap = QLMTestDrawFlippedAtScale(size, scale, draw);
    // A redraw covers every pixel the rect touches.
    NSRect pixels = NSIntegralRect(
        NSMakeRect(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale));
    NSInteger outside = 0;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            if (!NSPointInRect(NSMakePoint(x + 0.5, y + 0.5), pixels) && [bitmap colorAtX:x y:y].alphaComponent > 0) {
                outside++;
            }
        }
    }
    return outside;
}

// A text's change redraws its slot's ink alone, so a slot draws nothing
// past it: not a fallback font's glyphs, nor stacked combining marks, at
// the reference size and scaled up, at 1x and 2x. Otherwise a change would
// leave some of the old text behind.
- (void)testASlotsTextInksInsideWhatItsChangeRedraws {
    NSArray<NSString *> *names = @[@"MAIN 4X2 WITH A LONG NAME", @"监听 4X2", @"MAIN 4X2 \u0301\u0301\u0301"];
    NSDictionary<NSString *, NSArray<NSString *> *> *display = @{
        @"caption": names, @"level": @[@"−88.8", @"−100.0"], @"unit": @[@"dB"], @"output": @[@"OUTPUT −100.0", @"MUTED"],
        @"max": @[@"MAX −88.8"],
    };
    NSDictionary<NSString *, NSArray<NSString *> *> *osd = @{
        @"level": @[@"−100.0"], @"unit": @[@"dB"], @"title": names, @"subtitle": @[@"Muted · Dimmed"],
    };
    for (NSString *name in @[@"modern", @"vintage", @"retro"]) {
        QLMSkin *skin = [QLMSkin skinAtURL:[QLMBuiltInSkinsURL() URLByAppendingPathComponent:name] error:NULL];
        QLMSkinElement *element = [skin element:@"display"];
        for (NSNumber *scale in @[@1, @2]) {
            for (NSNumber *grow in @[@1, @1.7]) {
                // Whole points, so the bitmap lies on the pixels the drawing does.
                CGSize size = CGSizeMake(round(element.frame.size.width * grow.doubleValue),
                                         round(element.frame.size.height * grow.doubleValue));
                for (NSString *slotName in display) {
                    QLMSkinTextSlot *slot = element.text[slotName];
                    NSRect frame = QLMSkinSlotFrame(element, slot, size);
                    CGFloat slotScale = QLMSkinSlotScale(element, slot, size);
                    for (NSString *text in display[slotName]) {
                        NSInteger outside = QLMTestInkOutside(size, scale.doubleValue, QLMSkinSlotInk(slot, frame, slotScale), ^{
                            QLMSkinDrawSlotInInk(text, slot, frame, slotScale, YES, 1);
                        });
                        XCTAssertEqual(outside, 0, @"%@ display %@ \"%@\" at %@, %@x", name, slotName, text, grow, scale);
                    }
                }
            }
            for (NSString *slotName in osd) {
                QLMSkinTextSlot *slot = skin.osd.text[slotName];
                for (NSString *text in osd[slotName]) {
                    NSInteger outside = QLMTestInkOutside(skin.osd.frame.size, scale.doubleValue, QLMSkinSlotInk(slot, slot.frame, 1), ^{
                        QLMSkinDrawSlotInInk(text, slot, slot.frame, 1, YES, 1);
                    });
                    XCTAssertEqual(outside, 0, @"%@ OSD %@ \"%@\", %@x", name, slotName, text, scale);
                }
            }
        }
    }
}

@end
