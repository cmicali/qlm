#import "QLMSkinControls.h"

#import "NSImage+Util.h"
#import "PlatformColor.h"
#import "QLMSkinDrawing.h"
#import "QLMSkinLayout.h"

static BOOL QLMSkinSame(NSString *_Nullable a, NSString *_Nullable b) {
    return a == b || [a isEqualToString:b];
}

// The symbol a footer button draws where this macOS lacks the skin's.
static NSString *const QLMSkinFallbackSymbol = @"questionmark.circle";

#pragma mark - The control

@implementation QLMSkinControl {
    NSTrackingArea *_tracking;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _skin = skin;
        self.focusRingType = NSFocusRingTypeNone;
        // A button unless its controller says otherwise.
        self.accessibilityRole = NSAccessibilityButtonRole;
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
    if (hovered == _hovered) {
        return;
    }
    _hovered = hovered;
    self.needsDisplay = YES;
}

- (void)setPressed:(BOOL)pressed {
    if (pressed == _pressed) {
        return;
    }
    _pressed = pressed;
    self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == self.enabled) {
        return;
    }
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

- (BOOL)isAccessibilityElement {
    return YES;
}

- (BOOL)isAccessibilityEnabled {
    return self.enabled;
}

- (BOOL)accessibilityPerformPress {
    if (!self.enabled) {
        return NO;
    }
    [self sendAction:self.action to:self.target];
    return YES;
}

@end

#pragma mark - A button

@implementation QLMSkinButtonView {
    NSAttributedString *_titleString;  // nil until drawn, and after a change
    CGFloat _titleWidth;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithSkin:skin];
    if (self) {
        _title = @"";
    }
    return self;
}

- (void)titleDidChange {
    _titleString = nil;
    self.needsDisplay = YES;
}

- (void)setTitle:(NSString *)title {
    if (QLMSkinSame(title, _title)) {
        return;
    }
    _title = [title copy];
    [self titleDidChange];
}

- (void)setPrefix:(NSString *)prefix {
    if (QLMSkinSame(prefix, _prefix)) {
        return;
    }
    _prefix = [prefix copy];
    [self titleDidChange];
}

- (void)setSelected:(BOOL)selected {
    if (selected == _selected) {
        return;
    }
    _selected = selected;
    [self titleDidChange];
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == self.enabled) {
        return;
    }
    super.enabled = enabled;
    [self titleDidChange];
}

- (void)setShowsLED:(BOOL)showsLED {
    if (showsLED == _showsLED) {
        return;
    }
    _showsLED = showsLED;
    self.needsDisplay = YES;
}

- (void)setLedLit:(BOOL)ledLit {
    if (ledLit == _ledLit) {
        return;
    }
    _ledLit = ledLit;
    self.needsDisplay = YES;
}

- (NSAttributedString *)titleString {
    if (_titleString != nil) {
        return _titleString;
    }
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
    _titleString = string;
    _titleWidth = ceil(string.size.width) + 1;
    return string;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinButton *button = self.skin.button;
    NSRect bounds = self.bounds;
    QLMSkinState state = QLMSkinButtonState(self.selected, self.enabled, self.pressed, self.hovered);
    QLMSkinDrawStyle(self.skin, button.style, state, bounds, NO);

    NSAttributedString *title = [self titleString];
    CGFloat led = self.showsLED ? button.ledSize : 0;
    QLMSkinLabel label = QLMSkinLabelLayout(bounds.size.width, _titleWidth, led, button.ledGap, button.ledX);
    if (self.showsLED) {
        QLMSkinDrawLED(self.skin.led, NSMakeRect(label.ledX, round(NSMidY(bounds) - led / 2), led, led), self.ledLit,
                       self.enabled);
    }
    QLMSkinDrawCenteredCaps(title, NSMakeRect(label.textX, 0, label.textWidth, bounds.size.height));

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(button.focus, bounds, NO);
    }
}

@end

#pragma mark - A footer button

@implementation QLMSkinTextButton {
    QLMSkinTextSlot *_slot;
    NSAttributedString *_titleString;  // nil until drawn, and after a change
    CGFloat _titleAlpha;
    CGFloat _titleWidth;
}

- (instancetype)initWithSkin:(QLMSkin *)skin slot:(QLMSkinTextSlot *)slot symbol:(NSString *)symbol {
    self = [super initWithSkin:skin];
    if (self) {
        _slot = slot;
        _symbolName = [[NSImage availableSymbolName:symbol fallback:QLMSkinFallbackSymbol] copy];
        _title = @"";
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    if (QLMSkinSame(title, _title)) {
        return;
    }
    _title = [title copy];
    _titleString = nil;
    self.needsDisplay = YES;
}

- (NSAttributedString *)titleStringAtAlpha:(CGFloat)alpha color:(NSColor *)color {
    if (_titleString == nil || _titleAlpha != alpha) {
        _titleString = [[NSAttributedString alloc]
            initWithString:self.title
                attributes:QLMSkinTextAttributes(QLMSkinSlotFont(_slot, 1, NO), color, QLMSkinAlignmentLeft, _slot.tracking)];
        _titleAlpha = alpha;
        _titleWidth = ceil(_titleString.size.width) + 1;
    }
    return _titleString;
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat alpha = !self.enabled ? QLMSkinDisabledAlpha : self.pressed ? 0.6 : 1;
    NSColor *color = VibeColorWithScaledAlpha(QLMSkinNSColor(_slot.color), alpha);
    NSAttributedString *title = [self titleStringAtAlpha:alpha color:color];

    NSImageSymbolConfiguration *configuration =
        [[NSImageSymbolConfiguration configurationWithPointSize:round(_slot.size * 1.25) weight:NSFontWeightRegular]
            configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
    NSImage *symbol = [[NSImage imageWithSystemSymbolName:self.symbolName accessibilityDescription:nil]
        imageWithSymbolConfiguration:configuration];

    NSRect bounds = self.bounds;
    CGFloat gap = symbol ? round(_slot.size * 0.7) : 0;
    NSSize symbolSize = symbol ? symbol.size : NSZeroSize;
    CGFloat total = MIN(symbolSize.width + gap + _titleWidth, bounds.size.width);
    CGFloat x = _slot.alignment == QLMSkinAlignmentLeft ? 0
                : _slot.alignment == QLMSkinAlignmentRight ? bounds.size.width - total
                : round((bounds.size.width - total) / 2);
    if (symbol != nil) {
        NSRect frame = NSMakeRect(x, round(NSMidY(bounds) - symbolSize.height / 2), symbolSize.width, symbolSize.height);
        QLMSkinDrawImage(symbol, frame);
    }
    QLMSkinDrawCenteredCaps(title, NSMakeRect(x + symbolSize.width + gap, 0, total - symbolSize.width - gap, bounds.size.height));

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
    if (QLMSkinSame(text, _text)) {
        return;
    }
    _text = [text copy];
    self.needsDisplay = YES;
}

- (void)setLit:(BOOL)lit {
    if (lit == _lit) {
        return;
    }
    _lit = lit;
    self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) {
        return;
    }
    _enabled = enabled;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinElement *element = [_skin element:@"status"];
    QLMSkinTextSlot *online = element.text[@"online"];
    QLMSkinDrawLED(_skin.led, element.ledFrame, self.lit, self.enabled);
    QLMSkinDrawSlot(self.text, online, QLMSkinSlotFrame(element, online, self.bounds.size), 1, YES,
                    self.enabled ? 1 : QLMSkinDisabledAlpha);
}

- (id)accessibilityValue {
    return self.toolTip ?: self.text;
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

- (void)setCaption:(NSString *)caption {
    if (QLMSkinSame(caption, _caption)) {
        return;
    }
    _caption = [caption copy];
    self.needsDisplay = YES;
}

- (void)setLevel:(NSString *)level {
    if (QLMSkinSame(level, _level)) {
        return;
    }
    _level = [level copy];
    self.needsDisplay = YES;
}

- (void)setUnit:(NSString *)unit {
    if (QLMSkinSame(unit, _unit)) {
        return;
    }
    _unit = [unit copy];
    self.needsDisplay = YES;
}

- (void)setOutput:(NSString *)output {
    if (QLMSkinSame(output, _output)) {
        return;
    }
    _output = [output copy];
    self.needsDisplay = YES;
}

- (void)setMax:(NSString *)max {
    if (QLMSkinSame(max, _max)) {
        return;
    }
    _max = [max copy];
    self.needsDisplay = YES;
}

- (void)setDisabled:(BOOL)disabled {
    if (disabled == _disabled) {
        return;
    }
    _disabled = disabled;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinElement *element = [_skin element:@"display"];
    CGSize size = self.bounds.size;
    QLMSkinDrawDimmed(self.disabled, element.disabledOverlay, self.bounds, ^{
        QLMSkinDrawStyle(self->_skin, element.style, QLMSkinStateNormal, self.bounds, NO);
        NSDictionary<NSString *, NSString *> *texts = @{
            @"caption": self.caption ?: @"", @"level": self.level ?: @"", @"unit": self.unit ?: @"",
            @"output": self.output ?: @"", @"max": self.max ?: @"",
        };
        for (NSString *name in texts) {
            QLMSkinTextSlot *slot = element.text[name];
            QLMSkinDrawSlot(texts[name], slot, QLMSkinSlotFrame(element, slot, size), QLMSkinSlotScale(element, slot, size),
                            YES, 1);
        }
    });
}

// The slots, as they read, then the tooltip's reason, if any.
- (id)accessibilityValue {
    NSString *level = self.level.length > 0 ? [NSString stringWithFormat:@"%@ %@", self.level, self.unit ?: @""] : nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in @[self.caption ?: @"", level ?: @"", self.output ?: @"", self.max ?: @"", self.toolTip ?: @""]) {
        if (part.length > 0) {
            [parts addObject:part];
        }
    }
    return [parts componentsJoinedByString:@". "];
}

@end

#pragma mark - The OSD

@implementation QLMSkinOSDView {
    QLMSkin *_skin;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:skin.osd.frame];
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
    if (QLMSkinSame(level, _level)) {
        return;
    }
    _level = [level copy];
    self.needsDisplay = YES;
}

- (void)setUnit:(NSString *)unit {
    if (QLMSkinSame(unit, _unit)) {
        return;
    }
    _unit = [unit copy];
    self.needsDisplay = YES;
}

- (void)setTitle:(NSString *)title {
    if (QLMSkinSame(title, _title)) {
        return;
    }
    _title = [title copy];
    self.needsDisplay = YES;
}

- (void)setSubtitle:(NSString *)subtitle {
    if (QLMSkinSame(subtitle, _subtitle)) {
        return;
    }
    _subtitle = [subtitle copy];
    self.needsDisplay = YES;
}

- (void)setFraction:(double)fraction {
    fraction = isfinite(fraction) ? MAX(0, MIN(1, fraction)) : 0;
    if (fraction == _fraction) {
        return;
    }
    _fraction = fraction;
    self.needsDisplay = YES;
}

- (void)setDisabled:(BOOL)disabled {
    if (disabled == _disabled) {
        return;
    }
    _disabled = disabled;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinElement *osd = _skin.osd;
    NSRect bounds = osd.frame;
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
