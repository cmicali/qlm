#import "QLMSkinGlyphs.h"

#import <CoreText/CoreText.h>

#import "QLMSkinDrawing.h"
#import "QLMSkinImages.h"
#import "QLMSkinLayers.h"

// A glyph's place on the pixels, in sixteenths: far finer than any eye
// sees, and few enough images.
static const CGFloat QLMSkinGlyphPhases = 16;
// Pixels around a glyph's bounds, for its antialiasing.
static const CGFloat QLMSkinGlyphPad = 2;

// One glyph's image and where its origin sits in it, in pixels, y down.
@interface QLMSkinGlyphImage : NSObject
@property (nonatomic) id image;  // a CGImage
@property (nonatomic) CGPoint origin;
@property (nonatomic) CGSize pixels;
@end

@implementation QLMSkinGlyphImage
@end

// A font's glyphs in one color, overlay, and scale, by glyph and phase.
@interface QLMSkinGlyphFont : NSObject
@property (nonatomic) CGFloat baseline;  // below the line's top
@property (nonatomic) NSMutableDictionary<NSNumber *, id> *glyphs;
@end

@implementation QLMSkinGlyphFont
@end

// A sixteenth of a pixel, and the whole pixel left of it.
static NSInteger QLMSkinGlyphPhase(CGFloat device, CGFloat *whole) {
    CGFloat base = floor(device);
    NSInteger phase = (NSInteger)round((device - base) * QLMSkinGlyphPhases);
    if (phase >= QLMSkinGlyphPhases) {
        base += 1;
        phase = 0;
    }
    *whole = base;
    return phase;
}

// The glyph at `phase` on the pixels, drawn as text draws it: filled in its
// color, then dimmed in its own shape.
static QLMSkinGlyphImage *_Nullable QLMSkinMakeGlyphImage(CTFontRef font, CGGlyph glyph, NSColor *color, QLMSkinColor overlay,
                                                          CGFloat scale, CGPoint phase) {
    CGRect bounds = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal, &glyph, NULL, 1);
    if (CGRectIsEmpty(bounds)) {
        return nil;
    }
    CGFloat left = floor(phase.x + CGRectGetMinX(bounds) * scale) - QLMSkinGlyphPad;
    CGFloat right = ceil(phase.x + CGRectGetMaxX(bounds) * scale) + QLMSkinGlyphPad;
    CGFloat top = floor(phase.y - CGRectGetMaxY(bounds) * scale) - QLMSkinGlyphPad;
    CGFloat bottom = ceil(phase.y - CGRectGetMinY(bounds) * scale) + QLMSkinGlyphPad;
    CGPoint origin = CGPointMake(phase.x - left, phase.y - top);
    CGSize pixels = CGSizeMake(right - left, bottom - top);
    NSSize points = NSMakeSize(pixels.width / scale, pixels.height / scale);
    CGImageRef image = QLMSkinRenderImage(points, scale, ^{
        QLMSkinDrawDimmed(overlay.alpha > 0, overlay, (NSRect){NSZeroPoint, points}, ^{
            CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
            CGContextSetFillColorWithColor(cg, color.CGColor);
            // The origin in the text matrix, so it holds whether the
            // position is read in user space or text space.
            CGContextSetTextMatrix(cg, CGAffineTransformMake(1, 0, 0, -1, origin.x / scale, origin.y / scale));
            CGPoint position = CGPointZero;
            CTFontDrawGlyphs(font, &glyph, &position, 1, cg);
        });
    });
    if (image == NULL) {
        return nil;
    }
    QLMSkinGlyphImage *made = [[QLMSkinGlyphImage alloc] init];
    made.image = CFBridgingRelease(image);
    made.origin = origin;
    made.pixels = pixels;
    return made;
}

// The line, cut with an ellipsis where it overflows the box, as text
// drawing truncates its tail.
static CTLineRef QLMSkinGlyphCTLine(NSAttributedString *string, CGFloat width) CF_RETURNS_RETAINED {
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) <= width) {
        return line;
    }
    NSDictionary *attributes = [string attributesAtIndex:string.length - 1 effectiveRange:NULL];
    NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"…" attributes:attributes];
    CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)ellipsis);
    CTLineRef cut = CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token);
    CFRelease(token);
    if (cut == NULL) {
        return line;
    }
    CFRelease(line);
    return cut;
}

@implementation QLMSkinGlyphLine {
    __weak QLMSkinLayers *_layers;
    NSMutableArray<CALayer *> *_glyphs;
    NSUInteger _shownCount;
    // The last call's inputs, so a call that changes nothing does nothing.
    NSString *_text;
    NSRect _frame;
    CGFloat _fontScale;
    QLMSkinColor _overlay;
    CGFloat _scale;
    CGRect _bounds;
    // The resolved fonts' glyphs, for this slot, scale, and overlay.
    NSMutableDictionary<NSString *, QLMSkinGlyphFont *> *_fonts;
    NSString *_fontsKey;
}

- (instancetype)initWithLayers:(QLMSkinLayers *)layers {
    self = [super init];
    if (self) {
        _layers = layers;
        _layer = [layers makeLayerOfClass:[CALayer class]];
        _glyphs = [NSMutableArray array];
    }
    return self;
}

- (CALayer *)glyphLayerAt:(NSUInteger)index {
    while (_glyphs.count <= index) {
        CALayer *layer = [_layers makeLayerOfClass:[CALayer class]];
        layer.contentsGravity = kCAGravityResize;
        [_glyphs addObject:layer];
        [_layer addSublayer:layer];
    }
    return _glyphs[index];
}

// Where text drawing puts the baseline below a line's top. TRAP: not the
// font's ascender, which sets glyphs up to half a point off.
static CGFloat QLMSkinBaselineOffset(NSFont *font) {
    static NSLayoutManager *layout;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        layout = [[NSLayoutManager alloc] init];
    });
    return [layout defaultBaselineOffsetForFont:font];
}

- (QLMSkinGlyphFont *)glyphsOfFont:(CTFontRef)font color:(NSColor *)color family:(NSString *)family skin:(QLMSkin *)skin {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&red green:&green blue:&blue alpha:&alpha];
    QLMSkinColor rgba = {red, green, blue, alpha};
    NSString *key = [NSString stringWithFormat:@"%@|%g|%@", CFBridgingRelease(CTFontCopyPostScriptName(font)), CTFontGetSize(font),
                                               QLMSkinColorKey(rgba)];
    QLMSkinGlyphFont *glyphs = _fonts[key];
    if (glyphs == nil) {
        // A size a live resize passes through keeps only the family's last
        // few.
        glyphs = [[QLMSkinImages imagesOfSkin:skin] objectForKey:key inFamily:family make:^id {
            QLMSkinGlyphFont *made = [[QLMSkinGlyphFont alloc] init];
            made.baseline = QLMSkinBaselineOffset((__bridge NSFont *)font);
            made.glyphs = [NSMutableDictionary dictionary];
            return made;
        }];
        _fonts[key] = glyphs;
    }
    return glyphs;
}

- (void)showText:(NSString *)text
            slot:(QLMSkinTextSlot *)slot
           frame:(NSRect)frame
       fontScale:(CGFloat)fontScale
      monoDigits:(BOOL)monoDigits
         overlay:(QLMSkinColor)overlay
            skin:(QLMSkin *)skin
          inView:(NSView *)view {
    QLMSkinLayers *layers = _layers;
    CGFloat scale = layers.scale;
    CGRect bounds = view.layer.bounds;
    if (QLMSkinSameText(text, _text) && NSEqualRects(frame, _frame) && fontScale == _fontScale && scale == _scale
        && CGRectEqualToRect(bounds, _bounds) && memcmp(&overlay, &_overlay, sizeof overlay) == 0) {
        return;
    }
    _text = [text copy];
    _frame = frame;
    _fontScale = fontScale;
    _scale = scale;
    _bounds = bounds;
    _overlay = overlay;
    if (!CGRectEqualToRect(_layer.frame, bounds)) {
        _layer.frame = bounds;
    }
    NSString *family = [NSString stringWithFormat:@"glyphs|%p|%g|%@", slot, scale, QLMSkinColorKey(overlay)];
    if (![family isEqualToString:_fontsKey]) {
        _fontsKey = family;
        _fonts = [NSMutableDictionary dictionary];
    }
    NSUInteger used = 0;
    if (text.length > 0 && layers != nil) {
        NSAttributedString *string = QLMSkinSlotString(text, slot, fontScale, monoDigits, 1);
        NSFont *font = [string attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSRect box = QLMSkinLineBox(font, frame);
        CTLineRef line = QLMSkinGlyphCTLine(string, box.size.width);
        CGFloat width = MIN(box.size.width, CTLineGetTypographicBounds(line, NULL, NULL, NULL));
        CGFloat x = box.origin.x;
        if (slot.alignment == QLMSkinAlignmentCenter) {
            x += (box.size.width - width) / 2;
        } else if (slot.alignment == QLMSkinAlignmentRight) {
            x += box.size.width - width;
        }
        for (id run in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
            CTRunRef ctRun = (__bridge CTRunRef)run;
            CFIndex count = CTRunGetGlyphCount(ctRun);
            NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(ctRun);
            CTFontRef runFont = (__bridge CTFontRef)attributes[NSFontAttributeName];
            NSColor *color = attributes[NSForegroundColorAttributeName] ?: NSColor.blackColor;
            if (runFont == NULL || count == 0) {
                continue;
            }
            QLMSkinGlyphFont *glyphFont = [self glyphsOfFont:runFont color:color family:family skin:skin];
            CGFloat baseline = box.origin.y + glyphFont.baseline;
            CGGlyph glyphs[count];
            CGPoint positions[count];
            CTRunGetGlyphs(ctRun, CFRangeMake(0, 0), glyphs);
            CTRunGetPositions(ctRun, CFRangeMake(0, 0), positions);
            for (CFIndex i = 0; i < count; i++) {
                CGFloat wholeX = 0;
                CGFloat wholeY = 0;
                NSInteger phaseX = QLMSkinGlyphPhase((x + positions[i].x) * scale, &wholeX);
                NSInteger phaseY = QLMSkinGlyphPhase((baseline - positions[i].y) * scale, &wholeY);
                NSNumber *key = @(((NSInteger)glyphs[i] * 16 + phaseX) * 16 + phaseY);
                id cached = glyphFont.glyphs[key];
                CGPoint phase = CGPointMake(phaseX / QLMSkinGlyphPhases, phaseY / QLMSkinGlyphPhases);
                if (cached == nil) {
                    cached = QLMSkinMakeGlyphImage(runFont, glyphs[i], color, overlay, scale, phase) ?: NSNull.null;
                    glyphFont.glyphs[key] = cached;
                }
                if (cached == NSNull.null) {
                    continue;  // a space inks nothing
                }
                QLMSkinGlyphImage *image = cached;
                CALayer *layer = [self glyphLayerAt:used++];
                NSRect rect = NSMakeRect((wholeX - image.origin.x + phase.x) / scale, (wholeY - image.origin.y + phase.y) / scale,
                                         image.pixels.width / scale, image.pixels.height / scale);
                CGRect inLayer = [view convertRectToLayer:rect];
                if (layer.contents != image.image) {
                    layer.contents = image.image;
                }
                if (layer.contentsScale != scale) {
                    layer.contentsScale = scale;
                }
                if (!CGRectEqualToRect(layer.frame, inLayer)) {
                    layer.frame = inLayer;
                }
                if (layer.hidden) {
                    layer.hidden = NO;
                }
            }
        }
        CFRelease(line);
    }
    for (NSUInteger i = used; i < _shownCount; i++) {
        _glyphs[i].hidden = YES;
        _glyphs[i].contents = nil;
    }
    _shownCount = used;
}

@end
