#import "QLMSkinDrawing.h"

#import <CoreText/CoreText.h>
#import <objc/runtime.h>

const CGFloat QLMSkinDisabledAlpha = 0.4;

NSColor *QLMSkinNSColor(QLMSkinColor color) {
    return [NSColor colorWithSRGBRed:color.red green:color.green blue:color.blue alpha:color.alpha];
}

static BOOL QLMSkinColorIsClear(QLMSkinColor color) {
    return color.alpha <= 0;
}

static NSImageRep *_Nullable QLMSkinImageRep(NSURL *url, CGFloat scale) {
    NSImageRep *rep = [NSBitmapImageRep imageRepWithContentsOfURL:url];
    if (rep == nil || rep.pixelsWide <= 0) {
        return nil;
    }
    rep.size = NSMakeSize(rep.pixelsWide / scale, rep.pixelsHigh / scale);
    return rep;
}

// A value kept on an object, made the first time it's asked for. Keys are
// by address. On the main queue, as all drawing is.
static id QLMSkinAttached(id owner, const void *key, id (^make)(void)) {
    id value = objc_getAssociatedObject(owner, key);
    if (value == nil) {
        value = make();
        objc_setAssociatedObject(owner, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return value;
}

static char QLMSkinImagesKey;
static char QLMSkinGradientKey;

// png/<name>.png with its @2x beside it, sized in points and stretched
// through `insets`, or nil when either file won't load. Kept on the skin,
// so a skin read again reads its files again.
static NSImage *_Nullable QLMSkinStretchedImage(QLMSkin *skin, NSString *name, NSEdgeInsets insets) {
    NSMutableDictionary<NSString *, id> *cache = QLMSkinAttached(skin, &QLMSkinImagesKey, ^id {
        return [NSMutableDictionary dictionary];
    });
    NSString *key = [NSString stringWithFormat:@"%@|%g,%g,%g,%g", name, insets.top, insets.left, insets.bottom, insets.right];
    id cached = cache[key];
    if (cached != nil) {
        return cached == NSNull.null ? nil : cached;
    }
    NSImageRep *one = QLMSkinImageRep([skin imageURLForName:name scale:1], 1);
    NSImageRep *two = QLMSkinImageRep([skin imageURLForName:name scale:2], 2);
    NSImage *image = nil;
    if (one != nil && two != nil) {
        image = [[NSImage alloc] initWithSize:one.size];
        [image addRepresentation:one];
        [image addRepresentation:two];
        image.capInsets = insets;
        image.resizingMode = NSImageResizingModeStretch;
    }
    cache[key] = image ?: NSNull.null;
    return image;
}

static NSBezierPath *QLMSkinShape(NSRect rect, CGFloat radius, BOOL circle) {
    if (circle) {
        CGFloat side = MIN(rect.size.width, rect.size.height);
        return [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(rect) - side / 2, NSMidY(rect) - side / 2, side, side)];
    }
    radius = MIN(radius, MIN(rect.size.width, rect.size.height) / 2);
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
}

// TRAP: a shadow's offset is in the base space, whose y grows up, so a
// flipped view's y-down offset changes sign.
static void QLMSkinSetShadow(QLMSkinColor color, CGFloat blur, CGSize offset) {
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = QLMSkinNSColor(color);
    shadow.shadowBlurRadius = blur;
    shadow.shadowOffset = NSMakeSize(offset.width, -offset.height);
    [shadow set];
}

void QLMSkinDrawShadow(QLMSkinShadow *shadow, NSBezierPath *path, NSColor *fill) {
    [NSGraphicsContext saveGraphicsState];
    QLMSkinSetShadow(shadow.color, shadow.blur, shadow.offset);
    [fill setFill];
    [path fill];
    [NSGraphicsContext restoreGraphicsState];
}

static void QLMSkinDrawBlock(QLMSkinDraw *draw, NSRect rect, BOOL circle) {
    rect = NSInsetRect(rect, draw.inset, draw.inset);
    if (rect.size.width <= 0 || rect.size.height <= 0) {
        return;
    }
    NSBezierPath *shape = QLMSkinShape(rect, draw.radius, circle);
    if (draw.shadow != nil) {
        QLMSkinDrawShadow(draw.shadow, shape, QLMSkinNSColor(draw.hasGradient ? draw.gradientBottom : draw.fill));
    }
    if (draw.hasGradient) {
        NSGradient *gradient = QLMSkinAttached(draw, &QLMSkinGradientKey, ^id {
            return [[NSGradient alloc] initWithStartingColor:QLMSkinNSColor(draw.gradientTop)
                                                 endingColor:QLMSkinNSColor(draw.gradientBottom)];
        });
        [gradient drawInBezierPath:shape angle:90];
    }
    else if (!QLMSkinColorIsClear(draw.fill)) {
        [QLMSkinNSColor(draw.fill) setFill];
        [shape fill];
    }
    for (QLMSkinRing *ring in draw.rings) {
        NSRect ringRect = NSInsetRect(rect, ring.inset + ring.width / 2, ring.inset + ring.width / 2);
        NSBezierPath *path = QLMSkinShape(ringRect, MAX(0, draw.radius - ring.inset), circle);
        path.lineWidth = ring.width;
        [QLMSkinNSColor(ring.color) setStroke];
        [path stroke];
    }
    if (draw.borderWidth > 0 && !QLMSkinColorIsClear(draw.border)) {
        CGFloat half = draw.borderWidth / 2;
        NSBezierPath *border = QLMSkinShape(NSInsetRect(rect, half, half), MAX(0, draw.radius - half), circle);
        border.lineWidth = draw.borderWidth;
        [QLMSkinNSColor(draw.border) setStroke];
        [border stroke];
    }
}

void QLMSkinDrawStyle(QLMSkin *skin, QLMSkinStyle *style, QLMSkinState state, NSRect rect, BOOL circle) {
    QLMSkinDraw *draw = [style drawForState:state];
    if (draw != nil) {
        QLMSkinDrawBlock(draw, rect, circle);
        return;
    }
    QLMSkinDrawImage(QLMSkinStretchedImage(skin, [style imageNameForState:state], style.capInsets), rect);
}

// TRAP: an image with cap insets ignores respectFlipped whenever it draws at
// any size but its own, so in a flipped view it stretches upside down. So
// it draws through a CTM flipped about the rect, unflipped by AppKit.
void QLMSkinDrawImage(NSImage *image, NSRect rect) {
    if (image == nil || rect.size.width <= 0 || rect.size.height <= 0) {
        return;
    }
    NSEdgeInsets insets = image.capInsets;
    BOOL sliced = insets.top > 0 || insets.left > 0 || insets.bottom > 0 || insets.right > 0;
    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    if (!context.flipped || !sliced) {
        [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
           respectFlipped:YES hints:nil];
        return;
    }
    CGContextRef cg = context.CGContext;
    CGContextSaveGState(cg);
    // Maps the rect onto itself, upside down.
    CGContextTranslateCTM(cg, 0, NSMinY(rect) + NSMaxY(rect));
    CGContextScaleCTM(cg, 1, -1);
    [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
       respectFlipped:NO hints:nil];
    CGContextRestoreGState(cg);
}


void QLMSkinDrawDimmed(BOOL dimmed, QLMSkinColor overlay, NSRect bounds, void (^content)(void)) {
    if (!dimmed || QLMSkinColorIsClear(overlay)) {
        content();
        return;
    }
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextBeginTransparencyLayer(context, NULL);
    content();
    [QLMSkinNSColor(overlay) setFill];
    NSRectFillUsingOperation(bounds, NSCompositingOperationSourceAtop);
    CGContextEndTransparencyLayer(context);
}

void QLMSkinDrawLED(QLMSkinLED *led, NSRect rect, BOOL lit, BOOL enabled) {
    NSBezierPath *dot = QLMSkinShape(rect, 0, YES);
    [NSGraphicsContext saveGraphicsState];
    if (!enabled) {
        QLMSkinColor off = led.off;
        off.alpha *= QLMSkinDisabledAlpha;
        [QLMSkinNSColor(off) setFill];
    }
    else if (lit) {
        if (led.glow > 0) {
            QLMSkinSetShadow(led.on, led.glow, CGSizeZero);
        }
        [QLMSkinNSColor(led.on) setFill];
    }
    else {
        [QLMSkinNSColor(led.off) setFill];
    }
    [dot fill];
    [NSGraphicsContext restoreGraphicsState];
}

void QLMSkinDrawFocus(QLMSkinFocus *focus, NSRect rect, BOOL circle) {
    CGFloat outset = focus.outset + focus.width / 2;
    NSBezierPath *ring = QLMSkinShape(NSInsetRect(rect, -outset, -outset), focus.radius + outset, circle);
    ring.lineWidth = focus.width;
    [QLMSkinNSColor(focus.color) setStroke];
    [ring stroke];
}

static NSFontWeight QLMSkinFontWeight(QLMSkinWeight weight) {
    switch (weight) {
        case QLMSkinWeightUltraLight: return NSFontWeightUltraLight;
        case QLMSkinWeightThin: return NSFontWeightThin;
        case QLMSkinWeightLight: return NSFontWeightLight;
        case QLMSkinWeightRegular: return NSFontWeightRegular;
        case QLMSkinWeightMedium: return NSFontWeightMedium;
        case QLMSkinWeightSemibold: return NSFontWeightSemibold;
        case QLMSkinWeightBold: return NSFontWeightBold;
        case QLMSkinWeightHeavy: return NSFontWeightHeavy;
        case QLMSkinWeightBlack: return NSFontWeightBlack;
    }
    return NSFontWeightRegular;
}

static NSFont *_Nullable QLMSkinNamedFont(NSString *name, CGFloat size, QLMSkinWeight weight) {
    NSFont *exact = [NSFont fontWithName:name size:size];
    if (exact != nil && weight == QLMSkinWeightRegular) {
        return exact;
    }
    NSFontDescriptor *descriptor = [NSFontDescriptor fontDescriptorWithFontAttributes:@{
        NSFontFamilyAttribute: name,
        NSFontTraitsAttribute: @{NSFontWeightTrait: @(QLMSkinFontWeight(weight))},
    }];
    NSFont *font = [NSFont fontWithDescriptor:descriptor size:size];
    if (font != nil && [font.familyName isEqualToString:name]) {
        return font;
    }
    return exact;
}

static NSFont *QLMSkinMakeFont(NSString *_Nullable name, BOOL mono, CGFloat size, QLMSkinWeight weight, BOOL italic,
                               BOOL monoDigits) {
    NSFont *font = name ? QLMSkinNamedFont(name, size, weight) : nil;
    if (font == nil) {
        NSFontWeight systemWeight = QLMSkinFontWeight(weight);
        font = mono ? [NSFont monospacedSystemFontOfSize:size weight:systemWeight]
                    : [NSFont systemFontOfSize:size weight:systemWeight];
    }
    if (italic) {
        font = [NSFontManager.sharedFontManager convertFont:font toHaveTrait:NSItalicFontMask];
    }
    if (monoDigits && !mono) {
        NSFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
            NSFontFeatureSettingsAttribute: @[@{
                NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
                NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector),
            }],
        }];
        font = [NSFont fontWithDescriptor:descriptor size:size] ?: font;
    }
    return font;
}

// Each face, once: building one through descriptors costs more than a draw.
// A scaled slot's size follows a live resize, so it goes to the half point
// first, or each frame would make two new fonts.
NSFont *QLMSkinFont(NSString *name, BOOL mono, CGFloat size, QLMSkinWeight weight, BOOL italic, BOOL monoDigits) {
    static NSCache<NSString *, NSFont *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
    });
    size = round(size * 2) / 2;
    NSString *key = [NSString stringWithFormat:@"%@|%d|%g|%ld|%d|%d", name ?: @"", mono, size, (long)weight, italic, monoDigits];
    NSFont *font = [cache objectForKey:key];
    if (font == nil) {
        font = QLMSkinMakeFont(name, mono, size, weight, italic, monoDigits);
        [cache setObject:font forKey:key];
    }
    return font;
}

NSFont *QLMSkinSlotFont(QLMSkinTextSlot *slot, CGFloat scale, BOOL monoDigits) {
    return QLMSkinFont(slot.fontName, slot.mono, slot.size * scale, slot.weight, slot.italic, monoDigits);
}

NSDictionary<NSAttributedStringKey, id> *QLMSkinTextAttributes(NSFont *font, NSColor *color, QLMSkinAlignment alignment,
                                                               CGFloat tracking) {
    static NSArray<NSParagraphStyle *> *paragraphs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSParagraphStyle *> *made = [NSMutableArray array];
        for (NSNumber *textAlignment in @[@(NSTextAlignmentLeft), @(NSTextAlignmentCenter), @(NSTextAlignmentRight)]) {
            NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
            paragraph.alignment = (NSTextAlignment)textAlignment.integerValue;
            paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
            [made addObject:[paragraph copy]];
        }
        paragraphs = made;
    });
    return @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraphs[(NSUInteger)alignment],
        NSKernAttributeName: @(tracking),
    };
}

static void QLMSkinDrawAttributed(NSAttributedString *text, NSRect frame) {
    if (text.length == 0) {
        return;
    }
    NSFont *font = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    CGFloat line = ceil(font.ascender - font.descender);
    NSRect box = NSMakeRect(frame.origin.x, frame.origin.y + (frame.size.height - line) / 2, frame.size.width, line);
    [text drawWithRect:box options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine];
}

// An image face's bevel, on each side.
const CGFloat QLMSkinLabelPadding = 6;

QLMSkinLabel QLMSkinLabelLayout(CGFloat faceWidth, CGFloat titleWidth, CGFloat led, CGFloat gap) {
    CGFloat lead = led > 0 ? led + gap : 0;
    CGFloat room = faceWidth - 2 * QLMSkinLabelPadding - lead;
    CGFloat width = MIN(titleWidth, MAX(room, 0));
    CGFloat x = round(faceWidth / 2 - (lead + width) / 2);
    QLMSkinLabel label;
    label.ledX = x;
    label.textX = x + lead;
    label.textWidth = width;
    return label;
}

// The caps' middle on the frame's: a label with no descenders, as most are,
// looks centered only so. The line's box puts it a little high or low,
// with the font's leading and descent.
void QLMSkinDrawCenteredCaps(NSAttributedString *text, NSRect frame) {
    if (text.length == 0) {
        return;
    }
    NSFont *font = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    // With no line fragment origin, the rect's origin is the baseline.
    NSRect baseline = NSMakeRect(frame.origin.x, NSMidY(frame) + font.capHeight / 2, frame.size.width, 0);
    [text drawWithRect:baseline options:0];
}

void QLMSkinDrawSlot(NSString *text, QLMSkinTextSlot *slot, NSRect frame, CGFloat scale, BOOL monoDigits, CGFloat alpha) {
    if (text.length == 0) {
        return;
    }
    NSColor *color = [QLMSkinNSColor(slot.color) colorWithAlphaComponent:slot.color.alpha * alpha];
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc]
        initWithString:text
            attributes:QLMSkinTextAttributes(QLMSkinSlotFont(slot, scale, monoDigits), color, slot.alignment,
                                             slot.tracking * scale)];
    if (!QLMSkinColorIsClear(slot.accentColor) && [text hasSuffix:@"."]) {
        NSColor *accent = [QLMSkinNSColor(slot.accentColor) colorWithAlphaComponent:slot.accentColor.alpha * alpha];
        [string addAttribute:NSForegroundColorAttributeName value:accent range:NSMakeRange(text.length - 1, 1)];
    }
    QLMSkinDrawAttributed(string, frame);
}
