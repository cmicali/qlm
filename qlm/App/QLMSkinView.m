#import "QLMSkinView.h"

#include "QLMCommands.h"
#import "QLMFormat.h"
#import "QLMSkinDrawing.h"
#import "QLMSkinLayers.h"

// The panel's own words.
static NSString *const QLMSkinLogo = @"qlm.";
static NSString *const QLMSkinGroupsTitle = @"LISTENING SETUP";
static NSString *const QLMSkinKnobCaption = @"VOLUME";

@interface QLMSkinView ()
- (NSArray<QLMSkinMaterial *> *)panelMaterials:(QLMSkinLayers *)layers;
- (void)drawPanel:(NSRect)dirtyRect;
@end

// The panel's material, markings, and text, under every element: a view
// of its own, since a layered view is a leaf and the skin view hosts the
// elements.
@interface QLMSkinPanelView : QLMSkinLayerView
@property (nonatomic, weak) QLMSkinView *owner;
@end

@implementation QLMSkinPanelView

// A click on the panel is the skin view's, which moves the window.
- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    return [self.owner panelMaterials:layers];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    [self.owner drawPanel:dirtyRect];
}

@end

@implementation QLMSkinView {
    QLMSkinPanelView *_panel;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSMakeRect(0, 0, skin.windowSize.width, skin.windowSize.height)];
    if (self) {
        _skin = skin;
        _panel = [[QLMSkinPanelView alloc] initWithFrame:self.bounds];
        _panel.owner = self;
        [self addSubview:_panel];
        _status = [[QLMSkinStatusView alloc] initWithSkin:skin];
        [self addSubview:_status];

        NSUInteger cells = QLMSkinGroupButtonCount(skin);
        NSMutableArray<QLMSkinButtonView *> *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < cells; i++) {
            QLMSkinButtonView *button = [[QLMSkinButtonView alloc] initWithSkin:skin];
            button.hidden = YES;
            [self addSubview:button];
            [buttons addObject:button];
        }
        _groupButtons = buttons;

        _display = [[QLMSkinDisplayView alloc] initWithSkin:skin];
        [self addSubview:_display];

        _muteButton = [[QLMSkinButtonView alloc] initWithSkin:skin];
        _muteButton.showsLED = YES;
        _muteButton.title = @"MUTE";
        [self addSubview:_muteButton];
        _dimButton = [[QLMSkinButtonView alloc] initWithSkin:skin];
        _dimButton.title = [@"DIM " stringByAppendingString:QLMDecibelsNumberText(-QLMDimDecibels, 0)];
        [self addSubview:_dimButton];

        _knob = [[QLMKnobControl alloc] initWithSkin:skin];
        [self addSubview:_knob];

        QLMSkinElement *footer = [skin element:@"footer"];
        _monitorsButton = [[QLMSkinTextButton alloc] initWithSkin:skin slot:footer.text[@"monitors"]
                                                           symbol:footer.symbols[@"monitors"]];
        _monitorsButton.title = @"Monitors";
        [self addSubview:_monitorsButton];
        _powerButton = [[QLMSkinTextButton alloc] initWithSkin:skin slot:footer.text[@"power"]
                                                        symbol:footer.symbols[@"power"]];
        [self addSubview:_powerButton];

        [self applyLayout];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self applyLayout];
}

// TRAP: NSView's init sets the frame, before the subviews exist.
- (void)applyLayout {
    if (self.knob == nil) {
        return;
    }
    QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:self.skin size:self.bounds.size];
    _skinLayout = layout;
    _panel.frame = self.bounds;
    _panel.needsDisplay = YES;
    self.status.frame = [layout frameOfElement:@"status"];

    NSArray<NSValue *> *cells = [layout cellsOfElement:@"groups"];
    for (NSUInteger i = 0; i < self.groupButtons.count; i++) {
        self.groupButtons[i].frame = cells[i].rectValue;
    }

    self.display.frame = [layout frameOfElement:@"display"];

    NSArray<NSValue *> *toggles = [layout cellsOfElement:@"toggles"];
    self.muteButton.frame = toggles[0].rectValue;
    self.dimButton.frame = toggles[1].rectValue;

    self.knob.frame = [layout frameOfElement:@"knob"];

    NSRect footer = [layout frameOfElement:@"footer"];
    NSRect monitors = [layout frameOfSlot:@"monitors" inElement:@"footer"];
    NSRect power = [layout frameOfSlot:@"power" inElement:@"footer"];
    self.monitorsButton.frame = NSOffsetRect(monitors, footer.origin.x, footer.origin.y);
    self.powerButton.frame = NSOffsetRect(power, footer.origin.x, footer.origin.y);
}

- (void)setGroupTitles:(NSArray<NSString *> *)titles prefixes:(NSArray<NSString *> *)prefixes {
    NSUInteger shown = MIN(titles.count, self.groupButtons.count);
    for (NSUInteger i = 0; i < self.groupButtons.count; i++) {
        QLMSkinButtonView *button = self.groupButtons[i];
        button.hidden = i >= shown;
        button.title = i < shown ? titles[i] : @"";
        button.prefix = i < shown ? prefixes[i] : nil;
    }
}

#pragma mark - The panel's text

// Redraws only the slot's frame, and only on a change.
- (void)setText:(NSString *)text of:(NSString *__strong *)ivar slot:(NSString *)slot inElement:(NSString *)element {
    if (QLMSkinSameText(text, *ivar)) {
        return;
    }
    *ivar = [text copy];
    [_panel.layers setNeedsDisplayInRect:[self frameOfSlot:slot inElement:element]];
}

- (void)setGroupsMessage:(NSString *)groupsMessage {
    [self setText:groupsMessage of:&_groupsMessage slot:@"message" inElement:@"groups"];
}

- (void)setKnobMin:(NSString *)knobMin {
    [self setText:knobMin of:&_knobMin slot:@"min" inElement:@"knob"];
}

- (void)setKnobMax:(NSString *)knobMax {
    [self setText:knobMax of:&_knobMax slot:@"max" inElement:@"knob"];
}

#pragma mark - Drawing

// A slot's frame in the window.
- (NSRect)frameOfSlot:(NSString *)slot inElement:(NSString *)element {
    NSRect frame = [self.skinLayout frameOfElement:element];
    return NSOffsetRect([self.skinLayout frameOfSlot:slot inElement:element], frame.origin.x, frame.origin.y);
}

// The nameplate's logo is its one optional slot.
- (void)drawSlot:(NSString *)slot inElement:(NSString *)element text:(nullable NSString *)text dirty:(NSRect)dirty {
    QLMSkinTextSlot *style = [self.skin element:element].text[slot];
    if (style == nil || text.length == 0) {
        return;
    }
    NSRect frame = [self frameOfSlot:slot inElement:element];
    if (!NSIntersectsRect(frame, dirty)) {
        return;
    }
    QLMSkinDrawSlot(text, style, frame, [self.skinLayout scaleOfSlot:slot inElement:element], NO, 1);
}

- (void)drawMarkingsIn:(NSRect)dirty {
    QLMSkinMarkings *markings = self.skin.markings;
    if (markings.width <= 0) {
        return;
    }
    [QLMSkinNSColor(markings.color) setStroke];
    CGFloat half = markings.width / 2;
    for (QLMSkinLine *line in markings.lines) {
        NSRect frame = [self.skinLayout frameOfElement:line.element];
        CGFloat y = round(frame.origin.y + line.y) + half;
        if (!NSIntersectsRect(NSMakeRect(NSMinX(frame), y - half, frame.size.width, markings.width), dirty)) {
            continue;
        }
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(NSMinX(frame), y)];
        [path lineToPoint:NSMakePoint(NSMaxX(frame), y)];
        path.lineWidth = markings.width;
        [path stroke];
    }
    for (QLMSkinBox *box in markings.boxes) {
        NSRect outer = QLMSkinBoxFrame([self.skinLayout frameOfElement:box.element], box.outset);
        if (!NSIntersectsRect(outer, dirty)) {
            continue;
        }
        outer = NSInsetRect(outer, half, half);
        [NSGraphicsContext saveGraphicsState];
        if (box.gap != nil) {
            // The top edge breaks around the slot's text, as a frame's
            // title does.
            NSRect gap = NSInsetRect([self frameOfSlot:box.gap inElement:box.element], -4, 0);
            NSBezierPath *clip = [NSBezierPath bezierPathWithRect:self.bounds];
            [clip appendBezierPathWithRect:gap];
            clip.windingRule = NSWindingRuleEvenOdd;
            [clip addClip];
        }
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:outer xRadius:box.radius yRadius:box.radius];
        path.lineWidth = markings.width;
        [path stroke];
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (NSArray<QLMSkinMaterial *> *)panelMaterials:(QLMSkinLayers *)layers {
    NSMutableArray<QLMSkinMaterial *> *materials = [NSMutableArray array];
    for (NSString *name in @[@"panel", @"nameplate"]) {
        QLMSkinMaterial *material = [QLMSkinMaterial materialOfStyle:[self.skin element:name].style skin:self.skin
                                                               state:QLMSkinStateNormal
                                                               frame:[self.skinLayout frameOfElement:name] circle:NO
                                                             overlay:QLMSkinColorClear layers:layers];
        if (material != nil) {
            [materials addObject:material];
        }
    }
    return materials;
}

// Only what the dirty rect touches, so a change of one text redraws little
// of the panel.
- (void)drawPanel:(NSRect)dirtyRect {
    [self drawMarkingsIn:dirtyRect];
    [self drawSlot:@"logo" inElement:@"nameplate" text:QLMSkinLogo dirty:dirtyRect];
    [self drawSlot:@"groupsTitle" inElement:@"groups" text:QLMSkinGroupsTitle dirty:dirtyRect];
    [self drawSlot:@"message" inElement:@"groups" text:self.groupsMessage dirty:dirtyRect];
    [self drawSlot:@"min" inElement:@"knob" text:self.knobMin dirty:dirtyRect];
    [self drawSlot:@"max" inElement:@"knob" text:self.knobMax dirty:dirtyRect];
    [self drawSlot:@"caption" inElement:@"knob" text:QLMSkinKnobCaption dirty:dirtyRect];
}

@end

NSWindow *QLMSkinHostWindow(QLMSkin *skin, NSWindowStyleMask style) {
    NSRect frame = NSMakeRect(0, 0, skin.windowSize.width, skin.windowSize.height);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.movableByWindowBackground = YES;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.releasedWhenClosed = NO;
    window.contentMinSize = skin.windowSize;
    window.contentView = [[NSView alloc] initWithFrame:frame];
    return window;
}

void QLMSkinHost(NSWindow *window, NSView *view) {
    NSView *container = window.contentView;
    for (NSView *old in [container.subviews copy]) {
        [old removeFromSuperview];
    }
    view.frame = container.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
}
