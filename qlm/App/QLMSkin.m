#import "QLMSkin.h"

#include <math.h>

NSErrorDomain const QLMSkinErrorDomain = @"QLMSkinErrorDomain";

const CGSize QLMSkinReferenceWindowSize = {640, 480};
const CGSize QLMSkinReferenceOSDSize = {300, 72};
const QLMSkinColor QLMSkinColorClear = {0, 0, 0, 0};

static const int QLMSkinFormat = 1;

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

QLMSkinState QLMSkinKnobState(BOOL enabled, BOOL pressed, BOOL hovered) {
    return QLMSkinButtonState(NO, enabled, pressed, hovered);
}

static NSArray<NSString *> *QLMSkinStateNames(void) {
    return @[@"normal", @"hover", @"pressed", @"disabled",
             @"selected", @"selected-hover", @"selected-pressed", @"selected-disabled"];
}

NSString *QLMSkinStateName(QLMSkinState state) {
    return QLMSkinStateNames()[(NSUInteger)state];
}

static NSValue *QLMSkinColorValue(QLMSkinColor color) {
    return [NSValue valueWithBytes:&color objCType:@encode(QLMSkinColor)];
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
@property (nonatomic, copy) NSString *name;
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
@property (nonatomic) CGFloat ledX;
@property (nonatomic) CGFloat ledGap;
@end

@implementation QLMSkinButton
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
@property (nonatomic) CGSize osdSize;
@property (nonatomic, copy) NSDictionary<NSString *, NSValue *> *palette;
@property (nonatomic, copy) NSDictionary<NSString *, QLMSkinElement *> *elements;
@property (nonatomic) QLMSkinElement *osd;
@property (nonatomic) QLMSkinButton *button;
@property (nonatomic) QLMSkinKnob *knob;
@property (nonatomic) QLMSkinLED *led;
@property (nonatomic) QLMSkinMarkings *markings;
- (instancetype)initPrivately;
@end

#pragma mark - The reader

// Reads one skin.json. The first refusal stops the read: each step after it
// returns at once, so the message names the first fault.
@interface QLMSkinReader : NSObject
@property (nonatomic) NSURL *directory;
@property (nonatomic, copy, nullable) NSString *failure;
@property (nonatomic, copy) NSDictionary<NSString *, NSValue *> *palette;
@property (nonatomic) CGSize windowSize;
@property (nonatomic) BOOL unreadable;  // no file, or not JSON
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

// Refuses a key outside `allowed`, and a missing one of `required`.
- (BOOL)checkKeys:(NSDictionary *)object at:(NSString *)path
          allowed:(NSArray<NSString *> *)allowed
         required:(NSArray<NSString *> *)required {
    if ([self failed]) {
        return NO;
    }
    NSArray<NSString *> *keys = [object.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (id key in keys) {
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
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()
        || !isfinite([value doubleValue])) {
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
    if (![self failed] && number <= 0) {
        [self fail:@"%@ is not above 0", path];
    }
    return number;
}

- (CGFloat)nonNegative:(id)value at:(NSString *)path orDefault:(CGFloat)fallback {
    CGFloat number = [self number:value at:path orDefault:fallback];
    if (![self failed] && number < 0) {
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

- (NSInteger)integer:(id)value at:(NSString *)path {
    CGFloat number = [self number:value at:path];
    if (![self failed] && (number != floor(number) || number < 1 || number > 100)) {
        [self fail:@"%@ is not a whole number from 1 to 100", path];
    }
    return [self failed] ? 1 : (NSInteger)number;
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

- (NSEdgeInsets)capInsets:(id)value at:(NSString *)path {
    NSEdgeInsets insets = [self insets:value at:path];
    if (![self failed] && (insets.top < 0 || insets.left < 0 || insets.bottom < 0 || insets.right < 0)) {
        [self fail:@"%@ has an inset below 0", path];
    }
    return insets;
}

// Cap insets that leave no middle to stretch.
- (void)checkInsets:(NSEdgeInsets)insets fit:(CGSize)size at:(NSString *)path {
    if ([self failed]) {
        return;
    }
    if (insets.left + insets.right > size.width || insets.top + insets.bottom > size.height) {
        [self fail:@"%@ is larger than its frame, %g by %g", path, size.width, size.height];
    }
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

#pragma mark Colors

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
        NSString *path = [NSString stringWithFormat:@"palette.%@", name];
        QLMSkinColor color = QLMSkinColorClear;
        if (![object[name] isKindOfClass:NSString.class] || !QLMSkinParseHex(object[name], &color)) {
            [self fail:@"%@ is %@, which is not #RRGGBB or #RRGGBBAA", path, object[name]];
            return;
        }
        palette[name] = QLMSkinColorValue(color);
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
    shadow.color = [self color:object[@"color"] at:[path stringByAppendingString:@".color"]];
    shadow.blur = [self nonNegative:object[@"blur"] at:[path stringByAppendingString:@".blur"] orDefault:0];
    shadow.offset = object[@"offset"] ? [self size:object[@"offset"] at:[path stringByAppendingString:@".offset"]] : CGSizeZero;
    return shadow;
}

- (QLMSkinFocus *)focus:(id)value at:(NSString *)path {
    QLMSkinFocus *focus = [[QLMSkinFocus alloc] init];
    NSDictionary *object = [self object:value at:path];
    if (![self checkKeys:object at:path allowed:@[@"color", @"width", @"radius", @"outset"] required:@[@"color"]]) {
        return focus;
    }
    focus.color = [self color:object[@"color"] at:[path stringByAppendingString:@".color"]];
    focus.width = [self nonNegative:object[@"width"] at:[path stringByAppendingString:@".width"] orDefault:2];
    focus.radius = [self nonNegative:object[@"radius"] at:[path stringByAppendingString:@".radius"] orDefault:0];
    focus.outset = [self number:object[@"outset"] at:[path stringByAppendingString:@".outset"] orDefault:0];
    return focus;
}

// One draw block, over `base`'s values. A state's block overrides only what
// it names.
- (QLMSkinDraw *)draw:(NSDictionary *)object over:(nullable QLMSkinDraw *)base at:(NSString *)path {
    QLMSkinDraw *draw = base ? [base copy] : [[QLMSkinDraw alloc] init];
    NSString *(^at)(NSString *) = ^NSString *(NSString *key) {
        return [NSString stringWithFormat:@"%@.%@", path, key];
    };
    if (object[@"fill"] && object[@"gradient"]) {
        [self fail:@"%@ has both a fill and a gradient", path];
        return draw;
    }
    if (object[@"fill"]) {
        draw.fill = [self color:object[@"fill"] at:at(@"fill")];
        draw.hasGradient = NO;
    }
    if (object[@"gradient"]) {
        NSArray *stops = object[@"gradient"];
        if (![stops isKindOfClass:NSArray.class] || stops.count != 2) {
            [self fail:@"%@ is not two colors, top then bottom", at(@"gradient")];
            return draw;
        }
        draw.gradientTop = [self color:stops[0] at:at(@"gradient")];
        draw.gradientBottom = [self color:stops[1] at:at(@"gradient")];
        draw.hasGradient = YES;
        draw.fill = QLMSkinColorClear;
    }
    if (object[@"border"]) {
        draw.border = [self color:object[@"border"] at:at(@"border")];
        if (object[@"borderWidth"] == nil && draw.borderWidth == 0) {
            draw.borderWidth = 1;
        }
    }
    if (object[@"borderWidth"]) {
        draw.borderWidth = [self nonNegative:object[@"borderWidth"] at:at(@"borderWidth") orDefault:0];
    }
    if (object[@"radius"]) {
        draw.radius = [self nonNegative:object[@"radius"] at:at(@"radius") orDefault:0];
    }
    if (object[@"inset"]) {
        draw.inset = [self number:object[@"inset"] at:at(@"inset")];
    }
    if (object[@"shadow"]) {
        draw.shadow = [self shadow:object[@"shadow"] at:at(@"shadow")];
    }
    if (object[@"rings"]) {
        NSArray *rings = object[@"rings"];
        if (![rings isKindOfClass:NSArray.class]) {
            [self fail:@"%@ is not a list", at(@"rings")];
            return draw;
        }
        NSMutableArray<QLMSkinRing *> *read = [NSMutableArray array];
        for (NSUInteger i = 0; i < rings.count; i++) {
            NSString *ringPath = [NSString stringWithFormat:@"%@[%lu]", at(@"rings"), (unsigned long)i];
            NSDictionary *ringObject = [self object:rings[i] at:ringPath];
            if (![self checkKeys:ringObject at:ringPath allowed:@[@"inset", @"color", @"width"] required:@[@"color"]]) {
                return draw;
            }
            QLMSkinRing *ring = [[QLMSkinRing alloc] init];
            ring.inset = [self number:ringObject[@"inset"] at:[ringPath stringByAppendingString:@".inset"] orDefault:0];
            ring.color = [self color:ringObject[@"color"] at:[ringPath stringByAppendingString:@".color"]];
            ring.width = [self nonNegative:ringObject[@"width"] at:[ringPath stringByAppendingString:@".width"] orDefault:1];
            [read addObject:ring];
        }
        draw.rings = read;
    }
    return draw;
}

// An element's material: "image", with "capInsets", or "draw", never both.
// `states` are the states it takes: one, four, or eight.
- (nullable QLMSkinStyle *)style:(NSDictionary *)object states:(NSUInteger)states at:(NSString *)path {
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
        style.imageName = [self string:image at:[path stringByAppendingString:@".image"]];
        if (style.imageName && ([style.imageName containsString:@"/"] || [style.imageName hasPrefix:@"."])) {
            [self fail:@"%@.image is %@, which is not a file name in png/", path, style.imageName];
            return nil;
        }
        style.capInsets = [self capInsets:object[@"capInsets"] at:[path stringByAppendingString:@".capInsets"]];
        for (NSUInteger state = 0; state < states && ![self failed]; state++) {
            [self checkImage:[style imageNameForState:(QLMSkinState)state] at:path];
        }
        return [self failed] ? nil : style;
    }
    NSString *drawPath = [path stringByAppendingString:@".draw"];
    NSDictionary *drawObject = [self object:draw at:drawPath];
    NSArray *keys = @[@"fill", @"gradient", @"border", @"borderWidth", @"radius", @"inset", @"rings", @"shadow"];
    if (![self checkKeys:drawObject at:drawPath allowed:[keys arrayByAddingObject:@"states"] required:@[]]) {
        return nil;
    }
    QLMSkinDraw *base = [self draw:drawObject over:nil at:drawPath];
    NSDictionary *overrides = @{};
    if (drawObject[@"states"]) {
        if (states == 1) {
            [self fail:@"%@ has states, but its element takes one", drawPath];
            return nil;
        }
        overrides = [self object:drawObject[@"states"] at:[drawPath stringByAppendingString:@".states"]];
        NSArray<NSString *> *names = [QLMSkinStateNames() subarrayWithRange:NSMakeRange(1, states - 1)];
        if (![self checkKeys:overrides at:[drawPath stringByAppendingString:@".states"] allowed:names required:@[]]) {
            return nil;
        }
    }
    // A selected state takes selected's overrides, then its own.
    NSMutableArray<QLMSkinDraw *> *draws = [NSMutableArray array];
    for (NSUInteger state = 0; state < states; state++) {
        NSString *name = QLMSkinStateNames()[state];
        QLMSkinDraw *resolved = base;
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        if (state > QLMSkinStateSelected) {
            [chain addObject:@"selected"];
        }
        if (state != QLMSkinStateNormal) {
            [chain addObject:name];
        }
        for (NSString *link in chain) {
            if (overrides[link] == nil) {
                continue;
            }
            NSString *linkPath = [NSString stringWithFormat:@"%@.states.%@", drawPath, link];
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
    for (NSString *file in @[[name stringByAppendingString:@".png"], [name stringByAppendingString:@"@2x.png"]]) {
        NSURL *url = [self.directory URLByAppendingPathComponent:[@"png" stringByAppendingPathComponent:file]];
        if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            [self fail:@"%@ names the image %@, but the skin has no png/%@", path, name, file];
            return;
        }
    }
}

- (QLMSkinTextSlot *)slot:(id)value named:(NSString *)name at:(NSString *)path {
    QLMSkinTextSlot *slot = [[QLMSkinTextSlot alloc] init];
    slot.name = name;
    NSDictionary *object = [self object:value at:path];
    NSArray *allowed = @[@"frame", @"anchors", @"scales", @"font", @"mono", @"size", @"weight", @"italic",
                         @"alignment", @"color", @"tracking", @"accent"];
    if (![self checkKeys:object at:path allowed:allowed required:@[@"frame", @"size", @"color"]]) {
        return slot;
    }
    NSString *(^at)(NSString *) = ^NSString *(NSString *key) {
        return [NSString stringWithFormat:@"%@.%@", path, key];
    };
    slot.frame = [self frame:object[@"frame"] at:at(@"frame")];
    slot.anchors = [self anchors:object[@"anchors"] at:at(@"anchors")];
    slot.scales = [self boolean:object[@"scales"] at:at(@"scales")];
    slot.fontName = object[@"font"] ? [self string:object[@"font"] at:at(@"font")] : nil;
    slot.mono = [self boolean:object[@"mono"] at:at(@"mono")];
    slot.size = [self positive:object[@"size"] at:at(@"size")];
    slot.weight = [self weight:object[@"weight"] at:at(@"weight")];
    slot.italic = [self boolean:object[@"italic"] at:at(@"italic")];
    slot.alignment = [self choice:object[@"alignment"] among:@[@"left", @"center", @"right"]
                               at:at(@"alignment") orDefault:QLMSkinAlignmentLeft];
    slot.color = [self color:object[@"color"] at:at(@"color")];
    slot.tracking = [self number:object[@"tracking"] at:at(@"tracking") orDefault:0];
    slot.accentColor = [self color:object[@"accent"] at:at(@"accent") orDefault:QLMSkinColorClear];
    return slot;
}

- (QLMSkinWeight)weight:(id)value at:(NSString *)path {
    NSArray *names = @[@"ultralight", @"thin", @"light", @"regular", @"medium", @"semibold", @"bold", @"heavy", @"black"];
    return [self choice:value among:names at:path orDefault:QLMSkinWeightRegular];
}

#pragma mark Elements

// The keys every element may have, beside its kind's own.
static NSArray<NSString *> *QLMSkinElementKeys(NSArray<NSString *> *own) {
    return [@[@"frame", @"anchors", @"text"] arrayByAddingObjectsFromArray:own];
}

- (QLMSkinElement *)element:(NSString *)name
                       from:(NSDictionary *)elements
                       keys:(NSArray<NSString *> *)own
                   required:(NSArray<NSString *> *)requiredKeys
                      slots:(NSArray<NSString *> *)slots
              optionalSlots:(NSArray<NSString *> *)optionalSlots {
    QLMSkinElement *element = [[QLMSkinElement alloc] init];
    element.name = name;
    if ([self failed]) {
        return element;
    }
    NSString *path = [@"elements." stringByAppendingString:name];
    if (elements[name] == nil) {
        [self fail:@"elements has no %@", name];
        return element;
    }
    NSDictionary *object = [self object:elements[name] at:path];
    NSArray *required = [@[@"frame"] arrayByAddingObjectsFromArray:requiredKeys];
    if (slots.count > 0) {
        required = [required arrayByAddingObject:@"text"];
    }
    if (![self checkKeys:object at:path allowed:QLMSkinElementKeys(own) required:required]) {
        return element;
    }
    element.frame = [self frame:object[@"frame"] at:[path stringByAppendingString:@".frame"]];
    element.anchors = [self anchors:object[@"anchors"] at:[path stringByAppendingString:@".anchors"]];
    element.text = [self slots:object[@"text"] at:[path stringByAppendingString:@".text"]
                      required:slots optional:optionalSlots];
    return element;
}

- (NSDictionary<NSString *, QLMSkinTextSlot *> *)slots:(id)value at:(NSString *)path
                                              required:(NSArray<NSString *> *)required
                                              optional:(NSArray<NSString *> *)optional {
    if (value == nil && required.count == 0) {
        return @{};
    }
    NSDictionary *object = [self object:value at:path];
    if (![self checkKeys:object at:path allowed:[required arrayByAddingObjectsFromArray:optional] required:required]) {
        return @{};
    }
    NSMutableDictionary<NSString *, QLMSkinTextSlot *> *slots = [NSMutableDictionary dictionary];
    for (NSString *name in [object.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        slots[name] = [self slot:object[name] named:name at:[NSString stringWithFormat:@"%@.%@", path, name]];
    }
    return slots;
}

// A grid's cell, at the skin's size.
static CGSize QLMSkinCellSize(QLMSkinElement *grid) {
    return CGSizeMake((grid.frame.size.width - grid.gap.width * (grid.columns - 1)) / grid.columns,
                      (grid.frame.size.height - grid.gap.height * (grid.rows - 1)) / grid.rows);
}

- (void)readGrid:(QLMSkinElement *)element from:(NSDictionary *)object cells:(NSInteger)least {
    NSString *path = [@"elements." stringByAppendingString:element.name];
    element.columns = [self integer:object[@"columns"] at:[path stringByAppendingString:@".columns"]];
    element.rows = [self integer:object[@"rows"] at:[path stringByAppendingString:@".rows"]];
    if (object[@"gap"]) {
        element.gap = [self size:object[@"gap"] at:[path stringByAppendingString:@".gap"]];
    }
    if (![self failed] && element.columns * element.rows < least) {
        [self fail:@"%@ has %ld cells, fewer than its %ld buttons", path, (long)(element.columns * element.rows), (long)least];
    }
    if (![self failed] && (element.gap.width < 0 || element.gap.height < 0)) {
        [self fail:@"%@.gap is below 0", path];
    }
    CGSize cell = QLMSkinCellSize(element);
    if (![self failed] && (cell.width <= 0 || cell.height <= 0)) {
        [self fail:@"%@'s gap leaves its cells no room", path];
    }
}

// The button's face fits the smaller grid's cells: its cap insets and its
// LED.
- (void)checkButton:(QLMSkinButton *)button inGrids:(NSArray<QLMSkinElement *> *)grids {
    CGSize least = CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX);
    for (QLMSkinElement *grid in grids) {
        CGSize cell = QLMSkinCellSize(grid);
        least = CGSizeMake(MIN(least.width, cell.width), MIN(least.height, cell.height));
    }
    if (button.style.imageName != nil) {
        [self checkInsets:button.style.capInsets fit:least at:@"button.capInsets"];
    }
    if ([self failed] || button.ledSize <= 0) {
        return;
    }
    if (button.ledSize > least.height) {
        [self fail:@"button.led.size is taller than the button, %g", least.height];
    }
    else if (button.ledX >= 0 && button.ledX + button.ledSize > least.width) {
        [self fail:@"button.led.x puts the LED past the button's width, %g", least.width];
    }
    else if (button.ledX < 0 && button.ledSize + button.ledGap > least.width) {
        [self fail:@"button.led leaves the title no room in the button's width, %g", least.width];
    }
}

// Every drawn radius of the knob fits in half its frame, with the round
// caps' and the strokes' half-widths.
- (void)checkKnob:(QLMSkinKnob *)knob inFrame:(CGRect)frame {
    if ([self failed]) {
        return;
    }
    CGFloat half = MIN(frame.size.width, frame.size.height) / 2;
    NSMutableArray<NSArray *> *radii = [NSMutableArray arrayWithArray:@[
        @[@"elements.knob.body.size", @(knob.bodySize / 2)],
        @[@"elements.knob.pointer.outer", @(knob.pointerOuter + knob.pointerWidth / 2)],
        @[@"elements.knob.focus", @(knob.bodySize / 2 + knob.focus.outset + knob.focus.width)],
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

- (QLMSkinButton *)button:(id)value {
    QLMSkinButton *button = [[QLMSkinButton alloc] init];
    NSDictionary *object = [self object:value at:@"button"];
    if (![self checkKeys:object at:@"button" allowed:@[@"image", @"draw", @"capInsets", @"title", @"focus", @"led"]
                required:@[@"title", @"focus"]]) {
        return button;
    }
    button.style = [self style:object states:8 at:@"button"];
    button.focus = [self focus:object[@"focus"] at:@"button.focus"];

    NSDictionary *title = [self object:object[@"title"] at:@"button.title"];
    NSArray *titleKeys = @[@"font", @"size", @"weight", @"tracking", @"color", @"selectedColor", @"disabledColor", @"prefixColor"];
    if ([self checkKeys:title at:@"button.title" allowed:titleKeys required:@[@"size", @"color"]]) {
        QLMSkinTitle *read = [[QLMSkinTitle alloc] init];
        read.fontName = title[@"font"] ? [self string:title[@"font"] at:@"button.title.font"] : nil;
        read.size = [self positive:title[@"size"] at:@"button.title.size"];
        read.weight = [self weight:title[@"weight"] at:@"button.title.weight"];
        read.tracking = [self number:title[@"tracking"] at:@"button.title.tracking" orDefault:0];
        read.color = [self color:title[@"color"] at:@"button.title.color"];
        read.selectedColor = [self color:title[@"selectedColor"] at:@"button.title.selectedColor" orDefault:read.color];
        read.disabledColor = [self color:title[@"disabledColor"] at:@"button.title.disabledColor" orDefault:read.color];
        read.prefixColor = [self color:title[@"prefixColor"] at:@"button.title.prefixColor" orDefault:read.color];
        button.title = read;
    }

    button.ledX = -1;
    if (object[@"led"]) {
        NSDictionary *led = [self object:object[@"led"] at:@"button.led"];
        if ([self checkKeys:led at:@"button.led" allowed:@[@"size", @"gap", @"x"] required:@[@"size"]]) {
            button.ledSize = [self positive:led[@"size"] at:@"button.led.size"];
            button.ledGap = [self nonNegative:led[@"gap"] at:@"button.led.gap" orDefault:6];
            if (led[@"x"]) {
                button.ledX = [self nonNegative:led[@"x"] at:@"button.led.x" orDefault:0];
            }
        }
    }
    return button;
}

- (QLMSkinKnob *)knob:(NSDictionary *)object {
    QLMSkinKnob *knob = [[QLMSkinKnob alloc] init];
    NSString *path = @"elements.knob";

    NSDictionary *body = [self object:object[@"body"] at:[path stringByAppendingString:@".body"]];
    if ([self checkKeys:body at:@"elements.knob.body" allowed:@[@"size", @"image", @"draw", @"capInsets"] required:@[@"size"]]) {
        knob.bodySize = [self positive:body[@"size"] at:@"elements.knob.body.size"];
        knob.body = [self style:body states:4 at:@"elements.knob.body"];
    }

    if (object[@"ticks"]) {
        NSDictionary *ticks = [self object:object[@"ticks"] at:@"elements.knob.ticks"];
        if ([self checkKeys:ticks at:@"elements.knob.ticks" allowed:@[@"count", @"inner", @"outer", @"width", @"color"]
                   required:@[@"count", @"inner", @"outer", @"color"]]) {
            knob.tickCount = [self integer:ticks[@"count"] at:@"elements.knob.ticks.count"];
            knob.tickInner = [self positive:ticks[@"inner"] at:@"elements.knob.ticks.inner"];
            knob.tickOuter = [self positive:ticks[@"outer"] at:@"elements.knob.ticks.outer"];
            knob.tickWidth = [self nonNegative:ticks[@"width"] at:@"elements.knob.ticks.width" orDefault:1];
            knob.tickColor = [self color:ticks[@"color"] at:@"elements.knob.ticks.color"];
        }
    }

    NSDictionary *pointer = [self object:object[@"pointer"] at:@"elements.knob.pointer"];
    if ([self checkKeys:pointer at:@"elements.knob.pointer" allowed:@[@"inner", @"outer", @"width", @"color", @"disabledColor"]
               required:@[@"inner", @"outer", @"color"]]) {
        knob.pointerInner = [self nonNegative:pointer[@"inner"] at:@"elements.knob.pointer.inner" orDefault:0];
        knob.pointerOuter = [self positive:pointer[@"outer"] at:@"elements.knob.pointer.outer"];
        knob.pointerWidth = [self nonNegative:pointer[@"width"] at:@"elements.knob.pointer.width" orDefault:2];
        knob.pointerColor = [self color:pointer[@"color"] at:@"elements.knob.pointer.color"];
        knob.pointerDisabledColor = [self color:pointer[@"disabledColor"] at:@"elements.knob.pointer.disabledColor"
                                      orDefault:knob.pointerColor];
    }

    knob.shadow = [self shadow:object[@"shadow"] at:@"elements.knob.shadow"];
    knob.focus = [self focus:object[@"focus"] at:@"elements.knob.focus"];

    if (object[@"arc"]) {
        NSDictionary *arc = [self object:object[@"arc"] at:@"elements.knob.arc"];
        if ([self checkKeys:arc at:@"elements.knob.arc" allowed:@[@"radius", @"width", @"track", @"fill"]
                   required:@[@"radius", @"track", @"fill"]]) {
            knob.hasArc = YES;
            knob.arcRadius = [self positive:arc[@"radius"] at:@"elements.knob.arc.radius"];
            knob.arcWidth = [self nonNegative:arc[@"width"] at:@"elements.knob.arc.width" orDefault:3];
            knob.arcTrack = [self color:arc[@"track"] at:@"elements.knob.arc.track"];
            knob.arcFill = [self color:arc[@"fill"] at:@"elements.knob.arc.fill"];
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

- (QLMSkinMarkings *)markings:(id)value elements:(NSDictionary<NSString *, QLMSkinElement *> *)elements {
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
        QLMSkinElement *element = placed(line[@"element"], [path stringByAppendingString:@".element"]);
        read.element = element.name ?: @"";
        read.y = [self number:line[@"y"] at:[path stringByAppendingString:@".y"]];
        if (element) {
            [self checkFrame:CGRectMake(element.frame.origin.x, element.frame.origin.y + read.y, element.frame.size.width, 0)
                      inside:self.windowSize at:path];
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
        QLMSkinElement *element = placed(box[@"element"], [path stringByAppendingString:@".element"]);
        read.element = element.name ?: @"";
        read.outset = [self insets:box[@"outset"] at:[path stringByAppendingString:@".outset"]];
        read.radius = [self nonNegative:box[@"radius"] at:[path stringByAppendingString:@".radius"] orDefault:0];
        if (box[@"gap"]) {
            read.gap = [self string:box[@"gap"] at:[path stringByAppendingString:@".gap"]];
            if (element && read.gap && element.text[read.gap] == nil) {
                [self fail:@"%@.gap names %@, which is not a slot of %@", path, read.gap, element.name];
            }
        }
        if (element) {
            NSEdgeInsets o = read.outset;
            CGRect outer = CGRectMake(element.frame.origin.x - o.left, element.frame.origin.y - o.top,
                                      element.frame.size.width + o.left + o.right,
                                      element.frame.size.height + o.top + o.bottom);
            [self checkFrame:outer inside:self.windowSize at:path];
        }
        [boxes addObject:read];
    }
    markings.boxes = boxes;
    return markings;
}

- (void)checkFrame:(CGRect)frame inside:(CGSize)size named:(NSString *)surface at:(NSString *)path {
    if ([self failed]) {
        return;
    }
    const CGFloat slack = 0.001;
    if (CGRectGetMinX(frame) < -slack || CGRectGetMinY(frame) < -slack
        || CGRectGetMaxX(frame) > size.width + slack || CGRectGetMaxY(frame) > size.height + slack) {
        [self fail:@"%@ is outside the %@, %g by %g", path, surface, size.width, size.height];
    }
}

- (void)checkFrame:(CGRect)frame inside:(CGSize)size at:(NSString *)path {
    [self checkFrame:frame inside:size named:@"window" at:path];
}

// Each element's frame, and each of its slots' frames, in its surface.
- (void)checkElement:(QLMSkinElement *)element inside:(CGSize)size at:(NSString *)path {
    [self checkFrame:element.frame inside:size at:[path stringByAppendingString:@".frame"]];
    for (NSString *name in [element.text.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        CGRect frame = CGRectOffset(element.text[name].frame, element.frame.origin.x, element.frame.origin.y);
        NSString *slotPath = [NSString stringWithFormat:@"%@.text.%@", path, name];
        [self checkFrame:frame inside:size at:slotPath];
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
    if (![format isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)format) == CFBooleanGetTypeID()
        || [format doubleValue] != QLMSkinFormat) {
        [self fail:@"skin.json's format is %@, and qlm reads format %d", format, QLMSkinFormat];
        return nil;
    }

    QLMSkin *skin = [[QLMSkin alloc] initPrivately];
    skin.directory = self.directory;
    skin.name = self.directory.lastPathComponent;
    skin.windowSize = [self size:root[@"size"] at:@"size"];
    self.windowSize = skin.windowSize;
    if (![self failed] && (skin.windowSize.width < QLMSkinReferenceWindowSize.width
                           || skin.windowSize.height < QLMSkinReferenceWindowSize.height)) {
        [self fail:@"size is %g by %g, below the reference, %g by %g", skin.windowSize.width, skin.windowSize.height,
                   QLMSkinReferenceWindowSize.width, QLMSkinReferenceWindowSize.height];
    }
    [self readPalette:root[@"palette"]];
    skin.palette = self.palette ?: @{};

    NSDictionary *elements = [self object:root[@"elements"] at:@"elements"];
    NSArray<NSString *> *names = @[@"panel", @"nameplate", @"status", @"groups", @"display", @"toggles", @"knob", @"footer"];
    if (![self checkKeys:elements at:@"elements" allowed:names required:names]) {
        return nil;
    }
    NSArray *styled = @[@"image", @"draw", @"capInsets"];
    NSMutableDictionary<NSString *, QLMSkinElement *> *read = [NSMutableDictionary dictionary];

    QLMSkinElement *panel = [self element:@"panel" from:elements keys:styled required:@[] slots:@[] optionalSlots:@[]];
    panel.style = [self style:elements[@"panel"] states:1 at:@"elements.panel"];
    read[@"panel"] = panel;

    QLMSkinElement *nameplate = [self element:@"nameplate" from:elements keys:styled required:@[] slots:@[]
                                optionalSlots:@[@"logo", @"tagline"]];
    nameplate.style = [self style:elements[@"nameplate"] states:1 at:@"elements.nameplate"];
    read[@"nameplate"] = nameplate;

    QLMSkinElement *status = [self element:@"status" from:elements keys:@[@"led"] required:@[@"led"]
                                     slots:@[@"online"] optionalSlots:@[]];
    if (![self failed]) {
        status.ledFrame = [self frame:elements[@"status"][@"led"] at:@"elements.status.led"];
        [self checkFrame:CGRectOffset(status.ledFrame, status.frame.origin.x, status.frame.origin.y)
                  inside:skin.windowSize at:@"elements.status.led"];
    }
    read[@"status"] = status;

    QLMSkinElement *groups = [self element:@"groups" from:elements keys:@[@"columns", @"rows", @"gap"]
                                  required:@[@"columns", @"rows"] slots:@[@"groupsTitle", @"message"]
                             optionalSlots:@[]];
    if (![self failed]) {
        [self readGrid:groups from:elements[@"groups"] cells:1];
    }
    read[@"groups"] = groups;

    QLMSkinElement *display = [self element:@"display" from:elements
                                       keys:[styled arrayByAddingObject:@"disabledOverlay"] required:@[]
                                      slots:@[@"caption", @"level", @"unit", @"output", @"max"] optionalSlots:@[]];
    display.style = [self style:elements[@"display"] states:1 at:@"elements.display"];
    if (![self failed]) {
        display.disabledOverlay = [self color:elements[@"display"][@"disabledOverlay"]
                                           at:@"elements.display.disabledOverlay" orDefault:QLMSkinColorClear];
    }
    read[@"display"] = display;

    QLMSkinElement *toggles = [self element:@"toggles" from:elements keys:@[@"columns", @"rows", @"gap"]
                                   required:@[@"columns", @"rows"] slots:@[] optionalSlots:@[]];
    if (![self failed]) {
        [self readGrid:toggles from:elements[@"toggles"] cells:2];
    }
    read[@"toggles"] = toggles;

    QLMSkinElement *knob = [self element:@"knob" from:elements
                                    keys:@[@"body", @"ticks", @"pointer", @"shadow", @"focus", @"arc"]
                                required:@[@"body", @"pointer", @"focus"] slots:@[@"min", @"max", @"caption"]
                           optionalSlots:@[]];
    if (![self failed]) {
        skin.knob = [self knob:elements[@"knob"]];
        [self checkKnob:skin.knob inFrame:knob.frame];
        if (skin.knob.body.imageName != nil) {
            [self checkInsets:skin.knob.body.capInsets fit:CGSizeMake(skin.knob.bodySize, skin.knob.bodySize)
                           at:@"elements.knob.body.capInsets"];
        }
    }
    read[@"knob"] = knob;

    QLMSkinElement *footer = [self element:@"footer" from:elements keys:@[@"symbols"] required:@[@"symbols"]
                                     slots:@[@"monitors", @"power"] optionalSlots:@[]];
    if (![self failed]) {
        NSDictionary *symbols = [self object:elements[@"footer"][@"symbols"] at:@"elements.footer.symbols"];
        if ([self checkKeys:symbols at:@"elements.footer.symbols" allowed:@[@"monitors", @"power"]
                   required:@[@"monitors", @"power"]]) {
            for (NSString *slot in symbols) {
                [self string:symbols[slot] at:[@"elements.footer.symbols." stringByAppendingString:slot]];
            }
            footer.symbols = symbols;
        }
    }
    read[@"footer"] = footer;

    for (NSString *name in names) {
        QLMSkinElement *element = read[name];
        NSString *path = [@"elements." stringByAppendingString:name];
        [self checkElement:element inside:skin.windowSize at:path];
        if (element.style.imageName != nil) {
            [self checkInsets:element.style.capInsets fit:element.frame.size at:[path stringByAppendingString:@".capInsets"]];
        }
    }
    skin.elements = read;

    if (![self failed]) {
        skin.button = [self button:root[@"button"]];
        [self checkButton:skin.button inGrids:@[groups, toggles]];
    }
    if (![self failed]) {
        skin.led = [self led:root[@"led"]];
    }
    if (![self failed]) {
        skin.markings = [self markings:root[@"markings"] elements:read];
    }
    if (![self failed]) {
        skin.osd = [self osd:root[@"osd"] skin:skin];
    }
    return [self failed] ? nil : skin;
}

- (QLMSkinElement *)osd:(id)value skin:(QLMSkin *)skin {
    QLMSkinElement *osd = [[QLMSkinElement alloc] init];
    osd.name = @"osd";
    NSDictionary *object = [self object:value at:@"osd"];
    if (![self checkKeys:object at:@"osd"
                 allowed:@[@"size", @"image", @"draw", @"capInsets", @"disabledOverlay", @"bar", @"text"]
                required:@[@"size", @"bar", @"text"]]) {
        return osd;
    }
    skin.osdSize = [self size:object[@"size"] at:@"osd.size"];
    if (![self failed] && (skin.osdSize.width < QLMSkinReferenceOSDSize.width
                           || skin.osdSize.height < QLMSkinReferenceOSDSize.height)) {
        [self fail:@"osd.size is %g by %g, below the reference, %g by %g", skin.osdSize.width, skin.osdSize.height,
                   QLMSkinReferenceOSDSize.width, QLMSkinReferenceOSDSize.height];
        return osd;
    }
    osd.frame = CGRectMake(0, 0, skin.osdSize.width, skin.osdSize.height);
    osd.anchors = QLMSkinAnchorLeft | QLMSkinAnchorTop;
    osd.style = [self style:object states:1 at:@"osd"];
    if (osd.style.imageName != nil) {
        [self checkInsets:osd.style.capInsets fit:skin.osdSize at:@"osd.capInsets"];
    }
    osd.disabledOverlay = [self color:object[@"disabledOverlay"] at:@"osd.disabledOverlay" orDefault:QLMSkinColorClear];
    osd.text = [self slots:object[@"text"] at:@"osd.text" required:@[@"level", @"unit", @"title", @"subtitle"] optional:@[]];

    NSDictionary *bar = [self object:object[@"bar"] at:@"osd.bar"];
    if ([self checkKeys:bar at:@"osd.bar" allowed:@[@"frame", @"track", @"fill", @"radius"]
               required:@[@"frame", @"track", @"fill"]]) {
        QLMSkinBar *read = [[QLMSkinBar alloc] init];
        read.frame = [self frame:bar[@"frame"] at:@"osd.bar.frame"];
        read.track = [self color:bar[@"track"] at:@"osd.bar.track"];
        read.fill = [self color:bar[@"fill"] at:@"osd.bar.fill"];
        read.radius = [self nonNegative:bar[@"radius"] at:@"osd.bar.radius" orDefault:0];
        [self checkFrame:read.frame inside:skin.osdSize named:@"OSD" at:@"osd.bar.frame"];
        osd.bar = read;
    }
    for (NSString *name in [osd.text.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [self checkFrame:osd.text[name].frame inside:skin.osdSize named:@"OSD"
                      at:[@"osd.text." stringByAppendingString:name]];
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
                                     code:reader.unreadable ?QLMSkinErrorUnreadable : QLMSkinErrorInvalid
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
    NSString *file = scale >= 2 ? [name stringByAppendingString:@"@2x.png"] : [name stringByAppendingString:@".png"];
    return [self.directory URLByAppendingPathComponent:[@"png" stringByAppendingPathComponent:file]];
}

@end
