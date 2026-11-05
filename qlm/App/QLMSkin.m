#import "QLMSkin.h"

#include <math.h>

NSErrorDomain const QLMSkinErrorDomain = @"QLMSkinErrorDomain";

const QLMSkinColor QLMSkinColorClear = {0, 0, 0, 0};

static const int QLMSkinFormat = 1;

// The smallest window and OSD a skin may declare: the pack's sizes for the
// window and for its OSD housing's image.
static const CGSize QLMSkinReferenceWindowSize = {640, 480};
static const CGSize QLMSkinReferenceOSDSize = {300, 72};

NSArray<NSString *> *QLMSkinElementNames(void) {
    return @[@"panel", @"nameplate", @"status", @"groups", @"display", @"toggles", @"knob", @"footer"];
}

BOOL QLMSkinIsPlainName(NSString *name) {
    return name.length > 0 && ![name containsString:@"/"] && ![name hasPrefix:@"."];
}

QLMSkinState QLMSkinButtonState(BOOL selected, BOOL enabled, BOOL pressed, BOOL hovered) {
    if (!enabled) {
        return selected ? QLMSkinStateSelectedDisabled : QLMSkinStateDisabled;
    }
    if (pressed) {
        return selected ? QLMSkinStateSelectedPressed : QLMSkinStatePressed;
    }
    if (hovered) {
        return selected ? QLMSkinStateSelectedHover : QLMSkinStateHover;
    }
    return selected ? QLMSkinStateSelected : QLMSkinStateNormal;
}

// The suffixes of the states' image files, as the pack names them.
static NSArray<NSString *> *QLMSkinStateNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"normal", @"hover", @"pressed", @"disabled",
                  @"selected", @"selected-hover", @"selected-pressed", @"selected-disabled"];
    });
    return names;
}

static NSString *QLMSkinStateName(QLMSkinState state) {
    return QLMSkinStateNames()[(NSUInteger)state];
}

static NSString *QLMSkinKey(NSString *path, NSString *key) {
    return [NSString stringWithFormat:@"%@.%@", path, key];
}

// JSON's number, not its true or false, which NSJSONSerialization also
// gives as an NSNumber.
static BOOL QLMSkinIsNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}

// Keys format 1 had until #86, by the path they sit at. A user's skin copied
// from modern before then carries them, so they are accepted and never read.
static NSDictionary<NSString *, NSArray<NSString *> *> *QLMSkinIgnoredKeys(void) {
    return @{@"elements.nameplate.text": @[@"tagline"], @"osd": @[@"disabledOverlay"]};
}

NSInteger QLMSkinImageFileScale(CGFloat scale) {
    return scale > 1 ? 2 : 1;
}

NSString *QLMSkinImagePath(NSString *name, NSInteger scale) {
    NSString *suffix = QLMSkinImageFileScale(scale) == 2 ? @"@2x.png" : @".png";
    return [@"png" stringByAppendingPathComponent:[name stringByAppendingString:suffix]];
}

CGSize QLMSkinGridCellSize(CGSize size, NSInteger columns, NSInteger rows, CGSize gap) {
    return CGSizeMake((size.width - gap.width * (columns - 1)) / columns, (size.height - gap.height * (rows - 1)) / rows);
}

CGRect QLMSkinInsetRect(CGRect frame, NSEdgeInsets insets) {
    return QLMSkinGrowRect(frame, NSEdgeInsetsMake(-insets.top, -insets.left, -insets.bottom, -insets.right));
}

CGRect QLMSkinGrowRect(CGRect frame, NSEdgeInsets outset) {
    return CGRectMake(frame.origin.x - outset.left, frame.origin.y - outset.top, frame.size.width + outset.left + outset.right,
                      frame.size.height + outset.top + outset.bottom);
}

CGRect QLMSkinBoxedRect(QLMSkinElement *element, QLMSkinButton *button, CGRect frame) {
    return element.columns > 0 ? QLMSkinInsetRect(frame, button.face) : frame;
}

#pragma mark - Values

@interface QLMSkinShadow ()
@property (nonatomic) QLMSkinColor color;
@property (nonatomic) CGFloat blur;
@property (nonatomic) CGSize offset;
@end

@implementation QLMSkinShadow
@end

@interface QLMSkinRing ()
@property (nonatomic) CGFloat inset;
@property (nonatomic) QLMSkinColor color;
@property (nonatomic) CGFloat width;
@end

@implementation QLMSkinRing
@end

@interface QLMSkinDraw () <NSCopying>
@property (nonatomic) QLMSkinColor fill;
@property (nonatomic) BOOL hasGradient;
@property (nonatomic) QLMSkinColor gradientTop;
@property (nonatomic) QLMSkinColor gradientBottom;
@property (nonatomic) QLMSkinColor border;
@property (nonatomic) CGFloat borderWidth;
@property (nonatomic) CGFloat radius;
@property (nonatomic) CGFloat inset;
@property (nonatomic, copy) NSArray<QLMSkinRing *> *rings;
@property (nonatomic, nullable) QLMSkinShadow *shadow;
@end

@implementation QLMSkinDraw

- (instancetype)init {
    self = [super init];
    if (self) {
        _rings = @[];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    QLMSkinDraw *copy = [[QLMSkinDraw allocWithZone:zone] init];
    copy.fill = self.fill;
    copy.hasGradient = self.hasGradient;
    copy.gradientTop = self.gradientTop;
    copy.gradientBottom = self.gradientBottom;
    copy.border = self.border;
    copy.borderWidth = self.borderWidth;
    copy.radius = self.radius;
    copy.inset = self.inset;
    copy.rings = self.rings;
    copy.shadow = self.shadow;
    return copy;
}

- (BOOL)isUniformAlongWidth {
    return YES;
}

- (BOOL)isUniformAlongHeight {
    return !self.hasGradient;
}

@end

@interface QLMSkinStyle ()
@property (nonatomic, copy, nullable) NSString *imageName;
@property (nonatomic) NSEdgeInsets capInsets;
@property (nonatomic) BOOL hasStates;
@property (nonatomic, copy, nullable) NSArray<QLMSkinDraw *> *draws;  // by state
@end

@implementation QLMSkinStyle

- (NSString *)imageNameForState:(QLMSkinState)state {
    if (!self.hasStates) {
        return self.imageName ?: @"";
    }
    return [NSString stringWithFormat:@"%@-%@", self.imageName ?: @"", QLMSkinStateName(state)];
}

- (QLMSkinDraw *)drawForState:(QLMSkinState)state {
    if (self.draws == nil) {
        return nil;
    }
    return self.draws[self.hasStates ? (NSUInteger)state : 0];
}

@end

@interface QLMSkinTextSlot ()
@property (nonatomic) CGRect frame;
@property (nonatomic) QLMSkinAnchors anchors;
@property (nonatomic) BOOL scales;
@property (nonatomic, copy, nullable) NSString *fontName;
@property (nonatomic) BOOL mono;
@property (nonatomic) CGFloat size;
@property (nonatomic) QLMSkinWeight weight;
@property (nonatomic) BOOL italic;
@property (nonatomic) QLMSkinAlignment alignment;
@property (nonatomic) QLMSkinColor color;
@property (nonatomic) CGFloat tracking;
@property (nonatomic) QLMSkinColor accentColor;
@end

@implementation QLMSkinTextSlot
@end

@interface QLMSkinLine ()
@property (nonatomic, copy) NSString *element;
@property (nonatomic) CGFloat y;
@end

@implementation QLMSkinLine
@end

@interface QLMSkinBox ()
@property (nonatomic, copy) NSString *element;
@property (nonatomic) NSEdgeInsets outset;
@property (nonatomic) CGFloat radius;
@property (nonatomic, copy, nullable) NSString *gap;
@end

@implementation QLMSkinBox
@end

@interface QLMSkinMarkings ()
@property (nonatomic) QLMSkinColor color;
@property (nonatomic) CGFloat width;
@property (nonatomic, copy) NSArray<QLMSkinLine *> *lines;
@property (nonatomic, copy) NSArray<QLMSkinBox *> *boxes;
@end

@implementation QLMSkinMarkings
@end

@interface QLMSkinLED ()
@property (nonatomic) QLMSkinColor on;
@property (nonatomic) QLMSkinColor off;
@property (nonatomic) CGFloat glow;
@end

@implementation QLMSkinLED
@end

@interface QLMSkinFocus ()
@property (nonatomic) QLMSkinColor color;
@property (nonatomic) CGFloat width;
@property (nonatomic) CGFloat radius;
@property (nonatomic) CGFloat outset;
@end

@implementation QLMSkinFocus
@end

@interface QLMSkinTitle ()
@property (nonatomic, copy, nullable) NSString *fontName;
@property (nonatomic) CGFloat size;
@property (nonatomic) QLMSkinWeight weight;
@property (nonatomic) CGFloat tracking;
@property (nonatomic) QLMSkinColor color;
@property (nonatomic) QLMSkinColor selectedColor;
@property (nonatomic) QLMSkinColor disabledColor;
@property (nonatomic) QLMSkinColor prefixColor;
@end

@implementation QLMSkinTitle
@end

@interface QLMSkinButton ()
@property (nonatomic) QLMSkinStyle *style;
@property (nonatomic) QLMSkinTitle *title;
@property (nonatomic) QLMSkinFocus *focus;
@property (nonatomic) CGFloat ledSize;
@property (nonatomic) CGFloat ledGap;
@property (nonatomic) NSEdgeInsets face;
@property (nonatomic) NSEdgeInsets pressedFace;
@end

@implementation QLMSkinButton

- (CGRect)faceInBounds:(CGRect)bounds pressed:(BOOL)pressed {
    return QLMSkinInsetRect(bounds, pressed ? self.pressedFace : self.face);
}

@end

@interface QLMSkinKnob ()
@property (nonatomic) CGFloat bodySize;
@property (nonatomic) QLMSkinStyle *body;
@property (nonatomic) NSInteger tickCount;
@property (nonatomic) CGFloat tickInner;
@property (nonatomic) CGFloat tickOuter;
@property (nonatomic) CGFloat tickWidth;
@property (nonatomic) QLMSkinColor tickColor;
@property (nonatomic) CGFloat pointerInner;
@property (nonatomic) CGFloat pointerOuter;
@property (nonatomic) CGFloat pointerWidth;
@property (nonatomic) QLMSkinColor pointerColor;
@property (nonatomic) QLMSkinColor pointerDisabledColor;
@property (nonatomic, nullable) QLMSkinShadow *shadow;
@property (nonatomic) QLMSkinFocus *focus;
@property (nonatomic) BOOL hasArc;
@property (nonatomic) CGFloat arcRadius;
@property (nonatomic) CGFloat arcWidth;
@property (nonatomic) QLMSkinColor arcTrack;
@property (nonatomic) QLMSkinColor arcFill;
@end

@implementation QLMSkinKnob
@end

@interface QLMSkinBar ()
@property (nonatomic) CGRect frame;
@property (nonatomic) QLMSkinColor track;
@property (nonatomic) QLMSkinColor fill;
@property (nonatomic) CGFloat radius;
@end

@implementation QLMSkinBar
@end

@interface QLMSkinElement ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic) CGRect frame;
@property (nonatomic) QLMSkinAnchors anchors;
@property (nonatomic, nullable) QLMSkinStyle *style;
@property (nonatomic, copy) NSDictionary<NSString *, QLMSkinTextSlot *> *text;
@property (nonatomic) NSInteger columns;
@property (nonatomic) NSInteger rows;
@property (nonatomic) CGSize gap;
@property (nonatomic) CGRect ledFrame;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *symbols;
@property (nonatomic) QLMSkinColor disabledOverlay;
@property (nonatomic, nullable) QLMSkinBar *bar;
@end

@implementation QLMSkinElement

- (instancetype)init {
    self = [super init];
    if (self) {
        _text = @{};
        _symbols = @{};
    }
    return self;
}

@end


@interface QLMSkin ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSURL *directory;
@property (nonatomic) CGSize windowSize;
@property (nonatomic, copy) NSDictionary<NSString *, QLMSkinElement *> *elements;
@property (nonatomic) QLMSkinElement *osd;
@property (nonatomic) QLMSkinButton *button;
@property (nonatomic) QLMSkinKnob *knob;
@property (nonatomic) QLMSkinLED *led;
@property (nonatomic) QLMSkinMarkings *markings;
@property (nonatomic, copy) NSArray<NSString *> *imageNames;
- (instancetype)initPrivately;
@end

#pragma mark - The reader

// Reads one skin.json. The first refusal is the one kept, so the message
// names the first fault. A step after it only has to not crash.
@interface QLMSkinReader : NSObject
@property (nonatomic) NSURL *directory;
@property (nonatomic, copy, nullable) NSString *failure;
@property (nonatomic, copy) NSDictionary<NSString *, NSValue *> *palette;  // QLMSkinColor values
@property (nonatomic) BOOL unreadable;  // no file, or not JSON
@property (nonatomic) NSMutableOrderedSet<NSString *> *imageNames;
- (void)fail:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
@end

@implementation QLMSkinReader

- (void)fail:(NSString *)format, ... {
    if (self.failure != nil) {
        return;
    }
    va_list args;
    va_start(args, format);
    self.failure = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
}

- (BOOL)failed {
    return self.failure != nil;
}

#pragma mark Shapes

- (nullable NSDictionary *)object:(id)value at:(NSString *)path {
    if (![value isKindOfClass:NSDictionary.class]) {
        [self fail:@"%@ is not an object", path];
        return nil;
    }
    return value;
}

// Refuses a key outside `allowed`, and a missing one of `required`. NO once
// anything has failed, so the caller reads no key of a bad object.
- (BOOL)checkKeys:(NSDictionary *)object at:(NSString *)path
          allowed:(NSArray<NSString *> *)allowed
         required:(NSArray<NSString *> *)required {
    if ([self failed]) {
        return NO;
    }
    for (id key in [object.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![allowed containsObject:key]) {
            [self fail:@"%@ has an unknown key, %@", path, key];
            return NO;
        }
    }
    for (NSString *key in required) {
        if (object[key] == nil) {
            [self fail:@"%@ has no %@", path, key];
            return NO;
        }
    }
    return YES;
}

- (CGFloat)number:(id)value at:(NSString *)path {
    if (!QLMSkinIsNumber(value) || !isfinite([value doubleValue])) {
        [self fail:@"%@ is not a number", path];
        return 0;
    }
    return [value doubleValue];
}

- (CGFloat)number:(id)value at:(NSString *)path orDefault:(CGFloat)fallback {
    return value == nil ? fallback : [self number:value at:path];
}

- (CGFloat)positive:(id)value at:(NSString *)path {
    CGFloat number = [self number:value at:path];
    if (number <= 0) {
        [self fail:@"%@ is not above 0", path];
    }
    return number;
}

- (CGFloat)nonNegative:(id)value at:(NSString *)path orDefault:(CGFloat)fallback {
    CGFloat number = [self number:value at:path orDefault:fallback];
    if (number < 0) {
        [self fail:@"%@ is below 0", path];
    }
    return number;
}

- (BOOL)boolean:(id)value at:(NSString *)path {
    if (value == nil) {
        return NO;
    }
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
        [self fail:@"%@ is not true or false", path];
        return NO;
    }
    return [value boolValue];
}

- (nullable NSString *)string:(id)value at:(NSString *)path {
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        [self fail:@"%@ is not a name", path];
        return nil;
    }
    return value;
}

// 1 on a failure, so a grid's cells can still be counted.
- (NSInteger)integer:(id)value at:(NSString *)path {
    CGFloat number = [self number:value at:path];
    if (number != floor(number) || number < 1 || number > 100) {
        [self fail:@"%@ is not a whole number from 1 to 100", path];
        return 1;
    }
    return (NSInteger)number;
}

- (nullable NSArray *)numbers:(id)value count:(NSUInteger)count at:(NSString *)path {
    if (![value isKindOfClass:NSArray.class] || [value count] != count) {
        [self fail:@"%@ is not %lu numbers", path, (unsigned long)count];
        return nil;
    }
    for (NSUInteger i = 0; i < count; i++) {
        [self number:value[i] at:path];
    }
    return [self failed] ? nil : value;
}

- (CGRect)frame:(id)value at:(NSString *)path {
    NSArray *numbers = [self numbers:value count:4 at:path];
    if (numbers == nil) {
        return CGRectZero;
    }
    CGRect frame = CGRectMake([numbers[0] doubleValue], [numbers[1] doubleValue],
                              [numbers[2] doubleValue], [numbers[3] doubleValue]);
    if (frame.size.width <= 0 || frame.size.height <= 0) {
        [self fail:@"%@ has no area", path];
    }
    return frame;
}

- (CGSize)size:(id)value at:(NSString *)path {
    NSArray *numbers = [self numbers:value count:2 at:path];
    return numbers ? CGSizeMake([numbers[0] doubleValue], [numbers[1] doubleValue]) : CGSizeZero;
}

// [top, left, bottom, right], as the pack orders them. A number is all four.
- (NSEdgeInsets)insets:(id)value at:(NSString *)path {
    if (value == nil) {
        return NSEdgeInsetsMake(0, 0, 0, 0);
    }
    if ([value isKindOfClass:NSNumber.class]) {
        CGFloat inset = [self nonNegative:value at:path orDefault:0];
        return NSEdgeInsetsMake(inset, inset, inset, inset);
    }
    NSArray *numbers = [self numbers:value count:4 at:path];
    if (numbers == nil) {
        return NSEdgeInsetsMake(0, 0, 0, 0);
    }
    return NSEdgeInsetsMake([numbers[0] doubleValue], [numbers[1] doubleValue],
                            [numbers[2] doubleValue], [numbers[3] doubleValue]);
}

- (QLMSkinAnchors)anchors:(id)value at:(NSString *)path {
    if (value == nil) {
        return QLMSkinAnchorLeft | QLMSkinAnchorTop;
    }
    if (![value isKindOfClass:NSArray.class]) {
        [self fail:@"%@ is not a list of edges", path];
        return 0;
    }
    NSDictionary<NSString *, NSNumber *> *edges = @{
        @"left": @(QLMSkinAnchorLeft), @"right": @(QLMSkinAnchorRight),
        @"top": @(QLMSkinAnchorTop), @"bottom": @(QLMSkinAnchorBottom),
    };
    QLMSkinAnchors anchors = 0;
    for (id edge in value) {
        NSNumber *bit = [edge isKindOfClass:NSString.class] ? edges[edge] : nil;
        if (bit == nil) {
            [self fail:@"%@ has %@, which is not left, right, top, or bottom", path, edge];
            return 0;
        }
        anchors |= bit.unsignedIntegerValue;
    }
    return anchors;
}

- (NSInteger)choice:(id)value among:(NSArray<NSString *> *)names at:(NSString *)path orDefault:(NSInteger)fallback {
    if (value == nil) {
        return fallback;
    }
    NSUInteger index = [value isKindOfClass:NSString.class] ? [names indexOfObject:value] : NSNotFound;
    if (index == NSNotFound) {
        [self fail:@"%@ is not one of %@", path, [names componentsJoinedByString:@", "]];
        return fallback;
    }
    return (NSInteger)index;
}

- (QLMSkinWeight)weight:(id)value at:(NSString *)path {
    NSArray *names = @[@"ultralight", @"thin", @"light", @"regular", @"medium", @"semibold", @"bold", @"heavy", @"black"];
    return [self choice:value among:names at:path orDefault:QLMSkinWeightRegular];
}

- (void)checkFrame:(CGRect)frame inside:(CGSize)size named:(NSString *)surface at:(NSString *)path {
    const CGFloat slack = 0.001;
    if (CGRectGetMinX(frame) < -slack || CGRectGetMinY(frame) < -slack
        || CGRectGetMaxX(frame) > size.width + slack || CGRectGetMaxY(frame) > size.height + slack) {
        [self fail:@"%@ is outside the %@, %g by %g", path, surface, size.width, size.height];
    }
}

#pragma mark Colors

// Not vibe-libs' hex reader, which makes an NSColor: this reader is
// Foundation only.
static BOOL QLMSkinParseHex(NSString *text, QLMSkinColor *color) {
    if (!(text.length == 7 || text.length == 9) || [text characterAtIndex:0] != '#') {
        return NO;
    }
    unsigned components[4] = {0, 0, 0, 255};
    NSUInteger count = (text.length - 1) / 2;
    for (NSUInteger i = 0; i < count; i++) {
        unsigned value = 0;
        for (NSUInteger j = 0; j < 2; j++) {
            unichar c = [text characterAtIndex:1 + 2 * i + j];
            unsigned digit;
            if (c >= '0' && c <= '9') {
                digit = c - '0';
            }
            else if (c >= 'a' && c <= 'f') {
                digit = c - 'a' + 10;
            }
            else if (c >= 'A' && c <= 'F') {
                digit = c - 'A' + 10;
            }
            else {
                return NO;
            }
            value = value * 16 + digit;
        }
        components[i] = value;
    }
    *color = (QLMSkinColor){components[0] / 255.0, components[1] / 255.0, components[2] / 255.0, components[3] / 255.0};
    return YES;
}

// "#RRGGBB", "#RRGGBBAA", or a name in the palette.
- (QLMSkinColor)color:(id)value at:(NSString *)path {
    QLMSkinColor color = QLMSkinColorClear;
    if (![value isKindOfClass:NSString.class]) {
        [self fail:@"%@ is not a color", path];
        return color;
    }
    if ([value hasPrefix:@"#"]) {
        if (!QLMSkinParseHex(value, &color)) {
            [self fail:@"%@ is %@, which is not #RRGGBB or #RRGGBBAA", path, value];
        }
        return color;
    }
    NSValue *named = self.palette[value];
    if (named == nil) {
        [self fail:@"%@ names %@, which the palette lacks", path, value];
        return color;
    }
    [named getValue:&color size:sizeof color];
    return color;
}

- (QLMSkinColor)color:(id)value at:(NSString *)path orDefault:(QLMSkinColor)fallback {
    return value == nil ? fallback : [self color:value at:path];
}

- (void)readPalette:(id)value {
    NSMutableDictionary<NSString *, NSValue *> *palette = [NSMutableDictionary dictionary];
    NSDictionary *object = [self object:value at:@"palette"];
    for (id name in [object.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        QLMSkinColor color = QLMSkinColorClear;
        if (![object[name] isKindOfClass:NSString.class] || !QLMSkinParseHex(object[name], &color)) {
            [self fail:@"%@ is %@, which is not #RRGGBB or #RRGGBBAA", QLMSkinKey(@"palette", name), object[name]];
            return;
        }
        palette[name] = [NSValue valueWithBytes:&color objCType:@encode(QLMSkinColor)];
    }
    self.palette = palette;
}

#pragma mark Parts

- (nullable QLMSkinShadow *)shadow:(id)value at:(NSString *)path {
    if (value == nil) {
        return nil;
    }
    NSDictionary *object = [self object:value at:path];
    if (![self checkKeys:object at:path allowed:@[@"color", @"blur", @"offset"] required:@[@"color"]]) {
        return nil;
    }
    QLMSkinShadow *shadow = [[QLMSkinShadow alloc] init];
    shadow.color = [self color:object[@"color"] at:QLMSkinKey(path, @"color")];
    shadow.blur = [self nonNegative:object[@"blur"] at:QLMSkinKey(path, @"blur") orDefault:0];
    shadow.offset = object[@"offset"] ? [self size:object[@"offset"] at:QLMSkinKey(path, @"offset")] : CGSizeZero;
    return shadow;
}

- (QLMSkinFocus *)focus:(id)value at:(NSString *)path {
    QLMSkinFocus *focus = [[QLMSkinFocus alloc] init];
    NSDictionary *object = [self object:value at:path];
    if (![self checkKeys:object at:path allowed:@[@"color", @"width", @"radius", @"outset"] required:@[@"color"]]) {
        return focus;
    }
    focus.color = [self color:object[@"color"] at:QLMSkinKey(path, @"color")];
    focus.width = [self nonNegative:object[@"width"] at:QLMSkinKey(path, @"width") orDefault:2];
    focus.radius = [self nonNegative:object[@"radius"] at:QLMSkinKey(path, @"radius") orDefault:0];
    focus.outset = [self number:object[@"outset"] at:QLMSkinKey(path, @"outset") orDefault:0];
    return focus;
}

// One draw block, over `base`'s values. A state's block overrides only what
// it names.
- (QLMSkinDraw *)draw:(NSDictionary *)object over:(nullable QLMSkinDraw *)base at:(NSString *)path {
    QLMSkinDraw *draw = base ? [base copy] : [[QLMSkinDraw alloc] init];
    if (object[@"fill"] && object[@"gradient"]) {
        [self fail:@"%@ has both a fill and a gradient", path];
        return draw;
    }
    if (object[@"fill"]) {
        draw.fill = [self color:object[@"fill"] at:QLMSkinKey(path, @"fill")];
        draw.hasGradient = NO;
    }
    if (object[@"gradient"]) {
        NSArray *stops = object[@"gradient"];
        NSString *gradient = QLMSkinKey(path, @"gradient");
        if (![stops isKindOfClass:NSArray.class] || stops.count != 2) {
            [self fail:@"%@ is not two colors, top then bottom", gradient];
            return draw;
        }
        draw.gradientTop = [self color:stops[0] at:gradient];
        draw.gradientBottom = [self color:stops[1] at:gradient];
        draw.hasGradient = YES;
        draw.fill = QLMSkinColorClear;
    }
    if (object[@"border"]) {
        draw.border = [self color:object[@"border"] at:QLMSkinKey(path, @"border")];
        if (object[@"borderWidth"] == nil && draw.borderWidth == 0) {
            draw.borderWidth = 1;
        }
    }
    if (object[@"borderWidth"]) {
        draw.borderWidth = [self nonNegative:object[@"borderWidth"] at:QLMSkinKey(path, @"borderWidth") orDefault:0];
    }
    if (object[@"radius"]) {
        draw.radius = [self nonNegative:object[@"radius"] at:QLMSkinKey(path, @"radius") orDefault:0];
    }
    if (object[@"inset"]) {
        draw.inset = [self number:object[@"inset"] at:QLMSkinKey(path, @"inset")];
    }
    if (object[@"shadow"]) {
        draw.shadow = [self shadow:object[@"shadow"] at:QLMSkinKey(path, @"shadow")];
    }
    if (object[@"rings"]) {
        NSArray *rings = object[@"rings"];
        if (![rings isKindOfClass:NSArray.class]) {
            [self fail:@"%@ is not a list", QLMSkinKey(path, @"rings")];
            return draw;
        }
        NSMutableArray<QLMSkinRing *> *read = [NSMutableArray array];
        for (NSUInteger i = 0; i < rings.count; i++) {
            NSString *ringPath = [NSString stringWithFormat:@"%@.rings[%lu]", path, (unsigned long)i];
            NSDictionary *ringObject = [self object:rings[i] at:ringPath];
            if (![self checkKeys:ringObject at:ringPath allowed:@[@"inset", @"color", @"width"] required:@[@"color"]]) {
                return draw;
            }
            QLMSkinRing *ring = [[QLMSkinRing alloc] init];
            ring.inset = [self number:ringObject[@"inset"] at:QLMSkinKey(ringPath, @"inset") orDefault:0];
            ring.color = [self color:ringObject[@"color"] at:QLMSkinKey(ringPath, @"color")];
            ring.width = [self nonNegative:ringObject[@"width"] at:QLMSkinKey(ringPath, @"width") orDefault:1];
            [read addObject:ring];
        }
        draw.rings = read;
    }
    return draw;
}

// An element's material: "image", with "capInsets", or "draw", never both.
// `states` are the states it takes: one, four, or eight. An image's cap
// insets must leave a middle in `size`.
- (nullable QLMSkinStyle *)style:(NSDictionary *)object states:(NSUInteger)states fits:(CGSize)size at:(NSString *)path {
    if ([self failed]) {
        return nil;
    }
    id image = object[@"image"];
    id draw = object[@"draw"];
    if (image && draw) {
        [self fail:@"%@ has both an image and a draw", path];
        return nil;
    }
    if (!image && !draw) {
        [self fail:@"%@ has neither an image nor a draw", path];
        return nil;
    }
    if (draw && object[@"capInsets"]) {
        [self fail:@"%@ has capInsets but no image", path];
        return nil;
    }
    QLMSkinStyle *style = [[QLMSkinStyle alloc] init];
    style.hasStates = states > 1;
    if (image) {
        style.imageName = [self string:image at:QLMSkinKey(path, @"image")];
        if (style.imageName && !QLMSkinIsPlainName(style.imageName)) {
            [self fail:@"%@.image is %@, which is not a file name in png/", path, style.imageName];
        }
        NSString *insetsPath = QLMSkinKey(path, @"capInsets");
        NSEdgeInsets insets = [self insets:object[@"capInsets"] at:insetsPath];
        if (insets.top < 0 || insets.left < 0 || insets.bottom < 0 || insets.right < 0) {
            [self fail:@"%@ has an inset below 0", insetsPath];
        }
        if (insets.left + insets.right > size.width || insets.top + insets.bottom > size.height) {
            [self fail:@"%@ is larger than its frame, %g by %g", insetsPath, size.width, size.height];
        }
        style.capInsets = insets;
        for (NSUInteger state = 0; state < states && ![self failed]; state++) {
            [self checkImage:[style imageNameForState:(QLMSkinState)state] at:path];
        }
        return [self failed] ? nil : style;
    }
    NSString *drawPath = QLMSkinKey(path, @"draw");
    NSDictionary *drawObject = [self object:draw at:drawPath];
    NSArray *keys = @[@"fill", @"gradient", @"border", @"borderWidth", @"radius", @"inset", @"rings", @"shadow"];
    if (![self checkKeys:drawObject at:drawPath allowed:[keys arrayByAddingObject:@"states"] required:@[]]) {
        return nil;
    }
    QLMSkinDraw *base = [self draw:drawObject over:nil at:drawPath];
    NSDictionary *overrides = @{};
    NSString *statesPath = QLMSkinKey(drawPath, @"states");
    if (drawObject[@"states"]) {
        if (states == 1) {
            [self fail:@"%@ has states, but its element takes one", drawPath];
            return nil;
        }
        overrides = [self object:drawObject[@"states"] at:statesPath];
        NSArray<NSString *> *names = [QLMSkinStateNames() subarrayWithRange:NSMakeRange(1, states - 1)];
        if (![self checkKeys:overrides at:statesPath allowed:names required:@[]]) {
            return nil;
        }
    }
    // A selected state takes selected's overrides, then its own.
    NSMutableArray<QLMSkinDraw *> *draws = [NSMutableArray array];
    for (NSUInteger state = 0; state < states; state++) {
        QLMSkinDraw *resolved = base;
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        if (state > QLMSkinStateSelected) {
            [chain addObject:@"selected"];
        }
        if (state != QLMSkinStateNormal) {
            [chain addObject:QLMSkinStateName((QLMSkinState)state)];
        }
        for (NSString *link in chain) {
            if (overrides[link] == nil) {
                continue;
            }
            NSString *linkPath = QLMSkinKey(statesPath, link);
            NSDictionary *linkObject = [self object:overrides[link] at:linkPath];
            if (![self checkKeys:linkObject at:linkPath allowed:keys required:@[]]) {
                return nil;
            }
            resolved = [self draw:linkObject over:resolved at:linkPath];
        }
        [draws addObject:resolved];
    }
    style.draws = draws;
    return [self failed] ? nil : style;
}

- (void)checkImage:(NSString *)name at:(NSString *)path {
    if (self.imageNames == nil) {
        self.imageNames = [NSMutableOrderedSet orderedSet];
    }
    [self.imageNames addObject:name];
    for (NSNumber *scale in @[@1, @2]) {
        NSString *file = QLMSkinImagePath(name, scale.integerValue);
        if (![NSFileManager.defaultManager fileExistsAtPath:[self.directory URLByAppendingPathComponent:file].path]) {
            [self fail:@"%@ names the image %@, but the skin has no %@", path, name, file];
            return;
        }
    }
}

// A slot. `placed` is NO for the OSD's, which has no layout to place them
// by.
- (QLMSkinTextSlot *)slot:(id)value placed:(BOOL)placed at:(NSString *)path {
    QLMSkinTextSlot *slot = [[QLMSkinTextSlot alloc] init];
    NSDictionary *object = [self object:value at:path];
    NSArray *allowed = @[@"frame", @"anchors", @"scales", @"font", @"mono", @"size", @"weight", @"italic",
                         @"alignment", @"color", @"tracking", @"accent"];
    if (![self checkKeys:object at:path allowed:allowed required:@[@"frame", @"size", @"color"]]) {
        return slot;
    }
    for (NSString *key in @[@"anchors", @"scales"]) {
        if (!placed && object[key] != nil) {
            [self fail:@"%@ has %@, but the OSD keeps its size", path, key];
            return slot;
        }
    }
    slot.frame = [self frame:object[@"frame"] at:QLMSkinKey(path, @"frame")];
    slot.anchors = [self anchors:object[@"anchors"] at:QLMSkinKey(path, @"anchors")];
    slot.scales = [self boolean:object[@"scales"] at:QLMSkinKey(path, @"scales")];
    slot.fontName = object[@"font"] ? [self string:object[@"font"] at:QLMSkinKey(path, @"font")] : nil;
    slot.mono = [self boolean:object[@"mono"] at:QLMSkinKey(path, @"mono")];
    slot.size = [self positive:object[@"size"] at:QLMSkinKey(path, @"size")];
    slot.weight = [self weight:object[@"weight"] at:QLMSkinKey(path, @"weight")];
    slot.italic = [self boolean:object[@"italic"] at:QLMSkinKey(path, @"italic")];
    slot.alignment = [self choice:object[@"alignment"] among:@[@"left", @"center", @"right"]
                               at:QLMSkinKey(path, @"alignment") orDefault:QLMSkinAlignmentLeft];
    slot.color = [self color:object[@"color"] at:QLMSkinKey(path, @"color")];
    slot.tracking = [self number:object[@"tracking"] at:QLMSkinKey(path, @"tracking") orDefault:0];
    slot.accentColor = [self color:object[@"accent"] at:QLMSkinKey(path, @"accent") orDefault:QLMSkinColorClear];
    return slot;
}

- (NSDictionary<NSString *, QLMSkinTextSlot *> *)slots:(id)value at:(NSString *)path
                                              required:(NSArray<NSString *> *)required
                                              optional:(NSArray<NSString *> *)optional
                                                placed:(BOOL)placed {
    if (value == nil && required.count == 0) {
        return @{};
    }
    NSDictionary *object = [self object:value at:path];
    NSArray<NSString *> *ignored = QLMSkinIgnoredKeys()[path] ?: @[];
    NSArray<NSString *> *allowed = [[required arrayByAddingObjectsFromArray:optional] arrayByAddingObjectsFromArray:ignored];
    if (![self checkKeys:object at:path allowed:allowed required:required]) {
        return @{};
    }
    NSMutableDictionary<NSString *, QLMSkinTextSlot *> *slots = [NSMutableDictionary dictionary];
    for (NSString *name in [object.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![ignored containsObject:name]) {
            slots[name] = [self slot:object[name] placed:placed at:QLMSkinKey(path, name)];
        }
    }
    return slots;
}

#pragma mark Elements

// The element, with its frame, anchors, and text. Nil once anything has
// failed, so the caller reads no key of a bad object.
- (nullable QLMSkinElement *)element:(NSString *)name
                                from:(NSDictionary *)elements
                                keys:(NSArray<NSString *> *)own
                            required:(NSArray<NSString *> *)requiredKeys
                               slots:(NSArray<NSString *> *)slots
                       optionalSlots:(NSArray<NSString *> *)optionalSlots {
    NSString *path = QLMSkinKey(@"elements", name);
    NSDictionary *object = [self object:elements[name] at:path];
    NSArray *required = [@[@"frame"] arrayByAddingObjectsFromArray:requiredKeys];
    if (slots.count > 0) {
        required = [required arrayByAddingObject:@"text"];
    }
    NSArray *allowed = [@[@"frame", @"anchors", @"text"] arrayByAddingObjectsFromArray:own];
    if (![self checkKeys:object at:path allowed:allowed required:required]) {
        return nil;
    }
    QLMSkinElement *element = [[QLMSkinElement alloc] init];
    element.name = name;
    element.frame = [self frame:object[@"frame"] at:QLMSkinKey(path, @"frame")];
    element.anchors = [self anchors:object[@"anchors"] at:QLMSkinKey(path, @"anchors")];
    element.text = [self slots:object[@"text"] at:QLMSkinKey(path, @"text") required:slots optional:optionalSlots
                        placed:YES];
    return [self failed] ? nil : element;
}

// A grid's cell, at the skin's size.
static CGSize QLMSkinCellSize(QLMSkinElement *grid) {
    return QLMSkinGridCellSize(grid.frame.size, grid.columns, grid.rows, grid.gap);
}

- (void)readGrid:(QLMSkinElement *)element from:(NSDictionary *)object cells:(NSInteger)least {
    NSString *path = QLMSkinKey(@"elements", element.name);
    element.columns = [self integer:object[@"columns"] at:QLMSkinKey(path, @"columns")];
    element.rows = [self integer:object[@"rows"] at:QLMSkinKey(path, @"rows")];
    if (object[@"gap"]) {
        element.gap = [self size:object[@"gap"] at:QLMSkinKey(path, @"gap")];
    }
    if (element.columns * element.rows < least) {
        [self fail:@"%@ has %ld cells, fewer than its %ld buttons", path, (long)(element.columns * element.rows), (long)least];
    }
    if (element.gap.width < 0 || element.gap.height < 0) {
        [self fail:@"%@.gap is below 0", path];
    }
    CGSize cell = QLMSkinCellSize(element);
    if (cell.width <= 0 || cell.height <= 0) {
        [self fail:@"%@'s gap leaves its cells no room", path];
    }
}

// The button's LED fits the smallest grid cell.
- (void)checkLED:(QLMSkinButton *)button inCell:(CGSize)cell {
    if (button.ledSize <= 0) {
        return;
    }
    if (button.ledSize > cell.height) {
        [self fail:@"button.led.size is taller than the button, %g", cell.height];
    }
    else if (button.ledSize + button.ledGap > cell.width) {
        [self fail:@"button.led leaves the title no room in the button's width, %g", cell.width];
    }
}

// Every drawn radius of the knob fits in half its frame, with the round
// caps' and the strokes' half-widths.
- (void)checkKnob:(QLMSkinKnob *)knob inFrame:(CGRect)frame {
    CGFloat half = MIN(frame.size.width, frame.size.height) / 2;
    NSMutableArray<NSArray *> *radii = [NSMutableArray arrayWithArray:@[
        @[@"elements.knob.body.size", @(knob.bodySize / 2)],
        @[@"elements.knob.pointer.outer", @(knob.pointerOuter + knob.pointerWidth / 2)],
        @[@"elements.knob.focus", @(knob.bodySize / 2 + QLMSkinFocusReach(knob.focus))],
    ]];
    if (knob.tickCount > 0) {
        [radii addObject:@[@"elements.knob.ticks.outer", @(knob.tickOuter + knob.tickWidth / 2)]];
    }
    if (knob.hasArc) {
        [radii addObject:@[@"elements.knob.arc.radius", @(knob.arcRadius + knob.arcWidth / 2)]];
    }
    QLMSkinDraw *draw = [knob.body drawForState:QLMSkinStateNormal];
    for (NSUInteger i = 0; i < draw.rings.count; i++) {
        NSString *ring = [NSString stringWithFormat:@"elements.knob.body.draw.rings[%lu]", (unsigned long)i];
        [radii addObject:@[ring, @(knob.bodySize / 2 - draw.inset - draw.rings[i].inset)]];
    }
    for (NSArray *radius in radii) {
        if ([radius[1] doubleValue] > half + 0.001) {
            [self fail:@"%@ reaches past half the knob's frame, %g", radius[0], half];
            return;
        }
    }
}

// A face's insets. Each lies within the image's cap insets, so it holds at
// any size, and the face keeps room in `cell`.
- (NSEdgeInsets)face:(id)value of:(QLMSkinStyle *)style cell:(CGSize)cell at:(NSString *)path {
    NSEdgeInsets face = [self insets:value at:path];
    NSEdgeInsets caps = style.imageName != nil ? style.capInsets : NSEdgeInsetsMake(INFINITY, INFINITY, INFINITY, INFINITY);
    if (face.top < 0 || face.left < 0 || face.bottom < 0 || face.right < 0) {
        [self fail:@"%@ is below 0", path];
    }
    else if (face.top > caps.top || face.left > caps.left || face.bottom > caps.bottom || face.right > caps.right) {
        [self fail:@"%@ reaches past button.capInsets", path];
    }
    else if (face.top + face.bottom >= cell.height || face.left + face.right >= cell.width) {
        [self fail:@"%@ leaves the face no room in the button, %g by %g", path, cell.width, cell.height];
    }
    return face;
}

// The button, its face fitting `cell`, the smallest grid cell.
- (QLMSkinButton *)button:(id)value cell:(CGSize)cell {
    QLMSkinButton *button = [[QLMSkinButton alloc] init];
    NSDictionary *object = [self object:value at:@"button"];
    NSArray *keys = @[@"image", @"draw", @"capInsets", @"title", @"focus", @"led", @"face", @"pressedFace"];
    if (![self checkKeys:object at:@"button" allowed:keys required:@[@"title", @"focus"]]) {
        return button;
    }
    button.style = [self style:object states:8 fits:cell at:@"button"];
    button.face = [self face:object[@"face"] of:button.style cell:cell at:@"button.face"];
    button.pressedFace = object[@"pressedFace"]
                             ? [self face:object[@"pressedFace"] of:button.style cell:cell at:@"button.pressedFace"]
                             : button.face;
    button.focus = [self focus:object[@"focus"] at:@"button.focus"];

    NSString *titlePath = @"button.title";
    NSDictionary *title = [self object:object[@"title"] at:titlePath];
    NSArray *titleKeys = @[@"font", @"size", @"weight", @"tracking", @"color", @"selectedColor", @"disabledColor", @"prefixColor"];
    if ([self checkKeys:title at:titlePath allowed:titleKeys required:@[@"size", @"color"]]) {
        QLMSkinTitle *read = [[QLMSkinTitle alloc] init];
        read.fontName = title[@"font"] ? [self string:title[@"font"] at:QLMSkinKey(titlePath, @"font")] : nil;
        read.size = [self positive:title[@"size"] at:QLMSkinKey(titlePath, @"size")];
        read.weight = [self weight:title[@"weight"] at:QLMSkinKey(titlePath, @"weight")];
        read.tracking = [self number:title[@"tracking"] at:QLMSkinKey(titlePath, @"tracking") orDefault:0];
        read.color = [self color:title[@"color"] at:QLMSkinKey(titlePath, @"color")];
        read.selectedColor = [self color:title[@"selectedColor"] at:QLMSkinKey(titlePath, @"selectedColor") orDefault:read.color];
        read.disabledColor = [self color:title[@"disabledColor"] at:QLMSkinKey(titlePath, @"disabledColor") orDefault:read.color];
        read.prefixColor = [self color:title[@"prefixColor"] at:QLMSkinKey(titlePath, @"prefixColor") orDefault:read.color];
        button.title = read;
    }

    if (object[@"led"]) {
        NSDictionary *led = [self object:object[@"led"] at:@"button.led"];
        if ([self checkKeys:led at:@"button.led" allowed:@[@"size", @"gap"] required:@[@"size"]]) {
            button.ledSize = [self positive:led[@"size"] at:@"button.led.size"];
            button.ledGap = [self nonNegative:led[@"gap"] at:@"button.led.gap" orDefault:6];
            [self checkLED:button inCell:cell];
        }
    }
    return button;
}

- (QLMSkinKnob *)knob:(NSDictionary *)object {
    QLMSkinKnob *knob = [[QLMSkinKnob alloc] init];
    NSString *path = @"elements.knob";

    NSString *bodyPath = QLMSkinKey(path, @"body");
    NSDictionary *body = [self object:object[@"body"] at:bodyPath];
    if ([self checkKeys:body at:bodyPath allowed:@[@"size", @"image", @"draw", @"capInsets"] required:@[@"size"]]) {
        knob.bodySize = [self positive:body[@"size"] at:QLMSkinKey(bodyPath, @"size")];
        knob.body = [self style:body states:4 fits:CGSizeMake(knob.bodySize, knob.bodySize) at:bodyPath];
    }

    if (object[@"ticks"]) {
        NSString *ticksPath = QLMSkinKey(path, @"ticks");
        NSDictionary *ticks = [self object:object[@"ticks"] at:ticksPath];
        if ([self checkKeys:ticks at:ticksPath allowed:@[@"count", @"inner", @"outer", @"width", @"color"]
                   required:@[@"count", @"inner", @"outer", @"color"]]) {
            knob.tickCount = [self integer:ticks[@"count"] at:QLMSkinKey(ticksPath, @"count")];
            knob.tickInner = [self positive:ticks[@"inner"] at:QLMSkinKey(ticksPath, @"inner")];
            knob.tickOuter = [self positive:ticks[@"outer"] at:QLMSkinKey(ticksPath, @"outer")];
            knob.tickWidth = [self nonNegative:ticks[@"width"] at:QLMSkinKey(ticksPath, @"width") orDefault:1];
            knob.tickColor = [self color:ticks[@"color"] at:QLMSkinKey(ticksPath, @"color")];
        }
    }

    NSString *pointerPath = QLMSkinKey(path, @"pointer");
    NSDictionary *pointer = [self object:object[@"pointer"] at:pointerPath];
    if ([self checkKeys:pointer at:pointerPath allowed:@[@"inner", @"outer", @"width", @"color", @"disabledColor"]
               required:@[@"inner", @"outer", @"color"]]) {
        knob.pointerInner = [self nonNegative:pointer[@"inner"] at:QLMSkinKey(pointerPath, @"inner") orDefault:0];
        knob.pointerOuter = [self positive:pointer[@"outer"] at:QLMSkinKey(pointerPath, @"outer")];
        knob.pointerWidth = [self nonNegative:pointer[@"width"] at:QLMSkinKey(pointerPath, @"width") orDefault:2];
        knob.pointerColor = [self color:pointer[@"color"] at:QLMSkinKey(pointerPath, @"color")];
        knob.pointerDisabledColor = [self color:pointer[@"disabledColor"] at:QLMSkinKey(pointerPath, @"disabledColor")
                                      orDefault:knob.pointerColor];
    }

    knob.shadow = [self shadow:object[@"shadow"] at:QLMSkinKey(path, @"shadow")];
    knob.focus = [self focus:object[@"focus"] at:QLMSkinKey(path, @"focus")];

    if (object[@"arc"]) {
        NSString *arcPath = QLMSkinKey(path, @"arc");
        NSDictionary *arc = [self object:object[@"arc"] at:arcPath];
        if ([self checkKeys:arc at:arcPath allowed:@[@"radius", @"width", @"track", @"fill"]
                   required:@[@"radius", @"track", @"fill"]]) {
            knob.hasArc = YES;
            knob.arcRadius = [self positive:arc[@"radius"] at:QLMSkinKey(arcPath, @"radius")];
            knob.arcWidth = [self nonNegative:arc[@"width"] at:QLMSkinKey(arcPath, @"width") orDefault:3];
            knob.arcTrack = [self color:arc[@"track"] at:QLMSkinKey(arcPath, @"track")];
            knob.arcFill = [self color:arc[@"fill"] at:QLMSkinKey(arcPath, @"fill")];
        }
    }
    return knob;
}

- (QLMSkinLED *)led:(id)value {
    QLMSkinLED *led = [[QLMSkinLED alloc] init];
    NSDictionary *object = [self object:value at:@"led"];
    if ([self checkKeys:object at:@"led" allowed:@[@"on", @"off", @"glow"] required:@[@"on", @"off"]]) {
        led.on = [self color:object[@"on"] at:@"led.on"];
        led.off = [self color:object[@"off"] at:@"led.off"];
        led.glow = [self nonNegative:object[@"glow"] at:@"led.glow" orDefault:0];
    }
    return led;
}

- (QLMSkinMarkings *)markings:(id)value
                     elements:(NSDictionary<NSString *, QLMSkinElement *> *)elements
                       button:(QLMSkinButton *)button
                       window:(CGSize)window {
    QLMSkinMarkings *markings = [[QLMSkinMarkings alloc] init];
    markings.lines = @[];
    markings.boxes = @[];
    NSDictionary *object = [self object:value at:@"markings"];
    if (![self checkKeys:object at:@"markings" allowed:@[@"color", @"width", @"lines", @"boxes"] required:@[@"color"]]) {
        return markings;
    }
    markings.color = [self color:object[@"color"] at:@"markings.color"];
    markings.width = [self nonNegative:object[@"width"] at:@"markings.width" orDefault:1];

    QLMSkinElement *(^placed)(id, NSString *) = ^QLMSkinElement *(id name, NSString *path) {
        QLMSkinElement *element = [name isKindOfClass:NSString.class] ? elements[name] : nil;
        if (element == nil) {
            [self fail:@"%@ names %@, which is not an element", path, name];
        }
        return element;
    };

    NSMutableArray<QLMSkinLine *> *lines = [NSMutableArray array];
    NSArray *lineObjects = object[@"lines"] ?: @[];
    if (![lineObjects isKindOfClass:NSArray.class]) {
        [self fail:@"markings.lines is not a list"];
        return markings;
    }
    for (NSUInteger i = 0; i < lineObjects.count && ![self failed]; i++) {
        NSString *path = [NSString stringWithFormat:@"markings.lines[%lu]", (unsigned long)i];
        NSDictionary *line = [self object:lineObjects[i] at:path];
        if (![self checkKeys:line at:path allowed:@[@"element", @"y"] required:@[@"element", @"y"]]) {
            break;
        }
        QLMSkinLine *read = [[QLMSkinLine alloc] init];
        QLMSkinElement *element = placed(line[@"element"], QLMSkinKey(path, @"element"));
        read.element = element.name ?: @"";
        read.y = [self number:line[@"y"] at:QLMSkinKey(path, @"y")];
        if (element) {
            [self checkFrame:CGRectMake(element.frame.origin.x, element.frame.origin.y + read.y, element.frame.size.width, 0)
                      inside:window named:@"window" at:path];
        }
        [lines addObject:read];
    }
    markings.lines = lines;

    NSMutableArray<QLMSkinBox *> *boxes = [NSMutableArray array];
    NSArray *boxObjects = object[@"boxes"] ?: @[];
    if (![boxObjects isKindOfClass:NSArray.class]) {
        [self fail:@"markings.boxes is not a list"];
        return markings;
    }
    for (NSUInteger i = 0; i < boxObjects.count && ![self failed]; i++) {
        NSString *path = [NSString stringWithFormat:@"markings.boxes[%lu]", (unsigned long)i];
        NSDictionary *box = [self object:boxObjects[i] at:path];
        if (![self checkKeys:box at:path allowed:@[@"element", @"outset", @"radius", @"gap"] required:@[@"element"]]) {
            break;
        }
        QLMSkinBox *read = [[QLMSkinBox alloc] init];
        QLMSkinElement *element = placed(box[@"element"], QLMSkinKey(path, @"element"));
        read.element = element.name ?: @"";
        read.outset = [self insets:box[@"outset"] at:QLMSkinKey(path, @"outset")];
        read.radius = [self nonNegative:box[@"radius"] at:QLMSkinKey(path, @"radius") orDefault:0];
        if (box[@"gap"]) {
            read.gap = [self string:box[@"gap"] at:QLMSkinKey(path, @"gap")];
            if (element && read.gap && element.text[read.gap] == nil) {
                [self fail:@"%@.gap names %@, which is not a slot of %@", path, read.gap, element.name];
            }
        }
        if (element) {
            [self checkFrame:QLMSkinGrowRect(QLMSkinBoxedRect(element, button, element.frame), read.outset) inside:window
                       named:@"window" at:path];
        }
        [boxes addObject:read];
    }
    markings.boxes = boxes;
    return markings;
}

// The element's frame, and each of its slots' frames, in the window.
- (void)checkElement:(QLMSkinElement *)element inside:(CGSize)window {
    NSString *path = QLMSkinKey(@"elements", element.name);
    [self checkFrame:element.frame inside:window named:@"window" at:QLMSkinKey(path, @"frame")];
    for (NSString *name in [element.text.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        CGRect frame = CGRectOffset(element.text[name].frame, element.frame.origin.x, element.frame.origin.y);
        NSString *slotPath = QLMSkinKey(QLMSkinKey(path, @"text"), name);
        [self checkFrame:frame inside:window named:@"window" at:slotPath];
        // A scaled slot grows from its element's origin, so only one inside
        // its element stays inside the window.
        if (element.text[name].scales) {
            [self checkFrame:element.text[name].frame inside:element.frame.size
                       named:[@"element " stringByAppendingString:element.name] at:slotPath];
        }
    }
}

- (nullable QLMSkin *)read {
    NSURL *file = [self.directory URLByAppendingPathComponent:@"skin.json"];
    NSData *data = [NSData dataWithContentsOfURL:file];
    if (data == nil) {
        self.unreadable = YES;
        [self fail:@"There is no skin.json in %@", self.directory.path];
        return nil;
    }
    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (json == nil) {
        self.unreadable = YES;
        [self fail:@"skin.json is not JSON: %@", jsonError.localizedDescription];
        return nil;
    }
    NSDictionary *root = [self object:json at:@"skin.json"];
    NSArray *keys = @[@"format", @"size", @"palette", @"elements", @"button", @"led", @"markings", @"osd"];
    if (![self checkKeys:root at:@"skin.json" allowed:keys required:keys]) {
        return nil;
    }
    id format = root[@"format"];
    if (!QLMSkinIsNumber(format) || [format doubleValue] != QLMSkinFormat) {
        [self fail:@"skin.json's format is %@, and qlm reads format %d", format, QLMSkinFormat];
        return nil;
    }

    QLMSkin *skin = [[QLMSkin alloc] initPrivately];
    skin.directory = self.directory;
    skin.name = self.directory.lastPathComponent;
    CGSize window = [self size:root[@"size"] at:@"size"];
    skin.windowSize = window;
    if (window.width < QLMSkinReferenceWindowSize.width || window.height < QLMSkinReferenceWindowSize.height) {
        [self fail:@"size is %g by %g, below the reference, %g by %g", window.width, window.height,
                   QLMSkinReferenceWindowSize.width, QLMSkinReferenceWindowSize.height];
    }
    [self readPalette:root[@"palette"]];

    NSDictionary *elements = [self object:root[@"elements"] at:@"elements"];
    NSArray<NSString *> *names = QLMSkinElementNames();
    if (![self checkKeys:elements at:@"elements" allowed:names required:names]) {
        return nil;
    }
    NSArray *styled = @[@"image", @"draw", @"capInsets"];

    QLMSkinElement *panel = [self element:@"panel" from:elements keys:styled required:@[] slots:@[] optionalSlots:@[]];
    panel.style = [self style:elements[@"panel"] states:1 fits:panel.frame.size at:@"elements.panel"];

    QLMSkinElement *nameplate = [self element:@"nameplate" from:elements keys:styled required:@[] slots:@[]
                                optionalSlots:@[@"logo"]];
    nameplate.style = [self style:elements[@"nameplate"] states:1 fits:nameplate.frame.size at:@"elements.nameplate"];

    QLMSkinElement *status = [self element:@"status" from:elements keys:@[@"led"] required:@[@"led"]
                                     slots:@[@"online"] optionalSlots:@[]];
    if (status) {
        status.ledFrame = [self frame:elements[@"status"][@"led"] at:@"elements.status.led"];
        [self checkFrame:CGRectOffset(status.ledFrame, status.frame.origin.x, status.frame.origin.y)
                  inside:window named:@"window" at:@"elements.status.led"];
    }

    QLMSkinElement *groups = [self element:@"groups" from:elements keys:@[@"columns", @"rows", @"gap"]
                                  required:@[@"columns", @"rows"] slots:@[@"groupsTitle", @"message"]
                             optionalSlots:@[]];
    if (groups) {
        [self readGrid:groups from:elements[@"groups"] cells:1];
    }

    QLMSkinElement *display = [self element:@"display" from:elements
                                       keys:[styled arrayByAddingObject:@"disabledOverlay"] required:@[]
                                      slots:@[@"caption", @"level", @"unit", @"output", @"max"] optionalSlots:@[]];
    if (display) {
        display.style = [self style:elements[@"display"] states:1 fits:display.frame.size at:@"elements.display"];
        display.disabledOverlay = [self color:elements[@"display"][@"disabledOverlay"]
                                           at:@"elements.display.disabledOverlay" orDefault:QLMSkinColorClear];
    }

    QLMSkinElement *toggles = [self element:@"toggles" from:elements keys:@[@"columns", @"rows", @"gap"]
                                   required:@[@"columns", @"rows"] slots:@[] optionalSlots:@[]];
    if (toggles) {
        [self readGrid:toggles from:elements[@"toggles"] cells:2];
    }

    QLMSkinElement *knob = [self element:@"knob" from:elements
                                    keys:@[@"body", @"ticks", @"pointer", @"shadow", @"focus", @"arc"]
                                required:@[@"body", @"pointer", @"focus"] slots:@[@"min", @"max", @"caption"]
                           optionalSlots:@[]];
    if (knob) {
        skin.knob = [self knob:elements[@"knob"]];
        [self checkKnob:skin.knob inFrame:knob.frame];
    }

    QLMSkinElement *footer = [self element:@"footer" from:elements keys:@[@"symbols"] required:@[@"symbols"]
                                     slots:@[@"monitors", @"power"] optionalSlots:@[]];
    NSDictionary *symbols = footer ? [self object:elements[@"footer"][@"symbols"] at:@"elements.footer.symbols"] : nil;
    if ([self checkKeys:symbols at:@"elements.footer.symbols" allowed:@[@"monitors", @"power"]
               required:@[@"monitors", @"power"]]) {
        for (NSString *slot in symbols) {
            [self string:symbols[slot] at:QLMSkinKey(@"elements.footer.symbols", slot)];
        }
        footer.symbols = symbols;
    }
    if ([self failed]) {
        return nil;
    }

    NSDictionary<NSString *, QLMSkinElement *> *read = @{
        @"panel": panel, @"nameplate": nameplate, @"status": status, @"groups": groups,
        @"display": display, @"toggles": toggles, @"knob": knob, @"footer": footer,
    };
    for (NSString *name in names) {
        [self checkElement:read[name] inside:window];
    }
    skin.elements = read;

    CGSize groupCell = QLMSkinCellSize(groups);
    CGSize toggleCell = QLMSkinCellSize(toggles);
    skin.button = [self button:root[@"button"]
                          cell:CGSizeMake(MIN(groupCell.width, toggleCell.width), MIN(groupCell.height, toggleCell.height))];
    skin.led = [self led:root[@"led"]];
    skin.markings = [self markings:root[@"markings"] elements:read button:skin.button window:window];
    skin.osd = [self osd:root[@"osd"]];
    skin.imageNames = self.imageNames.array ?: @[];
    return [self failed] ? nil : skin;
}

- (QLMSkinElement *)osd:(id)value {
    QLMSkinElement *osd = [[QLMSkinElement alloc] init];
    osd.name = @"osd";
    NSDictionary *object = [self object:value at:@"osd"];
    if (![self checkKeys:object at:@"osd"
                 allowed:[@[@"size", @"image", @"draw", @"capInsets", @"bar", @"text"] arrayByAddingObjectsFromArray:QLMSkinIgnoredKeys()[@"osd"]]
                required:@[@"size", @"bar", @"text"]]) {
        return osd;
    }
    CGSize size = [self size:object[@"size"] at:@"osd.size"];
    if (size.width < QLMSkinReferenceOSDSize.width || size.height < QLMSkinReferenceOSDSize.height) {
        [self fail:@"osd.size is %g by %g, below the reference, %g by %g", size.width, size.height,
                   QLMSkinReferenceOSDSize.width, QLMSkinReferenceOSDSize.height];
        return osd;
    }
    osd.frame = CGRectMake(0, 0, size.width, size.height);
    osd.style = [self style:object states:1 fits:size at:@"osd"];
    osd.text = [self slots:object[@"text"] at:@"osd.text" required:@[@"level", @"unit", @"title", @"subtitle"] optional:@[]
                    placed:NO];

    NSDictionary *bar = [self object:object[@"bar"] at:@"osd.bar"];
    if ([self checkKeys:bar at:@"osd.bar" allowed:@[@"frame", @"track", @"fill", @"radius"]
               required:@[@"frame", @"track", @"fill"]]) {
        QLMSkinBar *read = [[QLMSkinBar alloc] init];
        read.frame = [self frame:bar[@"frame"] at:@"osd.bar.frame"];
        read.track = [self color:bar[@"track"] at:@"osd.bar.track"];
        read.fill = [self color:bar[@"fill"] at:@"osd.bar.fill"];
        read.radius = [self nonNegative:bar[@"radius"] at:@"osd.bar.radius" orDefault:0];
        [self checkFrame:read.frame inside:size named:@"OSD" at:@"osd.bar.frame"];
        osd.bar = read;
    }
    for (NSString *name in [osd.text.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [self checkFrame:osd.text[name].frame inside:size named:@"OSD" at:QLMSkinKey(@"osd.text", name)];
    }
    return osd;
}

@end
#pragma mark - The skin

@implementation QLMSkin

- (instancetype)initPrivately {
    return [super init];
}

+ (instancetype)skinAtURL:(NSURL *)directory error:(NSError **)error {
    QLMSkinReader *reader = [[QLMSkinReader alloc] init];
    reader.directory = directory;
    reader.palette = @{};
    QLMSkin *skin = [reader read];
    if (skin == nil && error != NULL) {
        *error = [NSError errorWithDomain:QLMSkinErrorDomain
                                     code:reader.unreadable ? QLMSkinErrorUnreadable : QLMSkinErrorInvalid
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The skin %@ is refused. %@.",
                                                                        directory.lastPathComponent, reader.failure]}];
    }
    return skin;
}

- (QLMSkinElement *)element:(NSString *)name {
    QLMSkinElement *element = self.elements[name];
    NSAssert(element != nil, @"no element %@", name);
    return element;
}

- (NSURL *)imageURLForName:(NSString *)name scale:(NSInteger)scale {
    return [self.directory URLByAppendingPathComponent:QLMSkinImagePath(name, scale)];
}

@end
