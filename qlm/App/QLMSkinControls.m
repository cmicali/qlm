#import "QLMSkinControls.h"

#import "NSImage+Util.h"
#import "PlatformColor.h"
#import "QLMSkinDrawing.h"
#import "QLMSkinImages.h"
#import "QLMSkinLayout.h"

// The symbol a footer button draws where this macOS lacks the skin's.
static NSString *const QLMSkinFallbackSymbol = @"questionmark.circle";
// The level's unit, on the display and the OSD.
static NSString *const QLMSkinUnit = @"dB";
// The OSD's subtitle while nothing is muted or dimmed.
static NSString *const QLMSkinOSDIdleSubtitle = @"qlm · Output level";
// How far a footer button's focus ring stands off each side.
static const CGFloat QLMSkinTextButtonFocusMargin = 4;

#pragma mark - The control

@implementation QLMSkinControl {
    NSTrackingArea *_tracking;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _skin = skin;
        _layers = [[QLMSkinLayers alloc] initWithView:self];
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

// QLMSkinLayerView holds the same glue, as an NSView.
- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    [self.layers updateLayer];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    self.needsDisplay = YES;
}

- (void)viewDidUnhide {
    [super viewDidUnhide];
    self.needsDisplay = YES;
}

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    return @[];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
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

- (BOOL)drawsHover {
    return YES;
}

- (void)setHovered:(BOOL)hovered {
    if (hovered == _hovered) {
        return;
    }
    _hovered = hovered;
    if ([self drawsHover]) {
        self.needsDisplay = YES;
    }
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
    QLMSkinInk _titleInk;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithSkin:skin];
    if (self) {
        _title = @"";
        self.layers.contentOutset = MAX(0, ceil(QLMSkinFocusReach(skin.button.focus)));
    }
    return self;
}

- (void)titleDidChange {
    _titleString = nil;
    self.needsDisplay = YES;
}

- (void)setTitle:(NSString *)title {
    if (QLMSkinSameText(title, _title)) {
        return;
    }
    _title = [title copy];
    [self titleDidChange];
}

- (void)setPrefix:(NSString *)prefix {
    if (QLMSkinSameText(prefix, _prefix)) {
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
    _titleString = string;
    _titleInk = QLMSkinLabelInk(string);
    return string;
}

- (NSRect)face {
    return [self.skin.button faceInBounds:self.bounds pressed:self.pressed];
}

- (QLMSkinLabel)label {
    [self titleString];
    QLMSkinButton *button = self.skin.button;
    NSRect face = [self face];
    QLMSkinLabel label = QLMSkinLabelLayout(face.size.width, _titleInk.width, self.showsLED ? button.ledSize : 0,
                                            button.ledGap);
    label.ledX += face.origin.x;
    label.textX += face.origin.x;
    return label;
}

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    NSMutableArray<QLMSkinMaterial *> *materials = [NSMutableArray array];
    QLMSkinState state = QLMSkinButtonState(self.selected, self.enabled, self.pressed, self.hovered);
    QLMSkinMaterial *face = [QLMSkinMaterial materialOfStyle:self.skin.button.style skin:self.skin state:state
                                                       frame:self.bounds circle:NO overlay:QLMSkinColorClear layers:layers];
    if (face != nil) {
        [materials addObject:face];
    }
    if (self.showsLED) {
        CGFloat led = self.skin.button.ledSize;
        NSRect frame = NSMakeRect([self label].ledX, round(NSMidY([self face]) - led / 2), led, led);
        QLMSkinMaterial *dot = [QLMSkinMaterial materialOfLED:self.skin.led skin:self.skin lit:self.ledLit
                                                      enabled:self.enabled frame:frame layers:layers];
        if (dot != nil) {
            [materials addObject:dot];
        }
    }
    return materials;
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    NSAttributedString *title = [self titleString];
    QLMSkinLabel label = [self label];
    NSRect face = [self face];
    QLMSkinDrawLabel(title, _titleInk, label.textX, label.textWidth, face);

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(self.skin.button.focus, face, NO);
    }
}

@end

#pragma mark - A footer button

@implementation QLMSkinTextButton {
    QLMSkinTextSlot *_slot;
    NSString *_symbolName;  // the skin's, or a stand-in where this macOS lacks it
    // Each nil until drawn, and after a change of the title.
    NSAttributedString *_titleString;
    CGFloat _titleAlpha;
    QLMSkinInk _titleInk;
}

- (instancetype)initWithSkin:(QLMSkin *)skin slot:(QLMSkinTextSlot *)slot symbol:(NSString *)symbol {
    self = [super initWithSkin:skin];
    if (self) {
        _slot = slot;
        _symbolName = [[NSImage availableSymbolName:symbol fallback:QLMSkinFallbackSymbol] copy];
        _title = @"";
        self.layers.contentOutset = QLMSkinTextButtonFocusMargin + MAX(0, ceil(QLMSkinFocusReach(skin.button.focus)));
    }
    return self;
}

// Nothing it draws shows hover.
- (BOOL)drawsHover {
    return NO;
}

- (void)setTitle:(NSString *)title {
    if (QLMSkinSameText(title, _title)) {
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
        _titleInk = QLMSkinLabelInk(_titleString);
    }
    return _titleString;
}

// Kept on the skin: building one costs most of a first show's drawing.
- (nullable NSImage *)symbolAtAlpha:(CGFloat)alpha color:(NSColor *)color {
    CGFloat size = round(_slot.size * 1.25);
    NSString *key = [NSString stringWithFormat:@"symbol|%@|%g|%@|%g", _symbolName, size, QLMSkinColorKey(_slot.color), alpha];
    NSString *name = _symbolName;
    return [[QLMSkinImages imagesOfSkin:self.skin] objectForKey:key make:^id {
        NSImageSymbolConfiguration *configuration =
            [[NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular]
                configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:color]];
        return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:configuration];
    }];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    CGFloat alpha = !self.enabled ? QLMSkinDisabledAlpha : self.pressed ? 0.6 : 1;
    NSColor *color = VibeColorWithScaledAlpha(QLMSkinNSColor(_slot.color), alpha);
    NSAttributedString *title = [self titleStringAtAlpha:alpha color:color];
    NSImage *symbol = [self symbolAtAlpha:alpha color:color];

    NSRect bounds = self.bounds;
    CGFloat gap = symbol ? round(_slot.size * 0.7) : 0;
    NSSize symbolSize = symbol ? symbol.size : NSZeroSize;
    CGFloat total = MIN(symbolSize.width + gap + _titleInk.width, bounds.size.width);
    CGFloat x = _slot.alignment == QLMSkinAlignmentLeft ? 0
                : _slot.alignment == QLMSkinAlignmentRight ? bounds.size.width - total
                : round((bounds.size.width - total) / 2);
    if (symbol != nil) {
        NSRect frame = NSMakeRect(x, round(NSMidY(bounds) - symbolSize.height / 2), symbolSize.width, symbolSize.height);
        QLMSkinDrawImage(symbol, frame);
    }
    CGFloat lead = symbolSize.width + gap;
    QLMSkinDrawLabel(title, _titleInk, x + lead, total - lead, bounds);

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(self.skin.button.focus, NSInsetRect(bounds, -QLMSkinTextButtonFocusMargin, 0), NO);
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

- (void)setText:(NSString *)text {
    if (QLMSkinSameText(text, _text)) {
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

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    QLMSkinMaterial *dot = [QLMSkinMaterial materialOfLED:_skin.led skin:_skin lit:self.lit enabled:self.enabled
                                                    frame:[_skin element:@"status"].ledFrame layers:layers];
    return dot ? @[dot] : @[];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    QLMSkinElement *element = [_skin element:@"status"];
    QLMSkinTextSlot *online = element.text[@"online"];
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

// Where a slot inks, in the view.
- (NSRect)inkOfSlot:(NSString *)name {
    QLMSkinElement *element = [_skin element:@"display"];
    QLMSkinTextSlot *slot = element.text[name];
    CGSize size = self.bounds.size;
    return QLMSkinSlotInk(slot, QLMSkinSlotFrame(element, slot, size), QLMSkinSlotScale(element, slot, size));
}

// A text's change redraws its slot alone, over the glass's material.
- (void)redrawSlot:(NSString *)name {
    [self.layers setNeedsDisplayInRect:[self inkOfSlot:name]];
}

- (void)setCaption:(NSString *)caption {
    if (QLMSkinSameText(caption, _caption)) {
        return;
    }
    _caption = [caption copy];
    [self redrawSlot:@"caption"];
}

- (void)setLevel:(NSString *)level {
    if (QLMSkinSameText(level, _level)) {
        return;
    }
    _level = [level copy];
    [self redrawSlot:@"level"];
    [self redrawSlot:@"unit"];
}

- (void)setOutput:(NSString *)output {
    if (QLMSkinSameText(output, _output)) {
        return;
    }
    _output = [output copy];
    [self redrawSlot:@"output"];
}

- (void)setMax:(NSString *)max {
    if (QLMSkinSameText(max, _max)) {
        return;
    }
    _max = [max copy];
    [self redrawSlot:@"max"];
}

- (void)setDisabled:(BOOL)disabled {
    if (disabled == _disabled) {
        return;
    }
    _disabled = disabled;
    self.needsDisplay = YES;
}

// Dimmed, the overlay lays over the glass and over the text, each in its
// own shape. Over both together, as source-atop, it comes to the same.
- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    QLMSkinElement *element = [_skin element:@"display"];
    QLMSkinMaterial *glass = [QLMSkinMaterial materialOfStyle:element.style skin:_skin state:QLMSkinStateNormal
                                                        frame:self.bounds circle:NO
                                                      overlay:self.disabled ? element.disabledOverlay : QLMSkinColorClear
                                                       layers:layers];
    return glass ? @[glass] : @[];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    QLMSkinElement *element = [_skin element:@"display"];
    CGSize size = self.bounds.size;
    QLMSkinDrawDimmed(self.disabled, element.disabledOverlay, self.bounds, ^{
        NSDictionary<NSString *, NSString *> *texts = @{
            @"caption": self.caption ?: @"", @"level": self.level ?: @"", @"unit": QLMSkinUnit,
            @"output": self.output ?: @"", @"max": self.max ?: @"",
        };
        for (NSString *name in texts) {
            if (!NSIntersectsRect([self inkOfSlot:name], dirtyRect)) {
                continue;
            }
            QLMSkinTextSlot *slot = element.text[name];
            QLMSkinDrawSlotInInk(texts[name], slot, QLMSkinSlotFrame(element, slot, size),
                                 QLMSkinSlotScale(element, slot, size), YES, 1);
        }
    });
}

// The slots, as they read, then the tooltip's reason, if any.
- (id)accessibilityValue {
    NSString *level = self.level.length > 0 ? [NSString stringWithFormat:@"%@ %@", self.level, QLMSkinUnit] : nil;
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
    CALayer *_fillClip;  // the fill shows as far as its width
    CALayer *_fill;      // the whole bar's fill
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithFrame:skin.osd.frame];
    if (self) {
        _skin = skin;
        self.clipsToBounds = YES;
        _fillClip = [self.layers makeLayerOfClass:[CALayer class]];
        _fillClip.masksToBounds = YES;
        _fillClip.anchorPoint = CGPointZero;
        _fill = [self.layers makeLayerOfClass:[CALayer class]];
        _fill.contentsGravity = kCAGravityResize;
        [_fillClip addSublayer:_fill];
        self.layers.movingLayers = @[_fillClip];
    }
    return self;
}

- (NSRect)inkOfSlot:(NSString *)name {
    QLMSkinTextSlot *slot = _skin.osd.text[name];
    return QLMSkinSlotInk(slot, slot.frame, 1);
}

// A change redraws its own part alone, over the housing's material.
- (void)redrawSlot:(NSString *)name {
    [self.layers setNeedsDisplayInRect:[self inkOfSlot:name]];
}

- (void)setLevel:(NSString *)level {
    if (QLMSkinSameText(level, _level)) {
        return;
    }
    _level = [level copy];
    [self redrawSlot:@"level"];
    [self redrawSlot:@"unit"];
}

- (void)setTitle:(NSString *)title {
    if (QLMSkinSameText(title, _title)) {
        return;
    }
    _title = [title copy];
    [self redrawSlot:@"title"];
}

- (void)setSubtitle:(NSString *)subtitle {
    if (QLMSkinSameText(subtitle, _subtitle)) {
        return;
    }
    _subtitle = [subtitle copy];
    [self redrawSlot:@"subtitle"];
}

- (void)setFraction:(double)fraction {
    fraction = isfinite(fraction) ? MAX(0, MIN(1, fraction)) : 0;
    if (fraction == _fraction) {
        return;
    }
    _fraction = fraction;
    [self showFractionEased:QLMSkinEases(self)];
}

// The bar's whole shape in `color`, in `rect`.
static void QLMSkinOSDFillBar(QLMSkinBar *bar, QLMSkinColor color, NSRect rect) {
    CGFloat radius = MIN(bar.radius, rect.size.height / 2);
    [QLMSkinNSColor(color) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

- (QLMSkinMaterial *)barMaterialIn:(QLMSkinColor)color family:(NSString *)family layers:(QLMSkinLayers *)layers {
    QLMSkinBar *bar = _skin.osd.bar;
    return [QLMSkinMaterial materialPainting:^(NSRect rect) {
        QLMSkinOSDFillBar(bar, color, rect);
    }
                                       frame:bar.frame
                                      margin:0
                                      family:family
                                        skin:_skin
                                      layers:layers];
}

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    QLMSkinElement *osd = _skin.osd;
    NSMutableArray<QLMSkinMaterial *> *materials = [NSMutableArray array];
    QLMSkinMaterial *housing = [QLMSkinMaterial materialOfStyle:osd.style skin:_skin state:QLMSkinStateNormal frame:osd.frame
                                                         circle:NO overlay:QLMSkinColorClear layers:layers];
    if (housing != nil) {
        [materials addObject:housing];
    }
    QLMSkinMaterial *track = [self barMaterialIn:osd.bar.track family:@"osd-track" layers:layers];
    if (track != nil) {
        [materials addObject:track];
    }
    return materials;
}

// The fill's width, in whole points, so it rests on the pixels.
- (CGFloat)fillWidth {
    return round(_skin.osd.bar.frame.size.width * self.fraction);
}

// The clip spans the fill's material in the view's layer's coordinates, so
// the fill sits at its own frame inside it. Only its width moves.
- (void)layoutSkinMovingLayers:(QLMSkinLayers *)layers {
    QLMSkinMaterial *fill = [self barMaterialIn:_skin.osd.bar.fill family:@"osd-fill" layers:layers];
    [layers showMaterial:fill inLayer:_fill];
    NSRect frame = [self convertRectToLayer:fill.frame];
    frame.origin.x = [self convertRectToLayer:_skin.osd.bar.frame].origin.x;
    _fillClip.position = frame.origin;
    _fillClip.bounds = (CGRect){frame.origin, CGSizeMake([self fillWidth], frame.size.height)};
}

- (void)showFractionEased:(BOOL)eases {
    CGRect bounds = _fillClip.bounds;
    bounds.size.width = [self fillWidth];
    QLMSkinSetLayerValue(_fillClip, @"bounds", [NSValue valueWithRect:bounds], eases);
}

- (void)drawSkinMovingReference {
    QLMSkinBar *bar = _skin.osd.bar;
    if (self.fraction > 0) {
        NSRect fill = bar.frame;
        fill.size.width = [self fillWidth];
        [NSGraphicsContext saveGraphicsState];
        NSRectClip(fill);
        QLMSkinOSDFillBar(bar, bar.fill, bar.frame);
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    QLMSkinElement *osd = _skin.osd;
    NSDictionary<NSString *, NSString *> *texts = @{
        @"level": self.level ?: @"", @"unit": QLMSkinUnit, @"title": self.title ?: @"",
        @"subtitle": self.subtitle ?: QLMSkinOSDIdleSubtitle,
    };
    for (NSString *name in texts) {
        if (NSIntersectsRect([self inkOfSlot:name], dirtyRect)) {
            QLMSkinDrawSlotInInk(texts[name], osd.text[name], osd.text[name].frame, 1, YES, 1);
        }
    }
}

@end
