#import "QLMSkinDrawing.h"

#import <CoreText/CoreText.h>

NSColor *QLMSkinNSColor(QLMSkinColor color) {
    return [NSColor colorWithSRGBRed:color.red green:color.green blue:color.blue alpha:color.alpha];
}

BOOL QLMSkinColorIsClear(QLMSkinColor color) {
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

NSImage *QLMSkinImage(QLMSkin *skin, NSString *name) {
    static NSCache<NSString *, NSImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
    });
    NSString *key = [skin imageURLForName:name scale:1].path;
    NSImage *image = [cache objectForKey:key];
    if (image != nil) {
        return image;
    }
    NSImageRep *one = QLMSkinImageRep([skin imageURLForName:name scale:1], 1);
    NSImageRep *two = QLMSkinImageRep([skin imageURLForName:name scale:2], 2);
    if (one == nil || two == nil) {
        return nil;
    }
    image = [[NSImage alloc] initWithSize:one.size];
    [image addRepresentation:one];
    [image addRepresentation:two];
    [cache setObject:image forKey:key];
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
static NSShadow *QLMSkinNSShadow(QLMSkinColor color, CGFloat blur, CGSize offset) {
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = QLMSkinNSColor(color);
    shadow.shadowBlurRadius = blur;
    shadow.shadowOffset = NSMakeSize(offset.width, -offset.height);
    return shadow;
}

static void QLMSkinDrawBlock(QLMSkinDraw *draw, NSRect rect, BOOL circle) {
    rect = NSInsetRect(rect, draw.inset, draw.inset);
    if (rect.size.width <= 0 || rect.size.height <= 0) {
        return;
    }
    NSBezierPath *shape = QLMSkinShape(rect, draw.radius, circle);
    if (draw.shadow != nil) {
        [NSGraphicsContext saveGraphicsState];
        [QLMSkinNSShadow(draw.shadow.color, draw.shadow.blur, draw.shadow.offset) set];
        [(draw.hasGradient ? QLMSkinNSColor(draw.gradientBottom) : QLMSkinNSColor(draw.fill)) setFill];
        [shape fill];
        [NSGraphicsContext restoreGraphicsState];
    }
    if (draw.hasGradient) {
        NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:QLMSkinNSColor(draw.gradientTop)
                                                             endingColor:QLMSkinNSColor(draw.gradientBottom)];
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
    NSImage *image = [QLMSkinImage(skin, [style imageNameForState:state]) copy];
    if (image == nil) {
        return;
    }
    image.capInsets = style.capInsets;
    image.resizingMode = NSImageResizingModeStretch;
    [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
       respectFlipped:YES hints:nil];
}

void QLMSkinDrawLED(QLMSkinLED *led, NSRect rect, BOOL lit, BOOL enabled) {
    NSBezierPath *dot = QLMSkinShape(rect, 0, YES);
    [NSGraphicsContext saveGraphicsState];
    if (!enabled) {
        QLMSkinColor off = led.off;
        off.alpha *= 0.4;
        [QLMSkinNSColor(off) setFill];
    }
    else if (lit) {
        if (led.glow > 0) {
            [QLMSkinNSShadow(led.on, led.glow, CGSizeZero) set];
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

NSFont *QLMSkinFont(NSString *name, BOOL mono, CGFloat size, QLMSkinWeight weight, BOOL italic, BOOL monoDigits) {
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

NSFont *QLMSkinSlotFont(QLMSkinTextSlot *slot, CGFloat scale, BOOL monoDigits) {
    return QLMSkinFont(slot.fontName, slot.mono, slot.size * scale, slot.weight, slot.italic, monoDigits);
}

NSDictionary<NSAttributedStringKey, id> *QLMSkinTextAttributes(NSFont *font, NSColor *color, QLMSkinAlignment alignment,
                                                               CGFloat tracking) {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = alignment == QLMSkinAlignmentCenter ? NSTextAlignmentCenter
                          : alignment == QLMSkinAlignmentRight ? NSTextAlignmentRight : NSTextAlignmentLeft;
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph,
        NSKernAttributeName: @(tracking),
    };
}

void QLMSkinDrawAttributed(NSAttributedString *text, NSRect frame) {
    if (text.length == 0) {
        return;
    }
    NSFont *font = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    CGFloat line = ceil(font.ascender - font.descender);
    NSRect box = NSMakeRect(frame.origin.x, frame.origin.y + (frame.size.height - line) / 2, frame.size.width, line);
    [text drawWithRect:box options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine];
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
