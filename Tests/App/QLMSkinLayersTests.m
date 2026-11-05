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

// Each view's update, then each layer's drawing, where they are due, as a
// window shows them. Out of a window, a content layer draws whole, so only
// a window shows what a partial redraw leaves.
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

// Each view's reference drawing, in its place, in the views' order: each
// material drawn itself, then the content, its shadows as they fall on the
// screen.
static NSBitmapImageRep *QLMTestDrawn(NSView *view) {
    return QLMTestDrawFlipped(view.bounds.size, ^{
        CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
        QLMTestEachView(view, ^(NSView *each) {
            if (each.hiddenOrHasHiddenAncestor || ![each respondsToSelector:@selector(layers)]) {
                return;
            }
            NSRect frame = [each convertRect:each.bounds toView:view];
            CGContextSaveGState(cg);
            CGContextTranslateCTM(cg, NSMinX(frame), NSMinY(frame));
            [[(id)each layers] drawReference:each.bounds];
            CGContextRestoreGState(cg);
        });
    });
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
@property (nonatomic) NSRect dirty;  // the last content draw's
@end

@implementation QLMTestSpyDisplay
- (void)updateLayer {
    self.updates++;
    [super updateLayer];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    self.dirty = dirtyRect;
    [super drawSkinContent:dirtyRect];
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

@implementation QLMSkinLayersTests

- (void)testEachSkinsWindowCompositesAsItDraws {
    for (NSString *name in QLMBuiltInSkinNames()) {
        QLMSkin *skin = QLMBuiltInSkin(name);
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
    for (NSString *name in QLMBuiltInSkinNames()) {
        QLMSkin *skin = QLMBuiltInSkin(name);
        QLMSkinOSDView *view = [[QLMSkinOSDView alloc] initWithSkin:skin];
        view.level = @"−59.0";
        view.title = @"Main monitors";
        view.fraction = 0.42;
        NSBitmapImageRep *composite = QLMTestComposite(view);
        double match = QLMTestMatch(composite, QLMTestDrawn(view));
        XCTAssertGreaterThanOrEqual(match, 0.999, @"%@", name);
    }
}

// Whether what `draw` draws, in a bitmap `size` points big at `scale`,
// inks only inside `rect`'s pixels, every one of which a redraw covers.
static BOOL QLMTestInksInside(NSSize size, CGFloat scale, NSRect rect, void (^draw)(void)) {
    NSBitmapImageRep *bitmap = QLMTestDrawFlippedAtScale(size, scale, draw);
    NSRect ink = QLMTestPixelBounds(bitmap, bitmap, ^BOOL(const uint8_t *u, const uint8_t *v) {
        return u[3] > 0;
    });
    NSRect pixels = NSIntegralRect(
        NSMakeRect(rect.origin.x * scale, rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale));
    return NSIsEmptyRect(ink) || NSContainsRect(pixels, ink);
}

// A text's change redraws its slot's ink alone, so a slot draws nothing
// past it: not a fallback font's glyphs, nor stacked combining marks, at
// the reference size and scaled up, at 1x and 2x. Otherwise a change would
// leave some of the old text behind. The panel's own slots, the ones that
// change and the ones that don't, take the same rule.
- (void)testASlotsTextInksInsideWhatItsChangeRedraws {
    NSArray<NSString *> *names = @[@"MAIN 4X2 WITH A LONG NAME", @"监听 4X2", @"MAIN 4X2 \u0301\u0301\u0301"];
    NSDictionary<NSString *, NSDictionary<NSString *, NSArray<NSString *> *> *> *elements = @{
        @"display": @{
            @"caption": names, @"level": @[@"−88.8", @"−100.0"], @"unit": @[@"dB"], @"output": @[@"OUTPUT −100.0", @"MUTED"],
            @"max": @[@"MAX −88.8"],
        },
        @"groups": @{@"message": @[@"Main.sam has no groups", @"监听.sam \u0301\u0301"], @"groupsTitle": @[@"LISTENING SETUP"]},
        @"knob": @{@"min": @[@"−100.5"], @"max": @[@"−88.8"], @"caption": @[@"VOLUME"]},
        @"nameplate": @{@"logo": @[@"qlm."]},
    };
    NSDictionary<NSString *, NSArray<NSString *> *> *osd = @{
        @"level": @[@"−100.0"], @"unit": @[@"dB"], @"title": names, @"subtitle": @[@"Muted · Dimmed"],
    };
    for (NSString *name in QLMBuiltInSkinNames()) {
        QLMSkin *skin = QLMBuiltInSkin(name);
        for (NSNumber *scale in @[@1, @2]) {
            for (NSString *elementName in elements) {
                QLMSkinElement *element = [skin element:elementName];
                for (NSNumber *grow in @[@1, @1.7]) {
                    // Whole points, so the bitmap lies on the pixels the drawing does.
                    CGSize size = CGSizeMake(round(element.frame.size.width * grow.doubleValue),
                                             round(element.frame.size.height * grow.doubleValue));
                    for (NSString *slotName in elements[elementName]) {
                        QLMSkinTextSlot *slot = element.text[slotName];
                        if (slot == nil) {
                            continue;
                        }
                        NSRect frame = QLMSkinSlotFrame(element, slot, size);
                        CGFloat slotScale = QLMSkinSlotScale(element, slot, size);
                        for (NSString *text in elements[elementName][slotName]) {
                            XCTAssertTrue(QLMTestInksInside(size, scale.doubleValue, QLMSkinSlotInk(slot, frame, slotScale), ^{
                                QLMSkinDrawSlotInInk(text, slot, frame, slotScale, YES, 1);
                            }), @"%@ %@ %@ \"%@\" at %@, %@x", name, elementName, slotName, text, grow, scale);
                        }
                    }
                }
            }
            for (NSString *slotName in osd) {
                QLMSkinTextSlot *slot = skin.osd.text[slotName];
                for (NSString *text in osd[slotName]) {
                    XCTAssertTrue(QLMTestInksInside(skin.osd.frame.size, scale.doubleValue, QLMSkinSlotInk(slot, slot.frame, 1), ^{
                        QLMSkinDrawSlotInInk(text, slot, slot.frame, 1, YES, 1);
                    }), @"%@ OSD %@ \"%@\", %@x", name, slotName, text, scale);
                }
            }
        }
    }
}

// In a window, a change that redraws only a slot leaves none of the old
// text: Core Animation clears the slot's rect before the content draws.
// A narrow level drawn over a wide one comes out as a whole draw of it.
- (void)testAPartialRedrawInAWindowLeavesNoOldText {
    QLMSkin *skin = QLMBuiltInSkin(@"retro");
    NSMutableArray<NSBitmapImageRep *> *renders = [NSMutableArray array];
    for (NSNumber *partial in @[@YES, @NO]) {
        NSWindow *window = QLMTestOffscreenWindow(NSMakeSize(400, 200));
        QLMTestSpyDisplay *display = [[QLMTestSpyDisplay alloc] initWithSkin:skin];
        display.frame = NSMakeRect(10, 10, 356, 132);
        [window.contentView addSubview:display];
        // A window's first changes after it shows redraw whole.
        NSArray<NSString *> *levels = partial.boolValue ? @[@"−88.8", @"1.0", @"−88.8", @"1.0"] : @[@"1.0"];
        for (NSString *level in levels) {
            display.level = level;
            QLMTestPumpWindow(window);
        }
        if (partial.boolValue) {
            XCTAssertLessThan(display.dirty.size.width, display.bounds.size.width, @"%@", NSStringFromRect(display.dirty));
        }
        CALayer *content = display.layer.sublayers.lastObject;
        NSBitmapImageRep *bitmap = QLMTestBitmapAtScale(content.bounds.size, window.backingScaleFactor);
        CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
        CGContextScaleCTM(cg, window.backingScaleFactor, window.backingScaleFactor);
        [content renderInContext:cg];
        [renders addObject:bitmap];
        [window close];
    }
    XCTAssertGreaterThanOrEqual(QLMTestMatch(renders[0], renders[1]), 0.9999);
}

// In a window, a size change alone sets a layered view's materials again,
// and a move that keeps its pixels sets nothing. A move off them draws
// again: an odd change of the window's height moves the knob half a point,
// half a pixel at 1x. TRAP: out of a window, AppKit keeps a view's layer
// due for display, so only a window shows it.
- (void)testASizeChangeInAWindowSetsTheMaterialsAgain {
    QLMSkin *skin = QLMBuiltInSkin(@"retro");
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
        view.frameOrigin = NSMakePoint(20, 10 + 0.5 / window.backingScaleFactor);
        QLMTestPumpWindow(window);
        XCTAssertEqual([(id)view updates], 1, @"%@ moved half a pixel", view);
        [(id)view setUpdates:0];
        view.frameSize = NSMakeSize(300, 160);
        QLMTestPumpWindow(window);
        XCTAssertEqual([(id)view updates], 1, @"%@ grew", view);
        QLMTestAssertMaterialsFollow(self, view, @"grown");
        // Hidden, it waits to be shown.
        view.hidden = YES;
        view.frameSize = NSMakeSize(250, 140);
        QLMTestPumpWindow(window);
        view.hidden = NO;
        QLMTestPumpWindow(window);
        QLMTestAssertMaterialsFollow(self, view, @"grown while hidden");
        [window close];
    }
}

// A size change alone sets every material again, as a drag of the
// window's corner makes. Each material's layer then sits where the view's
// state puts it, and the grids' buttons take the layout's cells: within a
// grid, each the same width, with the grid's gap between.
- (void)testEachMaterialFollowsItsViewsSize {
    for (NSString *name in QLMBuiltInSkinNames()) {
        QLMSkin *skin = QLMBuiltInSkin(name);
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

// A group's button, Mute's, or Dim's, with its title and its LED, if it
// has one, or with neither.
static QLMSkinButtonView *QLMTestButton(QLMSkin *skin, NSSize size, NSUInteger kind, BOOL titled) {
    QLMSkinButtonView *button = [[QLMSkinButtonView alloc] initWithSkin:skin];
    button.frame = (NSRect){NSZeroPoint, size};
    button.layer.contentsScale = QLMTestScale;
    NSArray<NSString *> *titles = @[@"MAIN 2X2", @"MUTE", @"DIM −20"];
    button.title = titled ? titles[kind] : @"";
    button.prefix = titled && kind == 0 ? @"B" : nil;
    button.showsLED = titled && kind == 1;
    return button;
}

static uint8_t QLMTestMostAlpha(NSBitmapImageRep *bitmap) {
    uint8_t most = 0;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        const uint8_t *row = bitmap.bitmapData + y * bitmap.bytesPerRow;
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            most = MAX(most, row[x * 4 + 3]);
        }
    }
    return most;
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
    for (NSString *name in QLMBuiltInSkinNames()) {
        QLMSkin *skin = QLMBuiltInSkin(name);
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
                        QLMSkinButtonView *button = QLMTestButton(skin, sizes[kind], kind, labelled.boolValue);
                        button.ledLit = YES;
                        button.selected = states[s].selected;
                        button.enabled = states[s].enabled;
                        button.pressed = states[s].pressed;
                        button.hovered = states[s].hovered;
                        [bitmaps addObject:QLMTestDrawn(button)];
                    }
                    uint8_t most = QLMTestMostAlpha(bitmaps[0]);
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
