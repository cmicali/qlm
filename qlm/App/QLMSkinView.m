#import "QLMSkinView.h"

#import "QLMSkinDrawing.h"

static BOOL QLMSkinSameText(NSString *_Nullable a, NSString *_Nullable b) {
    return a == b || [a isEqualToString:b];
}

@implementation QLMSkinView

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSMakeRect(0, 0, skin.windowSize.width, skin.windowSize.height)];
    if (self) {
        _skin = skin;
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
        [self addSubview:_muteButton];
        _dimButton = [[QLMSkinButtonView alloc] initWithSkin:skin];
        [self addSubview:_dimButton];

        _knob = [[QLMKnobControl alloc] initWithSkin:skin];
        [self addSubview:_knob];

        QLMSkinElement *footer = [skin element:@"footer"];
        _monitorsButton = [[QLMSkinTextButton alloc] initWithSkin:skin slot:footer.text[@"monitors"]
                                                           symbol:footer.symbols[@"monitors"]];
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
    self.needsDisplay = YES;
}

- (void)setGroupTitles:(NSArray<NSString *> *)titles prefixes:(NSArray<NSString *> *)prefixes {
    NSUInteger shown = MIN(titles.count, self.groupButtons.count);
    for (NSUInteger i = 0; i < self.groupButtons.count; i++) {
        QLMSkinButtonView *button = self.groupButtons[i];
        button.hidden = i >= shown;
        button.title = i < shown ? titles[i] : @"";
        button.prefix = i < prefixes.count ? prefixes[i] : nil;
    }
}

#pragma mark - The panel's text

// Redraws only the slot's frame, and only on a change.
- (void)setText:(NSString *)text of:(NSString *__strong *)ivar slot:(NSString *)slot inElement:(NSString *)element {
    if (QLMSkinSameText(text, *ivar)) {
        return;
    }
    *ivar = [text copy];
    if ([self.skin element:element].text[slot] != nil) {
        [self setNeedsDisplayInRect:[self frameOfSlot:slot inElement:element]];
    }
}

- (void)setLogo:(NSString *)logo {
    [self setText:logo of:&_logo slot:@"logo" inElement:@"nameplate"];
}

- (void)setTagline:(NSString *)tagline {
    [self setText:tagline of:&_tagline slot:@"tagline" inElement:@"nameplate"];
}

- (void)setGroupsTitle:(NSString *)groupsTitle {
    [self setText:groupsTitle of:&_groupsTitle slot:@"groupsTitle" inElement:@"groups"];
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

- (void)setKnobCaption:(NSString *)knobCaption {
    [self setText:knobCaption of:&_knobCaption slot:@"caption" inElement:@"knob"];
}

#pragma mark - Drawing

// A slot's frame in the window.
- (NSRect)frameOfSlot:(NSString *)slot inElement:(NSString *)element {
    NSRect frame = [self.skinLayout frameOfElement:element];
    return NSOffsetRect([self.skinLayout frameOfSlot:slot inElement:element], frame.origin.x, frame.origin.y);
}

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
        NSRect frame = [self.skinLayout frameOfElement:box.element];
        NSEdgeInsets outset = box.outset;
        NSRect outer = NSMakeRect(frame.origin.x - outset.left, frame.origin.y - outset.top,
                                  frame.size.width + outset.left + outset.right,
                                  frame.size.height + outset.top + outset.bottom);
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

// Only what the dirty rect touches, so a turn of the knob redraws little of
// the panel.
- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinDrawStyle(self.skin, [self.skin element:@"panel"].style, QLMSkinStateNormal,
                     [self.skinLayout frameOfElement:@"panel"], NO);
    NSRect nameplate = [self.skinLayout frameOfElement:@"nameplate"];
    if (NSIntersectsRect(nameplate, dirtyRect)) {
        QLMSkinDrawStyle(self.skin, [self.skin element:@"nameplate"].style, QLMSkinStateNormal, nameplate, NO);
    }
    [self drawMarkingsIn:dirtyRect];
    [self drawSlot:@"logo" inElement:@"nameplate" text:self.logo dirty:dirtyRect];
    [self drawSlot:@"tagline" inElement:@"nameplate" text:self.tagline dirty:dirtyRect];
    [self drawSlot:@"groupsTitle" inElement:@"groups" text:self.groupsTitle dirty:dirtyRect];
    [self drawSlot:@"message" inElement:@"groups" text:self.groupsMessage dirty:dirtyRect];
    [self drawSlot:@"min" inElement:@"knob" text:self.knobMin dirty:dirtyRect];
    [self drawSlot:@"max" inElement:@"knob" text:self.knobMax dirty:dirtyRect];
    [self drawSlot:@"caption" inElement:@"knob" text:self.knobCaption dirty:dirtyRect];
}

@end
