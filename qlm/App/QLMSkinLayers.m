#import "QLMSkinLayers.h"

#import "QLMSkinDrawing.h"

@interface QLMSkinMaterial ()
@property (nonatomic) id image;  // a CGImage
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGRect center;  // in the image's unit space
@property (nonatomic) NSRect frame;
@property (nonatomic, copy) void (^draw)(void);
@end

static char QLMSkinTintsKey;
static char QLMSkinRendersKey;

static NSString *QLMSkinColorKey(QLMSkinColor color) {
    return [NSString stringWithFormat:@"%g,%g,%g,%g", color.red, color.green, color.blue, color.alpha];
}

// The image with `overlay` laid over it in its own shape, as
// QLMSkinDrawDimmed lays it. One color, so it commutes with the stretch.
static id QLMSkinTintedImage(QLMSkin *skin, NSString *name, NSInteger scale, CGImageRef image, QLMSkinColor overlay) {
    NSMutableDictionary<NSString *, id> *cache = QLMSkinAttached(skin, &QLMSkinTintsKey, ^id {
        return [NSMutableDictionary dictionary];
    });
    NSString *key = [NSString stringWithFormat:@"%@@%ldx|%@", name, (long)scale, QLMSkinColorKey(overlay)];
    if (cache[key] == nil) {
        CGRect rect = CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image));
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef cg = CGBitmapContextCreate(NULL, (size_t)rect.size.width, (size_t)rect.size.height, 8, 0, space,
                                                (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
        CGColorSpaceRelease(space);
        id tinted = nil;
        if (cg != NULL) {
            CGContextDrawImage(cg, rect, image);
            CGContextSetBlendMode(cg, kCGBlendModeSourceAtop);
            CGContextSetFillColorWithColor(cg, QLMSkinNSColor(overlay).CGColor);
            CGContextFillRect(cg, rect);
            tinted = CFBridgingRelease(CGBitmapContextCreateImage(cg));
            CGContextRelease(cg);
        }
        cache[key] = tinted ?: (__bridge id)image;
    }
    return cache[key];
}

@implementation QLMSkinMaterial

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
    CGFloat scale = layers.scale;
    BOOL dimmed = overlay.alpha > 0;
    QLMSkinMaterial *material = [[QLMSkinMaterial alloc] init];
    material.draw = ^{
        QLMSkinDrawDimmed(dimmed, overlay, frame, ^{
            QLMSkinDrawStyle(skin, style, state, frame, circle);
        });
    };
    QLMSkinDraw *draw = [style drawForState:state];
    if (draw == nil) {
        NSString *name = [style imageNameForState:state];
        CGImageRef one = QLMSkinDecodedImage(skin, name, 1);
        CGImageRef two = QLMSkinDecodedImage(skin, name, 2);
        if (one == NULL || two == NULL) {
            return nil;
        }
        NSInteger pick = scale > 1 ? 2 : 1;
        CGImageRef image = pick == 2 ? two : one;
        material.scale = pick;
        material.image = dimmed ? QLMSkinTintedImage(skin, name, pick, image, overlay) : (__bridge id)image;
        // The cap insets are in the image's points, the 1x file's pixels.
        CGFloat width = CGImageGetWidth(one);
        CGFloat height = CGImageGetHeight(one);
        NSEdgeInsets insets = style.capInsets;
        material.center = CGRectMake(insets.left / width, insets.top / height, (width - insets.left - insets.right) / width,
                                     (height - insets.top - insets.bottom) / height);
        material.frame = frame;
        return material;
    }

    // A shadow falls outside the frame, as it does in a view that doesn't
    // clip. The image lies on the window's pixels, as a view's backing
    // store does, so the layer shows it unresampled.
    QLMSkinShadow *shadow = draw.shadow;
    CGFloat margin = shadow ? ceil(2 * shadow.blur + MAX(fabs(shadow.offset.width), fabs(shadow.offset.height))) : 0;
    NSRect pixels = [layers pixelRect:NSInsetRect(frame, -margin, -margin)];
    NSRect inner = NSOffsetRect(frame, -pixels.origin.x, -pixels.origin.y);

    // Drawn narrow, with one column of pixels between its corners, which
    // the layer stretches: along a straight edge the block draws the same
    // throughout, so a resize draws nothing new. Its gradient runs top to
    // bottom, so a block with one keeps its height.
    CGRect center = CGRectMake(0, 0, 1, 1);
    NSSize size = pixels.size;
    if (!circle) {
        CGFloat corner = draw.inset + draw.radius + margin;
        CGFloat (^narrow)(CGFloat, CGFloat, CGFloat, CGFloat *, CGFloat *) =
            ^CGFloat(CGFloat start, CGFloat length, CGFloat total, CGFloat *capStart, CGFloat *span) {
                CGFloat lead = ceil((start + corner) * scale) + 1;
                CGFloat trail = ceil((total - start - length + corner) * scale) + 1;
                CGFloat whole = round(total * scale);
                if (lead + 1 + trail >= whole) {
                    *capStart = 0;
                    *span = 1;
                    return 0;
                }
                *capStart = lead / (lead + 1 + trail);
                *span = 1 / (lead + 1 + trail);
                return (whole - lead - 1 - trail) / scale;  // whole pixels, so the far edge keeps its place on them
            };
        CGFloat cut = narrow(inner.origin.x, inner.size.width, size.width, &center.origin.x, &center.size.width);
        inner.size.width -= cut;
        size.width -= cut;
        if (!draw.hasGradient) {
            cut = narrow(inner.origin.y, inner.size.height, size.height, &center.origin.y, &center.size.height);
            inner.size.height -= cut;
            size.height -= cut;
        }
    }
    NSMutableDictionary<NSString *, id> *cache = QLMSkinAttached(skin, &QLMSkinRendersKey, ^id {
        return [NSMutableDictionary dictionary];
    });
    NSString *key = [NSString stringWithFormat:@"%p|%ld|%@|%@|%g|%d|%@", style, (long)state, NSStringFromRect(inner),
                                               NSStringFromSize(size), scale, circle, QLMSkinColorKey(overlay)];
    id image = cache[key];
    if (image == nil) {
        image = CFBridgingRelease(QLMSkinRenderImage(size, scale, ^{
            QLMSkinDrawDimmed(dimmed, overlay, inner, ^{
                QLMSkinDrawStyle(skin, style, state, inner, circle);
            });
        }));
        if (image == nil) {
            return nil;
        }
        // A live resize makes a size a frame, so the cache keeps few.
        if (cache.count >= 64) {
            [cache removeAllObjects];
        }
        cache[key] = image;
    }
    material.image = image;
    material.scale = scale;
    material.center = center;
    material.frame = pixels;
    return material;
}

+ (instancetype)materialOfImage:(CGImageRef)image frame:(NSRect)frame layers:(QLMSkinLayers *)layers {
    QLMSkinMaterial *material = [[QLMSkinMaterial alloc] init];
    material.image = (__bridge id)image;
    material.scale = layers.scale;
    material.center = CGRectMake(0, 0, 1, 1);
    material.frame = frame;
    NSImage *drawn = [[NSImage alloc] initWithCGImage:image size:frame.size];
    material.draw = ^{
        QLMSkinDrawImage(drawn, frame);
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

- (void)drawRect:(NSRect)dirtyRect {
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
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = QLMSkinLayerGraphicsContext(context, layer.contentsScale);
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

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    [self.layers updateLayer];
}

- (void)drawRect:(NSRect)dirtyRect {
    [self.layers drawRect:dirtyRect];
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
