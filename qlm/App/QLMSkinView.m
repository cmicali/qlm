#import "QLMSkinView.h"

#import "QLMSkinDrawing.h"

const NSUInteger QLMSkinViewMaxGroups = 6;

@implementation QLMSkinView

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSMakeRect(0, 0, skin.windowSize.width, skin.windowSize.height)];
    if (self) {
        _skin = skin;
        _skinLayout = [[QLMSkinLayout alloc] initWithSkin:skin size:skin.windowSize];
        _status = [[QLMSkinStatusView alloc] initWithSkin:skin];
        [self addSubview:_status];

        QLMSkinElement *groups = [skin element:@"groups"];
        NSUInteger cells = MIN((NSUInteger)(groups.columns * groups.rows), QLMSkinViewMaxGroups);
        NSMutableArray<QLMSkinButtonView *> *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < cells; i++) {
            QLMSkinButtonView *button = [[QLMSkinButtonView alloc] initWithSkin:skin];
            button.tag = (NSInteger)i;
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

// A frame change calls this, once.
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self applyLayout];
}

static NSRect QLMSkinRect(NSValue *value) {
    CGRect rect = CGRectZero;
    [value getValue:&rect size:sizeof rect];
    return rect;
}

// TRAP: NSView's init sets the frame, before the subviews exist.
- (void)applyLayout {
    if (self.knob == nil) {
        return;
    }
    QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:self.skin size:self.bounds.size];
    _skinLayout = layout;
    self.status.frame = [layout frameOfElement:@"status"];
    self.status.skinLayout = layout;

    NSArray<NSValue *> *cells = [layout cellsOfElement:@"groups"];
    for (NSUInteger i = 0; i < self.groupButtons.count; i++) {
        self.groupButtons[i].frame = QLMSkinRect(cells[i]);
    }

    self.display.frame = [layout frameOfElement:@"display"];
    self.display.skinLayout = layout;

    NSArray<NSValue *> *toggles = [layout cellsOfElement:@"toggles"];
    self.muteButton.frame = QLMSkinRect(toggles[0]);
    self.dimButton.frame = QLMSkinRect(toggles[1]);

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

- (void)setLogo:(NSString *)logo {
    _logo = [logo copy];
    self.needsDisplay = YES;
}

- (void)setTagline:(NSString *)tagline {
    _tagline = [tagline copy];
    self.needsDisplay = YES;
}

- (void)setGroupsMessage:(NSString *)groupsMessage {
    _groupsMessage = [groupsMessage copy];
    self.needsDisplay = YES;
}

- (void)setGroupsTitle:(NSString *)groupsTitle {
    _groupsTitle = [groupsTitle copy];
    self.needsDisplay = YES;
}

- (void)setKnobMin:(NSString *)knobMin {
    _knobMin = [knobMin copy];
    self.needsDisplay = YES;
}

- (void)setKnobMax:(NSString *)knobMax {
    _knobMax = [knobMax copy];
    self.needsDisplay = YES;
}

- (void)setKnobCaption:(NSString *)knobCaption {
    _knobCaption = [knobCaption copy];
    self.needsDisplay = YES;
}

#pragma mark - Drawing

// A slot's frame in the window.
- (NSRect)frameOfSlot:(NSString *)slot inElement:(NSString *)element {
    NSRect frame = [self.skinLayout frameOfElement:element];
    return NSOffsetRect([self.skinLayout frameOfSlot:slot inElement:element], frame.origin.x, frame.origin.y);
}

- (void)drawSlot:(NSString *)slot inElement:(NSString *)element text:(nullable NSString *)text {
    QLMSkinTextSlot *style = [self.skin element:element].text[slot];
    if (style == nil) {
        return;
    }
    QLMSkinDrawSlot(text, style, [self frameOfSlot:slot inElement:element],
                    [self.skinLayout scaleOfSlot:slot inElement:element], NO, 1);
}

- (void)drawMarkings {
    QLMSkinMarkings *markings = self.skin.markings;
    if (markings.width <= 0) {
        return;
    }
    [QLMSkinNSColor(markings.color) setStroke];
    CGFloat half = markings.width / 2;
    for (QLMSkinLine *line in markings.lines) {
        NSRect frame = [self.skinLayout frameOfElement:line.element];
        CGFloat y = round(frame.origin.y + line.y) + half;
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

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinDrawStyle(self.skin, [self.skin element:@"panel"].style, QLMSkinStateNormal,
                     [self.skinLayout frameOfElement:@"panel"], NO);
    QLMSkinDrawStyle(self.skin, [self.skin element:@"nameplate"].style, QLMSkinStateNormal,
                     [self.skinLayout frameOfElement:@"nameplate"], NO);
    [self drawMarkings];
    [self drawSlot:@"logo" inElement:@"nameplate" text:self.logo];
    [self drawSlot:@"tagline" inElement:@"nameplate" text:self.tagline];
    [self drawSlot:@"groupsTitle" inElement:@"groups" text:self.groupsTitle];
    [self drawSlot:@"message" inElement:@"groups" text:self.groupsMessage];
    [self drawSlot:@"min" inElement:@"knob" text:self.knobMin];
    [self drawSlot:@"max" inElement:@"knob" text:self.knobMax];
    [self drawSlot:@"caption" inElement:@"knob" text:self.knobCaption];
}

@end
