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

static CGFloat QLMSkinGlyphPhase(CGFloat device, CGFloat *whole) {
    CGFloat base = floor(device);
    CGFloat phase = round((device - base) * QLMSkinGlyphPhases) / QLMSkinGlyphPhases;
    if (phase >= 1) {
        base += 1;
        phase = 0;
    }
    *whole = base;
    return phase;
}

// The glyph at `phase` on the pixels, drawn as text draws it: filled in its
// color, then the overlay over its ink alone.
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
    BOOL dimmed = overlay.alpha > 0;
    CGImageRef image = QLMSkinRenderImage(NSMakeSize(pixels.width / scale, pixels.height / scale), scale, ^{
        CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
        if (dimmed) {
            CGContextBeginTransparencyLayer(cg, NULL);
        }
        CGContextSetFillColorWithColor(cg, color.CGColor);
        // The origin in the text matrix, so it holds whether the position
        // is read in user space or text space.
        CGContextSetTextMatrix(cg, CGAffineTransformMake(1, 0, 0, -1, origin.x / scale, origin.y / scale));
        CGPoint position = CGPointZero;
        CTFontDrawGlyphs(font, &glyph, &position, 1, cg);
        if (dimmed) {
            CGContextSetBlendMode(cg, kCGBlendModeSourceAtop);
            CGContextSetFillColorWithColor(cg, QLMSkinNSColor(overlay).CGColor);
            CGContextFillRect(cg, CGRectMake(0, 0, pixels.width / scale, pixels.height / scale));
            CGContextEndTransparencyLayer(cg);
        }
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

@implementation QLMSkinGlyphLine {
    __weak QLMSkinLayers *_layers;
    NSMutableArray<CALayer *> *_glyphs;
}

- (instancetype)initWithLayers:(QLMSkinLayers *)layers {
    self = [super init];
    if (self) {
        _layers = layers;
        _layer = [layers makeLayerOfClass:[CALayer class]];
        _glyphs = [NSMutableArray array];
        _text = @"";
    }
    return self;
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

- (CALayer *)glyphLayerAt:(NSUInteger)index {
    while (_glyphs.count <= index) {
        CALayer *layer = [_layers makeLayerOfClass:[CALayer class]];
        layer.contentsGravity = kCAGravityResize;
        [_glyphs addObject:layer];
        [_layer addSublayer:layer];
    }
    return _glyphs[index];
}

- (void)showText:(NSString *)text
            slot:(QLMSkinTextSlot *)slot
           frame:(NSRect)frame
       fontScale:(CGFloat)fontScale
      monoDigits:(BOOL)monoDigits
         overlay:(QLMSkinColor)overlay
            skin:(QLMSkin *)skin
          inView:(NSView *)view {
    _text = [text copy] ?: @"";
    _layer.frame = view.layer.bounds;
    NSUInteger used = 0;
    QLMSkinLayers *layers = _layers;
    if (text.length > 0 && layers != nil) {
        CGFloat scale = layers.scale;
        NSAttributedString *string = QLMSkinSlotString(text, slot, fontScale, monoDigits, 1);
        NSRect box = QLMSkinSlotLineBox(string, frame);
        CTLineRef line = QLMSkinGlyphCTLine(string, box.size.width);
        CGFloat width = MIN(box.size.width, CTLineGetTypographicBounds(line, NULL, NULL, NULL));
        CGFloat x = box.origin.x;
        if (slot.alignment == QLMSkinAlignmentCenter) {
            x += (box.size.width - width) / 2;
        } else if (slot.alignment == QLMSkinAlignmentRight) {
            x += box.size.width - width;
        }
        NSFont *font = [string attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        CGFloat baseline = box.origin.y + QLMSkinBaselineOffset(font);
        QLMSkinImages *images = [QLMSkinImages imagesOfSkin:skin];
        NSString *family = [NSString stringWithFormat:@"glyphs|%p|%g|%@", slot, scale, QLMSkinColorKey(overlay)];
        for (id run in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
            CTRunRef ctRun = (__bridge CTRunRef)run;
            CFIndex count = CTRunGetGlyphCount(ctRun);
            NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(ctRun);
            CTFontRef runFont = (__bridge CTFontRef)attributes[NSFontAttributeName];
            NSColor *color = attributes[NSForegroundColorAttributeName] ?: NSColor.blackColor;
            if (runFont == NULL || count == 0) {
                continue;
            }
            CGGlyph glyphs[count];
            CGPoint positions[count];
            CTRunGetGlyphs(ctRun, CFRangeMake(0, 0), glyphs);
            CTRunGetPositions(ctRun, CFRangeMake(0, 0), positions);
            NSString *fontKey = [NSString stringWithFormat:@"%@|%g|%@", CFBridgingRelease(CTFontCopyPostScriptName(runFont)),
                                                           CTFontGetSize(runFont), color];
            // A size a live resize passes through keeps only the family's
            // last few.
            NSMutableDictionary<NSString *, id> *cache =
                [images objectForKey:fontKey inFamily:family make:^id {
                    return [NSMutableDictionary dictionary];
                }];
            for (CFIndex i = 0; i < count; i++) {
                CGFloat wholeX = 0;
                CGFloat wholeY = 0;
                CGPoint phase = CGPointMake(QLMSkinGlyphPhase((x + positions[i].x) * scale, &wholeX),
                                            QLMSkinGlyphPhase((baseline - positions[i].y) * scale, &wholeY));
                NSString *key = [NSString stringWithFormat:@"%u|%g|%g", glyphs[i], phase.x, phase.y];
                id cached = cache[key];
                if (cached == nil) {
                    cached = QLMSkinMakeGlyphImage(runFont, glyphs[i], color, overlay, scale, phase) ?: NSNull.null;
                    cache[key] = cached;
                }
                if (cached == NSNull.null) {
                    continue;  // a space inks nothing
                }
                QLMSkinGlyphImage *image = cached;
                CALayer *layer = [self glyphLayerAt:used++];
                NSRect rect = NSMakeRect((wholeX - image.origin.x + phase.x) / scale, (wholeY - image.origin.y + phase.y) / scale,
                                         image.pixels.width / scale, image.pixels.height / scale);
                layer.contents = image.image;
                layer.contentsScale = scale;
                layer.frame = [view convertRectToLayer:rect];
                layer.hidden = NO;
            }
        }
        CFRelease(line);
    }
    for (NSUInteger i = used; i < _glyphs.count; i++) {
        _glyphs[i].hidden = YES;
        _glyphs[i].contents = nil;
    }
}

@end
