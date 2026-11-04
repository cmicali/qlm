#import "QLMSkinControls.h"

#import "QLMSkinDrawing.h"
#import "QLMSkinLayout.h"

#pragma mark - The control

@implementation QLMSkinControl {
    NSTrackingArea *_tracking;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _skin = skin;
        self.focusRingType = NSFocusRingTypeNone;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking != nil) {
        [self removeTrackingArea:_tracking];
    }
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect;
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)setHovered:(BOOL)hovered {
    _hovered = hovered;
    self.needsDisplay = YES;
}

- (void)setPressed:(BOOL)pressed {
    _pressed = pressed;
    self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled {
    super.enabled = enabled;
    self.needsDisplay = YES;
}

- (void)mouseEntered:(NSEvent *)event {
    self.hovered = YES;
}

- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
}

- (BOOL)isFocused {
    return self.window.isKeyWindow && self.window.firstResponder == self;
}

- (BOOL)acceptsFirstResponder {
    return self.enabled;
}

- (BOOL)becomeFirstResponder {
    self.needsDisplay = YES;
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
    self.needsDisplay = YES;
    return [super resignFirstResponder];
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) {
        return;
    }
    self.pressed = YES;
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
        BOOL inside = NSPointInRect(point, self.bounds);
        if (next.type == NSEventTypeLeftMouseUp) {
            self.pressed = NO;
            if (inside) {
                [self sendAction:self.action to:self.target];
            }
            return;
        }
        self.pressed = inside;
    }
}

- (void)keyDown:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    if (self.enabled && ([key isEqualToString:@" "] || [key isEqualToString:@"\r"])) {
        [self sendAction:self.action to:self.target];
        return;
    }
    [super keyDown:event];
}

@end

#pragma mark - A button

@implementation QLMSkinButtonView

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithSkin:skin];
    if (self) {
        _title = @"";
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.needsDisplay = YES;
}

- (void)setPrefix:(NSString *)prefix {
    _prefix = [prefix copy];
    self.needsDisplay = YES;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.needsDisplay = YES;
}

- (void)setShowsLED:(BOOL)showsLED {
    _showsLED = showsLED;
    self.needsDisplay = YES;
}

- (void)setLedLit:(BOOL)ledLit {
    _ledLit = ledLit;
    self.needsDisplay = YES;
}

- (NSAttributedString *)titleString {
    QLMSkinTitle *style = self.skin.button.title;
    QLMSkinColor color = !self.enabled ? style.disabledColor : self.selected ? style.selectedColor : style.color;
    QLMSkinColor prefixColor = self.enabled ? style.prefixColor : style.disabledColor;
    NSFont *font = QLMSkinFont(style.fontName, NO, style.size, style.weight, NO, NO);
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] init];
    if (self.prefix.length > 0) {
        NSString *prefix = [self.prefix stringByAppendingString:@"  "];
        [string appendAttributedString:[[NSAttributedString alloc]
                                           initWithString:prefix
                                               attributes:QLMSkinTextAttributes(font, QLMSkinNSColor(prefixColor),
                                                                                QLMSkinAlignmentLeft, style.tracking)]];
    }
    [string appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:self.title
                                           attributes:QLMSkinTextAttributes(font, QLMSkinNSColor(color),
                                                                            QLMSkinAlignmentLeft, style.tracking)]];
    // The last character's tracking would push the title off center.
    if (string.length > 0) {
        [string removeAttribute:NSKernAttributeName range:NSMakeRange(string.length - 1, 1)];
    }
    return string;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinButton *button = self.skin.button;
    NSRect bounds = self.bounds;
    QLMSkinState state = QLMSkinButtonState(self.selected, self.enabled, self.pressed, self.hovered);
    QLMSkinDrawStyle(self.skin, button.style, state, bounds, NO);

    NSAttributedString *title = [self titleString];
    CGFloat width = MIN(ceil(title.size.width) + 1, bounds.size.width);
    CGFloat led = self.showsLED ? button.ledSize : 0;
    BOOL beforeTitle = self.showsLED && button.ledX < 0;
    CGFloat total = beforeTitle ? led + button.ledGap + width : width;
    CGFloat x = round(NSMidX(bounds) - total / 2);
    if (self.showsLED) {
        CGFloat ledX = beforeTitle ? x : button.ledX;
        QLMSkinDrawLED(self.skin.led, NSMakeRect(ledX, round(NSMidY(bounds) - led / 2), led, led), self.ledLit, self.enabled);
    }
    CGFloat textX = beforeTitle ? x + led + button.ledGap : x;
    QLMSkinDrawAttributed(title, NSMakeRect(textX, 0, width, bounds.size.height));

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(button.focus, bounds, NO);
    }
}

@end

#pragma mark - A footer button

@implementation QLMSkinTextButton {
    QLMSkinTextSlot *_slot;
    NSMutableDictionary<NSNumber *, NSImage *> *_symbols;  // by alpha
}

- (instancetype)initWithSkin:(QLMSkin *)skin slot:(QLMSkinTextSlot *)slot symbol:(NSString *)symbol {
    self = [super initWithSkin:skin];
    if (self) {
        _slot = slot;
        _symbolName = [symbol copy];
        _title = @"";
        _symbols = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.needsDisplay = YES;
}

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = [symbolName copy];
    [_symbols removeAllObjects];
    self.needsDisplay = YES;
}

- (nullable NSImage *)symbolInColor:(NSColor *)color alpha:(CGFloat)alpha {
    NSImage *symbol = _symbols[@(alpha)];
    if (symbol == nil) {
        NSImageSymbolConfiguration *configuration =
            [[NSImageSymbolConfiguration configurationWithPointSize:round(_slot.size * 1.25) weight:NSFontWeightRegular]
                configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
        symbol = [[NSImage imageWithSystemSymbolName:self.symbolName accessibilityDescription:nil]
            imageWithSymbolConfiguration:configuration];
        if (symbol != nil) {
            _symbols[@(alpha)] = symbol;
        }
    }
    return symbol;
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat alpha = !self.enabled ? 0.4 : self.pressed ? 0.6 : 1;
    NSColor *color = [QLMSkinNSColor(_slot.color) colorWithAlphaComponent:_slot.color.alpha * alpha];
    NSFont *font = QLMSkinSlotFont(_slot, 1, NO);
    NSAttributedString *title = [[NSAttributedString alloc]
        initWithString:self.title
            attributes:QLMSkinTextAttributes(font, color, QLMSkinAlignmentLeft, _slot.tracking)];

    NSImage *symbol = [self symbolInColor:color alpha:alpha];

    NSRect bounds = self.bounds;
    CGFloat gap = symbol ? round(_slot.size * 0.7) : 0;
    NSSize symbolSize = symbol ? symbol.size : NSZeroSize;
    CGFloat textWidth = ceil(title.size.width) + 1;
    CGFloat total = MIN(symbolSize.width + gap + textWidth, bounds.size.width);
    CGFloat x = _slot.alignment == QLMSkinAlignmentLeft ? 0
                : _slot.alignment == QLMSkinAlignmentRight ? bounds.size.width - total
                : round((bounds.size.width - total) / 2);
    if (symbol != nil) {
        NSRect frame = NSMakeRect(x, round(NSMidY(bounds) - symbolSize.height / 2), symbolSize.width, symbolSize.height);
        [symbol drawInRect:frame fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
            respectFlipped:YES hints:nil];
    }
    QLMSkinDrawAttributed(title, NSMakeRect(x + symbolSize.width + gap, 0, total - symbolSize.width - gap, bounds.size.height));

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(self.skin.button.focus, NSInsetRect(bounds, -4, 0), NO);
    }
}

@end

#pragma mark - The status

@implementation QLMSkinStatusView {
    QLMSkin *_skin;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _skin = skin;
        _enabled = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setText:(NSString *)text {
    _text = [text copy];
    self.needsDisplay = YES;
}

- (void)setLit:(BOOL)lit {
    _lit = lit;
    self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    self.needsDisplay = YES;
}

- (void)setSkinLayout:(QLMSkinLayout *)skinLayout {
    _skinLayout = skinLayout;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinElement *element = [_skin element:@"status"];
    QLMSkinDrawLED(_skin.led, element.ledFrame, self.lit, self.enabled);
    if (self.skinLayout != nil) {
        QLMSkinDrawSlot(self.text, element.text[@"online"], [self.skinLayout frameOfSlot:@"online" inElement:@"status"], 1, YES,
                        self.enabled ? 1 : 0.5);
    }
}

@end

#pragma mark - The display

@implementation QLMSkinDisplayView {
    QLMSkin *_skin;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _skin = skin;
        self.clipsToBounds = YES;  // nothing draws over the knob column
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setSkinLayout:(QLMSkinLayout *)skinLayout {
    _skinLayout = skinLayout;
    self.needsDisplay = YES;
}

- (void)setCaption:(NSString *)caption {
    _caption = [caption copy];
    self.needsDisplay = YES;
}

- (void)setLevel:(NSString *)level {
    _level = [level copy];
    self.needsDisplay = YES;
}

- (void)setUnit:(NSString *)unit {
    _unit = [unit copy];
    self.needsDisplay = YES;
}

- (void)setOutput:(NSString *)output {
    _output = [output copy];
    self.needsDisplay = YES;
}

- (void)setMax:(NSString *)max {
    _max = [max copy];
    self.needsDisplay = YES;
}

- (void)setDisabled:(BOOL)disabled {
    _disabled = disabled;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinElement *element = [_skin element:@"display"];
    QLMSkinDrawDimmed(self.disabled, element.disabledOverlay, self.bounds, ^{
        QLMSkinDrawStyle(self->_skin, element.style, QLMSkinStateNormal, self.bounds, NO);
        if (self.skinLayout == nil) {
            return;
        }
        NSDictionary<NSString *, NSString *> *texts = @{
            @"caption": self.caption ?: @"", @"level": self.level ?: @"", @"unit": self.unit ?: @"",
            @"output": self.output ?: @"", @"max": self.max ?: @"",
        };
        for (NSString *name in texts) {
            QLMSkinDrawSlot(texts[name], element.text[name], [self.skinLayout frameOfSlot:name inElement:@"display"],
                            [self.skinLayout scaleOfSlot:name inElement:@"display"], YES, 1);
        }
    });
}

@end

#pragma mark - The OSD

@implementation QLMSkinOSDView {
    QLMSkin *_skin;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSMakeRect(0, 0, skin.osdSize.width, skin.osdSize.height)];
    if (self) {
        _skin = skin;
        self.clipsToBounds = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)setLevel:(NSString *)level {
    _level = [level copy];
    self.needsDisplay = YES;
}

- (void)setUnit:(NSString *)unit {
    _unit = [unit copy];
    self.needsDisplay = YES;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.needsDisplay = YES;
}

- (void)setSubtitle:(NSString *)subtitle {
    _subtitle = [subtitle copy];
    self.needsDisplay = YES;
}

- (void)setFraction:(double)fraction {
    _fraction = isfinite(fraction) ? MAX(0, MIN(1, fraction)) : 0;
    self.needsDisplay = YES;
}

- (void)setDisabled:(BOOL)disabled {
    _disabled = disabled;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinElement *osd = _skin.osd;
    NSRect bounds = NSMakeRect(0, 0, _skin.osdSize.width, _skin.osdSize.height);
    QLMSkinDrawDimmed(self.disabled, osd.disabledOverlay, bounds, ^{
        QLMSkinDrawStyle(self->_skin, osd.style, QLMSkinStateNormal, bounds, NO);
        NSDictionary<NSString *, NSString *> *texts = @{
            @"level": self.level ?: @"", @"unit": self.unit ?: @"", @"title": self.title ?: @"",
            @"subtitle": self.subtitle ?: @"",
        };
        for (NSString *name in texts) {
            QLMSkinDrawSlot(texts[name], osd.text[name], osd.text[name].frame, 1, YES, 1);
        }

        QLMSkinBar *bar = osd.bar;
        CGFloat radius = MIN(bar.radius, bar.frame.size.height / 2);
        [QLMSkinNSColor(bar.track) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:bar.frame xRadius:radius yRadius:radius] fill];
        if (self.fraction > 0) {
            NSRect fill = bar.frame;
            fill.size.width = round(fill.size.width * self.fraction);
            [NSGraphicsContext saveGraphicsState];
            NSRectClip(fill);
            [QLMSkinNSColor(bar.fill) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:bar.frame xRadius:radius yRadius:radius] fill];
            [NSGraphicsContext restoreGraphicsState];
        }
    });
}

@end
