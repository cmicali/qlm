#import "QLMSkinLayers.h"

#import "QLMSkinDrawing.h"
#import "QLMSkinImages.h"

@interface QLMSkinMaterial ()
@property (nonatomic) id image;  // a CGImage
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGRect center;  // in the image's unit space
@property (nonatomic) NSRect frame;
@property (nonatomic, copy) void (^draw)(void);
@end

static NSString *QLMSkinColorKey(QLMSkinColor color) {
    return [NSString stringWithFormat:@"%g,%g,%g,%g", color.red, color.green, color.blue, color.alpha];
}

// To an eighth of a pixel, so a key holds through a float's noise.
static NSString *QLMSkinRectKey(NSRect rect, CGFloat scale) {
    CGFloat step = 1 / (scale * 8);
    return [NSString stringWithFormat:@"%g,%g,%g,%g", round(rect.origin.x / step) * step, round(rect.origin.y / step) * step,
                                      round(rect.size.width / step) * step, round(rect.size.height / step) * step];
}

// One axis of a narrow draw: the cap before the column the layer
// stretches, the column, and the cap after, in pixels.
typedef struct {
    CGFloat cut;       // points taken out between the caps, or 0
    CGFloat capStart;  // the column's start and span, in the image's unit space
    CGFloat span;
} QLMSkinNarrowing;

// Along an axis of `total` points, a shape from `start` for `length`, with
// `corner` points at each end that don't stretch. It cuts whole pixels, so
// the far edge keeps its place on them.
static QLMSkinNarrowing QLMSkinNarrow(CGFloat start, CGFloat length, CGFloat total, CGFloat corner, CGFloat scale) {
    CGFloat lead = ceil((start + corner) * scale) + 1;
    CGFloat trail = ceil((total - start - length + corner) * scale) + 1;
    CGFloat whole = round(total * scale);
    CGFloat narrow = lead + 1 + trail;
    if (narrow >= whole) {
        return (QLMSkinNarrowing){0, 0, 1};
    }
    return (QLMSkinNarrowing){(whole - narrow) / scale, lead / narrow, 1 / narrow};
}

@implementation QLMSkinMaterial

// What `paint` draws in `frame`, grown by `margin`, drawn on the window's
// pixels as a view's backing store is, so the layer shows it unresampled.
// With `corner`, it draws narrow along each uniform axis, with one column
// of pixels between corners that wide, which the layer stretches.
+ (nullable instancetype)materialPainting:(void (^)(NSRect rect))paint
                                    frame:(NSRect)frame
                                   margin:(CGFloat)margin
                                   corner:(CGFloat)corner
                                    width:(BOOL)narrowWidth
                                   height:(BOOL)narrowHeight
                                   family:(NSString *)family
                                   images:(QLMSkinImages *)images
                                   layers:(QLMSkinLayers *)layers {
    CGFloat scale = layers.scale;
    NSRect pixels = [layers pixelRect:NSInsetRect(frame, -margin, -margin)];
    NSRect inner = NSOffsetRect(frame, -pixels.origin.x, -pixels.origin.y);
    NSSize size = pixels.size;
    CGRect center = CGRectMake(0, 0, 1, 1);
    if (narrowWidth) {
        QLMSkinNarrowing x = QLMSkinNarrow(inner.origin.x, inner.size.width, size.width, corner, scale);
        inner.size.width -= x.cut;
        size.width -= x.cut;
        center.origin.x = x.capStart;
        center.size.width = x.span;
    }
    if (narrowHeight) {
        QLMSkinNarrowing y = QLMSkinNarrow(inner.origin.y, inner.size.height, size.height, corner, scale);
        inner.size.height -= y.cut;
        size.height -= y.cut;
        center.origin.y = y.capStart;
        center.size.height = y.span;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@|%g", QLMSkinRectKey(inner, scale),
                                               QLMSkinRectKey((NSRect){NSZeroPoint, size}, scale), scale];
    id image = [images objectForKey:key inFamily:family make:^id {
        return CFBridgingRelease(QLMSkinRenderImage(size, scale, ^{
            paint(inner);
        }));
    }];
    if (image == nil) {
        return nil;
    }
    QLMSkinMaterial *material = [[QLMSkinMaterial alloc] init];
    material.image = image;
    material.scale = scale;
    material.center = center;
    material.frame = pixels;
    material.draw = ^{
        paint(frame);
    };
    return material;
}

+ (instancetype)materialOfStyle:(QLMSkinStyle *)style
                           skin:(QLMSkin *)skin
                          state:(QLMSkinState)state
                          frame:(NSRect)frame
                         circle:(BOOL)circle
                        overlay:(QLMSkinColor)overlay
                         layers:(QLMSkinLayers *)layers {
    if (frame.size.width <= 0 || frame.size.height <= 0) {
        return nil;
    }
    BOOL dimmed = overlay.alpha > 0;
    void (^paint)(NSRect) = ^(NSRect rect) {
        QLMSkinDrawDimmed(dimmed, overlay, rect, ^{
            QLMSkinDrawStyle(skin, style, state, rect, circle);
        });
    };
    QLMSkinImages *images = [QLMSkinImages imagesOfSkin:skin];
    QLMSkinDraw *draw = [style drawForState:state];
    if (draw == nil) {
        NSString *name = [style imageNameForState:state];
        NSInteger scale = QLMSkinImageFileScale(layers.scale);
        CGImageRef image = [images decodedImage:name scale:scale];
        if (image == NULL) {
            return nil;
        }
        // The cap insets are in the image's points.
        NSSize points = NSMakeSize(CGImageGetWidth(image) / (CGFloat)scale, CGImageGetHeight(image) / (CGFloat)scale);
        QLMSkinMaterial *material = [[QLMSkinMaterial alloc] init];
        material.image = (__bridge id)image;
        if (dimmed) {
            // The overlay is one color, so it commutes with the stretch.
            NSString *key = [NSString stringWithFormat:@"tint|%@|%ld|%@", name, (long)scale, QLMSkinColorKey(overlay)];
            material.image = [images objectForKey:key make:^id {
                NSImage *plain = [[NSImage alloc] initWithCGImage:image size:points];
                return CFBridgingRelease(QLMSkinRenderImage(points, scale, ^{
                    NSRect rect = (NSRect){NSZeroPoint, points};
                    QLMSkinDrawDimmed(YES, overlay, rect, ^{
                        QLMSkinDrawImage(plain, rect);
                    });
                }));
            }] ?: material.image;
        }
        NSEdgeInsets insets = style.capInsets;
        material.scale = scale;
        material.center = CGRectMake(insets.left / points.width, insets.top / points.height,
                                     (points.width - insets.left - insets.right) / points.width,
                                     (points.height - insets.top - insets.bottom) / points.height);
        material.frame = frame;
        material.draw = ^{
            paint(frame);
        };
        return material;
    }
    // A shadow falls outside the frame, as it does in a view that doesn't
    // clip.
    QLMSkinShadow *shadow = draw.shadow;
    CGFloat margin = shadow ? ceil(2 * shadow.blur + MAX(fabs(shadow.offset.width), fabs(shadow.offset.height))) : 0;
    NSString *family = [NSString stringWithFormat:@"style|%p|%ld|%d|%@", style, (long)state, circle, QLMSkinColorKey(overlay)];
    return [self materialPainting:paint frame:frame margin:margin corner:draw.inset + draw.radius + margin
                            width:!circle && draw.isUniformAlongWidth height:!circle && draw.isUniformAlongHeight
                           family:family images:images layers:layers];
}

+ (instancetype)materialOfLED:(QLMSkinLED *)led
                         skin:(QLMSkin *)skin
                          lit:(BOOL)lit
                      enabled:(BOOL)enabled
                        frame:(NSRect)frame
                       layers:(QLMSkinLayers *)layers {
    NSString *family = [NSString stringWithFormat:@"led|%d|%d", lit, enabled];
    return [self materialPainting:^(NSRect rect) {
        QLMSkinDrawLED(led, rect, lit, enabled);
    }
                            frame:frame
                           margin:ceil(2 * led.glow)
                           corner:0
                            width:NO
                           height:NO
                           family:family
                           images:[QLMSkinImages imagesOfSkin:skin]
                           layers:layers];
}

+ (instancetype)materialOfImage:(CGImageRef)image frame:(NSRect)frame layers:(QLMSkinLayers *)layers {
    QLMSkinMaterial *material = [[QLMSkinMaterial alloc] init];
    material.image = (__bridge id)image;
    material.scale = layers.scale;
    material.center = CGRectMake(0, 0, 1, 1);
    material.frame = frame;
    material.draw = ^{
        QLMSkinDrawImage([[NSImage alloc] initWithCGImage:image size:frame.size], frame);
    };
    return material;
}

@end

@implementation QLMSkinLayers {
    __weak NSView<QLMSkinLayered> *_view;
    NSMutableArray<CALayer *> *_materials;
    CALayer *_content;
    NSPoint _contentOrigin;  // the content layer's origin, in the view
}

- (instancetype)initWithView:(NSView<QLMSkinLayered> *)view {
    self = [super init];
    if (self) {
        _view = view;
        _materials = [NSMutableArray array];
        _content = [CALayer layer];
        _content.delegate = self;
        view.wantsLayer = YES;
        view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    }
    return self;
}

- (CGFloat)scale {
    NSView *view = _view;
    CGFloat scale = view.window != nil ? view.window.backingScaleFactor : view.layer.contentsScale;
    return MAX(1, scale);
}

- (NSRect)pixelRect:(NSRect)rect {
    return [_view backingAlignedRect:rect options:NSAlignAllEdgesOutward];
}

- (NSRect)contentFrame {
    NSView *view = _view;
    return [self pixelRect:NSInsetRect(view.bounds, -self.contentOutset, -self.contentOutset)];
}

- (void)updateLayer {
    NSView<QLMSkinLayered> *view = _view;
    // A subview's layer would sit among the view's own sublayers.
    NSAssert(view.subviews.count == 0, @"a layered view is a leaf");
    CALayer *host = view.layer;
    NSArray<QLMSkinMaterial *> *materials = [view skinMaterials:self];
    while (_materials.count < materials.count) {
        CALayer *layer = [CALayer layer];
        layer.delegate = self;
        layer.contentsGravity = kCAGravityResize;
        [_materials addObject:layer];
    }
    NSArray<CALayer *> *sublayers = [[_materials subarrayWithRange:NSMakeRange(0, materials.count)] arrayByAddingObject:_content];
    if (![host.sublayers isEqualToArray:sublayers]) {
        host.sublayers = sublayers;
    }
    for (NSUInteger i = 0; i < materials.count; i++) {
        QLMSkinMaterial *material = materials[i];
        CALayer *layer = _materials[i];
        layer.contents = material.image;
        layer.contentsScale = material.scale;
        layer.contentsCenter = material.center;
        layer.frame = [view convertRectToLayer:material.frame];
    }
    NSRect frame = [self contentFrame];
    _contentOrigin = frame.origin;
    _content.frame = [view convertRectToLayer:frame];
    _content.contentsScale = self.scale;
    [_content setNeedsDisplay];
}

- (void)drawReference:(NSRect)dirtyRect {
    NSView<QLMSkinLayered> *view = _view;
    for (QLMSkinMaterial *material in [view skinMaterials:self]) {
        material.draw();
    }
    [view drawSkinContent:dirtyRect];
}

- (void)setNeedsDisplayInRect:(NSRect)rect {
    CGRect inLayer = NSOffsetRect(rect, -_contentOrigin.x, -_contentOrigin.y);
    if (!_content.contentsAreFlipped) {
        inLayer.origin.y = _content.bounds.size.height - CGRectGetMaxY(inLayer);
    }
    [_content setNeedsDisplayInRect:inLayer];
}

- (void)viewDidMove {
    NSView *view = _view;
    if (view.window != nil && !NSEqualPoints([self contentFrame].origin, _contentOrigin)) {
        view.needsDisplay = YES;
    }
}

#pragma mark - CALayerDelegate

- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
    return (id<CAAction>)NSNull.null;
}

// In the view's coordinates, y down, as its drawRect: would draw.
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context {
    NSView<QLMSkinLayered> *view = _view;
    if (layer != _content || view == nil) {
        return;
    }
    CGContextSaveGState(context);
    if (!layer.contentsAreFlipped) {
        CGContextTranslateCTM(context, 0, layer.bounds.size.height);
        CGContextScaleCTM(context, 1, -1);
    }
    CGContextTranslateCTM(context, -_contentOrigin.x, -_contentOrigin.y);
    NSRect dirty = CGContextGetClipBoundingBox(context);
    // TRAP: a partial redraw keeps what was there, so the old text would
    // show under the new. A whole one starts clear, and its clear here
    // would cost a live resize a frame's fill of the window.
    NSRect whole = NSMakeRect(_contentOrigin.x, _contentOrigin.y, layer.bounds.size.width, layer.bounds.size.height);
    if (!NSContainsRect(dirty, whole)) {
        CGContextClearRect(context, dirty);
    }
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:YES];
    [view drawSkinContent:dirty];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(context);
}

@end

@implementation QLMSkinLayerView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _layers = [[QLMSkinLayers alloc] initWithView:self];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

// QLMSkinControl holds the same glue, as an NSControl.
- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    [self.layers updateLayer];
}

- (void)setFrameOrigin:(NSPoint)origin {
    [super setFrameOrigin:origin];
    [self.layers viewDidMove];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    self.needsDisplay = YES;
}

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    return @[];
}

- (void)drawSkinContent:(NSRect)dirtyRect {
}

@end
