#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>

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
// Each view's update, then each layer's drawing, where they are due.
static void QLMTestDisplayIfNeeded(NSView *view) {
    [view displayIfNeeded];
    QLMTestEachView(view, ^(NSView *each) {
        QLMTestEachLayer(each.layer, ^(CALayer *layer) {
            [layer displayIfNeeded];
        });
    });
}

static NSBitmapImageRep *QLMTestComposite(NSView *view) {
    view.wantsLayer = YES;  // as every view in a window is
    QLMTestEachView(view, ^(NSView *each) {
        each.layer.contentsScale = QLMTestScale;
        each.needsDisplay = YES;
    });
    QLMTestDisplayIfNeeded(view);
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

// How often a window has had a view set its layers since the last reset.
@interface QLMTestSpyButton : QLMSkinButtonView
@property (nonatomic) NSInteger updates;
@end

@implementation QLMTestSpyButton
- (void)updateLayer {
    self.updates++;
    [super updateLayer];
}
@end

@interface QLMTestSpyDisplay : QLMSkinDisplayView
@property (nonatomic) NSInteger updates;
@end

@implementation QLMTestSpyDisplay
- (void)updateLayer {
    self.updates++;
    [super updateLayer];
}
@end

// Each material's layer sits where the view's state puts it.
static void QLMTestAssertMaterialsFollow(XCTestCase *test, NSView *view, NSString *at) {
    QLMSkinLayers *layers = [(id)view layers];
    NSArray<QLMSkinMaterial *> *materials = [(id<QLMSkinLayered>)view skinMaterials:layers];
    NSArray<CALayer *> *sublayers = view.layer.sublayers;
    if (sublayers.count <= materials.count) {
        [test recordIssue:[[XCTIssue alloc] initWithType:XCTIssueTypeAssertionFailure
                                      compactDescription:[NSString stringWithFormat:@"%@, %@ has no material layers", at, view]]];
        return;
    }
    for (NSUInteger i = 0; i < materials.count; i++) {
        NSRect want = [view convertRectToLayer:materials[i].frame];
        if (!NSEqualRects(sublayers[i].frame, want)) {
            NSString *issue = [NSString stringWithFormat:@"%@, %@ material %lu: %@, not %@", at, view, (unsigned long)i,
                                                         NSStringFromRect(sublayers[i].frame), NSStringFromRect(want)];
            [test recordIssue:[[XCTIssue alloc] initWithType:XCTIssueTypeAssertionFailure compactDescription:issue]];
        }
    }
}

// What a window on the screen does at its next frame. TRAP: here, a
// window's displayIfNeeded draws nothing. The transaction's commit draws.
static void QLMTestPumpWindow(NSWindow *window) {
    [window displayIfNeeded];
    [CATransaction flush];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

// An offscreen window, as the screen's: it draws without being shown.
static NSWindow *QLMTestOffscreenWindow(NSSize size) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:(NSRect){NSZeroPoint, size} styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView.wantsLayer = YES;  // as on the screen
    return window;
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

// In a window, a size change alone sets a layered view's materials again,
// and a move that keeps its pixels sets nothing. TRAP: out of a window,
// AppKit keeps a view's layer due for display, so only a window shows it.
- (void)testASizeChangeInAWindowSetsTheMaterialsAgain {
    QLMSkin *skin = [QLMSkin skinAtURL:[QLMBuiltInSkinsURL() URLByAppendingPathComponent:@"retro"] error:NULL];
    QLMTestSpyButton *button = [[QLMTestSpyButton alloc] initWithSkin:skin];
    button.title = @"MUTE";
    QLMTestSpyDisplay *display = [[QLMTestSpyDisplay alloc] initWithSkin:skin];
    display.level = @"−40.0";
    for (NSView *view in @[button, display]) {
        NSWindow *window = QLMTestOffscreenWindow(NSMakeSize(800, 400));
        view.frame = NSMakeRect(10, 10, 200, 120);
        [window.contentView addSubview:view];
        QLMTestPumpWindow(window);
        [(id)view setUpdates:0];
        view.frameOrigin = NSMakePoint(20, 10);
        QLMTestPumpWindow(window);
        XCTAssertEqual([(id)view updates], 0, @"%@ moved", view);
        view.frameSize = NSMakeSize(300, 160);
        QLMTestPumpWindow(window);
        XCTAssertEqual([(id)view updates], 1, @"%@ grew", view);
        QLMTestAssertMaterialsFollow(self, view, @"grown");
        [window close];
    }
}

// A size change alone sets every material again, as a drag of the
// window's corner makes. Each material's layer then sits where the view's
// state puts it, and the grids' buttons take the layout's cells: within a
// grid, each the same width, with the grid's gap between.
- (void)testEachMaterialFollowsItsViewsSize {
    for (NSString *name in @[@"modern", @"vintage", @"retro"]) {
        QLMSkin *skin = [QLMSkin skinAtURL:[QLMBuiltInSkinsURL() URLByAppendingPathComponent:name] error:NULL];
        QLMSkinView *view = QLMTestWindowView(skin, skin.windowSize, QLMTestLookHovered);
        // Not deferred, as QLMSkinHostWindow's is, so it draws unshown.
        NSWindow *window = QLMTestOffscreenWindow(skin.windowSize);
        QLMSkinHost(window, view);
        QLMTestPumpWindow(window);
        for (NSValue *size in @[[NSValue valueWithSize:skin.windowSize], [NSValue valueWithSize:NSMakeSize(900, 640)],
                                [NSValue valueWithSize:NSMakeSize(1200, 900)]]) {
            [window setContentSize:size.sizeValue];
            QLMTestPumpWindow(window);
            NSString *at = [NSString stringWithFormat:@"%@ at %@", name, NSStringFromSize(size.sizeValue)];
            XCTAssertTrue(NSEqualSizes(view.bounds.size, size.sizeValue), @"%@", at);
            QLMTestEachView(view, ^(NSView *each) {
                if ([each respondsToSelector:@selector(layers)] && !each.hiddenOrHasHiddenAncestor) {
                    QLMTestAssertMaterialsFollow(self, each, at);
                }
            });
            QLMSkinLayout *layout = view.skinLayout;
            NSArray<NSArray<QLMSkinButtonView *> *> *grids = @[view.groupButtons, @[view.muteButton, view.dimButton]];
            NSArray<NSString *> *elements = @[@"groups", @"toggles"];
            for (NSUInteger g = 0; g < grids.count; g++) {
                QLMSkinElement *element = [skin element:elements[g]];
                NSArray<NSValue *> *cells = [layout cellsOfElement:elements[g]];
                NSRect grid = [layout frameOfElement:elements[g]];
                for (NSUInteger i = 0; i < grids[g].count; i++) {
                    NSRect frame = grids[g][i].frame;
                    XCTAssertTrue(NSEqualRects(frame, cells[i].rectValue), @"%@, %@ %lu", at, elements[g], (unsigned long)i);
                    XCTAssertEqualWithAccuracy(frame.size.width, cells[0].rectValue.size.width, 0.001, @"%@", at);
                    NSInteger column = (NSInteger)i % element.columns;
                    if (column > 0) {
                        XCTAssertEqualWithAccuracy(NSMinX(frame) - NSMaxX(grids[g][i - 1].frame), element.gap.width, 0.001,
                                                   @"%@, %@ %lu", at, elements[g], (unsigned long)i);
                    }
                    if (column == element.columns - 1) {
                        XCTAssertEqualWithAccuracy(NSMaxX(frame), NSMaxX(grid), 0.001, @"%@, %@ %lu", at, elements[g],
                                                   (unsigned long)i);
                    }
                }
            }
        }
        [window close];
    }
}

// The pixels' bounds where `pass` holds for a pixel of `a` and of `b`.
static NSRect QLMTestPixelBounds(NSBitmapImageRep *a, NSBitmapImageRep *b, BOOL (^pass)(const uint8_t *u, const uint8_t *v)) {
    NSInteger minX = NSIntegerMax, minY = NSIntegerMax, maxX = -1, maxY = -1;
    for (NSInteger y = 0; y < a.pixelsHigh; y++) {
        for (NSInteger x = 0; x < a.pixelsWide; x++) {
            if (pass(a.bitmapData + y * a.bytesPerRow + x * 4, b.bitmapData + y * b.bytesPerRow + x * 4)) {
                minX = MIN(minX, x);
                minY = MIN(minY, y);
                maxX = MAX(maxX, x);
                maxY = MAX(maxY, y);
            }
        }
    }
    return maxX < 0 ? NSZeroRect : NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

// A group's button, Mute's, or Dim's, with its title or none, and with its
// LED, if it has one, or none.
static QLMSkinButtonView *QLMTestButton(QLMSkin *skin, NSSize size, NSUInteger kind, BOOL titled, BOOL led) {
    QLMSkinButtonView *button = [[QLMSkinButtonView alloc] initWithSkin:skin];
    button.frame = (NSRect){NSZeroPoint, size};
    button.layer.contentsScale = QLMTestScale;
    NSArray<NSString *> *titles = @[@"MAIN 2X2", @"MUTE", @"DIM −20"];
    button.title = titled ? titles[kind] : @"";
    button.prefix = titled && kind == 0 ? @"B" : nil;
    button.showsLED = led && kind == 1;
    return button;
}

// The bounds of what differs between two drawings by more than `levels`.
static NSRect QLMTestDifference(NSBitmapImageRep *a, NSBitmapImageRep *b, int levels) {
    return QLMTestPixelBounds(a, b, ^BOOL(const uint8_t *u, const uint8_t *v) {
        int most = 0;
        for (int k = 0; k < 3; k++) {
            most = MAX(most, abs((int)u[k] - (int)v[k]));
        }
        return most > levels;
    });
}

// The label's ink centers on the button's face, its capitals on the face's
// height, within a pixel at 2x: in every state, in each skin, at the
// reference size and two larger. The face is where the material is at
// least half its most opaque, so a shadow below it counts for nothing. A
// lit LED with no glow inks its dot. A disabled LED is too faint to find,
// so a disabled title must end where its enabled one does.
- (void)testEachButtonsLabelCentersOnItsFace {
    typedef struct {
        BOOL selected, enabled, pressed, hovered;
    } QLMTestState;
    QLMTestState states[] = {{NO, YES, NO, NO}, {NO, YES, NO, YES}, {NO, YES, YES, NO}, {YES, YES, NO, NO},
                             {YES, YES, NO, YES}, {YES, YES, YES, NO}, {NO, NO, NO, NO}, {YES, NO, NO, NO}};
    size_t count = sizeof(states) / sizeof(states[0]);
    for (NSString *name in @[@"modern", @"vintage", @"retro"]) {
        QLMSkin *skin = [QLMSkin skinAtURL:[QLMBuiltInSkinsURL() URLByAppendingPathComponent:name] error:NULL];
        [skin.led setValue:@0 forKey:@"glow"];
        for (NSValue *window in @[[NSValue valueWithSize:skin.windowSize], [NSValue valueWithSize:NSMakeSize(900, 640)],
                                  [NSValue valueWithSize:NSMakeSize(1200, 900)]]) {
            QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:skin size:window.sizeValue];
            NSArray<NSValue *> *toggles = [layout cellsOfElement:@"toggles"];
            NSSize sizes[] = {[layout cellsOfElement:@"groups"][0].rectValue.size, toggles[0].rectValue.size,
                              toggles[1].rectValue.size};
            for (NSUInteger kind = 0; kind < 3; kind++) {
                NSMutableArray<NSValue *> *inks = [NSMutableArray array];
                for (size_t s = 0; s < count; s++) {
                    // The face alone, then with its label.
                    NSMutableArray<NSBitmapImageRep *> *bitmaps = [NSMutableArray array];
                    for (NSNumber *labelled in @[@NO, @YES]) {
                        QLMSkinButtonView *button = QLMTestButton(skin, sizes[kind], kind, labelled.boolValue,
                                                                  labelled.boolValue);
                        button.ledLit = YES;
                        button.selected = states[s].selected;
                        button.enabled = states[s].enabled;
                        button.pressed = states[s].pressed;
                        button.hovered = states[s].hovered;
                        [bitmaps addObject:QLMTestDrawn(button)];
                    }
                    __block uint8_t most = 0;
                    (void)QLMTestPixelBounds(bitmaps[0], bitmaps[0], ^BOOL(const uint8_t *u, const uint8_t *v) {
                        most = MAX(most, u[3]);
                        return NO;
                    });
                    NSRect face = QLMTestPixelBounds(bitmaps[0], bitmaps[0], ^BOOL(const uint8_t *u, const uint8_t *v) {
                        return u[3] * 2 >= most;
                    });
                    NSRect ink = QLMTestDifference(bitmaps[0], bitmaps[1], 40);
                    [inks addObject:[NSValue valueWithRect:ink]];
                    NSString *at = [NSString stringWithFormat:@"%@ at %@, button %lu, state %zu: face %@, ink %@", name,
                                                              NSStringFromSize(window.sizeValue), (unsigned long)kind, s,
                                                              NSStringFromRect(face), NSStringFromRect(ink)];
                    XCTAssertGreaterThan(ink.size.width, 0, @"%@", at);
                    if (kind == 1 && !states[s].enabled) {
                        NSRect enabled = inks[states[s].selected ? 3 : 0].rectValue;
                        XCTAssertEqualWithAccuracy(NSMaxX(ink), NSMaxX(enabled), 1, @"%@", at);
                        XCTAssertEqualWithAccuracy(NSMidY(ink), NSMidY(face), 1, @"%@", at);
                        continue;
                    }
                    XCTAssertEqualWithAccuracy(NSMidX(ink), NSMidX(face), 1, @"%@", at);
                    XCTAssertEqualWithAccuracy(NSMidY(ink), NSMidY(face), 1, @"%@", at);
                }
            }
        }
    }
}

@end
