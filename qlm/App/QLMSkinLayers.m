#import "QLMSkinLayers.h"

#import "QLMSkinDrawing.h"
#import "QLMSkinImages.h"
#import "QLMViews.h"

const CFTimeInterval QLMSkinEaseSeconds = 0.14;

static NSInteger QLMSkinEaseHolds;

static BOOL QLMSkinMotionIsReduced(void) {
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

BOOL (*QLMSkinEaseWindowIsSeen)(NSWindow *window) = QLMWindowIsSeen;
BOOL (*QLMSkinEaseMotionIsReduced)(void) = QLMSkinMotionIsReduced;

BOOL QLMSkinEases(NSView *view) {
    return QLMSkinEaseHolds == 0 && QLMSkinEaseWindowIsSeen(view.window) && !QLMSkinEaseMotionIsReduced();
}

void QLMSkinWithoutEase(void (^block)(void)) {
    QLMSkinEaseHolds++;
    block();
    QLMSkinEaseHolds--;
}

// A layer never committed has no presentation, so its first value never
// eases.
void QLMSkinSetLayerValue(CALayer *layer, NSString *keyPath, id value, BOOL eases) {
    id from = eases ? [layer.presentationLayer valueForKeyPath:keyPath] : nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer setValue:value forKeyPath:keyPath];
    if (from != nil && ![from isEqual:value]) {
        CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:keyPath];
        ease.fromValue = from;
        ease.toValue = value;
        ease.duration = QLMSkinEaseSeconds;
        ease.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [layer addAnimation:ease forKey:keyPath];
    } else {
        [layer removeAnimationForKey:keyPath];
    }
    [CATransaction commit];
}

@interface QLMSkinLayers ()
// `rect`, grown to the window's pixels, in the view.
- (NSRect)pixelRect:(NSRect)rect;
@end

@interface QLMSkinMaterial ()
@property (nonatomic) id image;  // a CGImage
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGRect center;  // in the image's unit space
@property (nonatomic) NSRect frame;
@property (nonatomic, copy) void (^draw)(void);
@end

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
                            width:!circle height:!circle && draw.isUniformAlongHeight
                           family:family images:images layers:layers];
}

+ (instancetype)materialPainting:(void (^)(NSRect rect))paint
                           frame:(NSRect)frame
                          margin:(CGFloat)margin
                          family:(NSString *)family
                            skin:(QLMSkin *)skin
                          layers:(QLMSkinLayers *)layers {
    return [self materialPainting:paint frame:frame margin:margin corner:0 width:NO height:NO family:family
                           images:[QLMSkinImages imagesOfSkin:skin] layers:layers];
}

+ (instancetype)materialOfLED:(QLMSkinLED *)led
                         skin:(QLMSkin *)skin
                          lit:(BOOL)lit
                      enabled:(BOOL)enabled
                        frame:(NSRect)frame
                       layers:(QLMSkinLayers *)layers {
    return [self materialPainting:^(NSRect rect) {
        QLMSkinDrawLED(led, rect, lit, enabled);
    }
                            frame:frame
                           margin:ceil(2 * led.glow)
                           family:[NSString stringWithFormat:@"led|%d|%d", lit, enabled]
                             skin:skin
                           layers:layers];
}

@end

@implementation QLMSkinLayers {
    __weak NSView<QLMSkinLayered> *_view;
    NSMutableArray<CALayer *> *_materials;
    NSArray<CALayer *> *_movingLayers;
    CALayer *_content;
    NSRect _contentFrame;  // the content layer's frame, in the view, at the last update
    NSSize _size;          // the view's size at the last update
}

- (instancetype)initWithView:(NSView<QLMSkinLayered> *)view {
    self = [super init];
    if (self) {
        _view = view;
        _materials = [NSMutableArray array];
        _movingLayers = @[];
        _content = [CALayer layer];
        _content.delegate = self;
        view.wantsLayer = YES;
        view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        // TRAP: in a window, a size change alone calls no updateLayer under
        // any redraw policy, so the materials would keep their old frames.
        view.postsFrameChangedNotifications = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(viewFrameDidChange:)
                                                   name:NSViewFrameDidChangeNotification object:view];
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
    _size = view.bounds.size;
    NSArray<QLMSkinMaterial *> *materials = [view skinMaterials:self];
    while (_materials.count < materials.count) {
        CALayer *layer = [CALayer layer];
        layer.delegate = self;
        layer.contentsGravity = kCAGravityResize;
        [_materials addObject:layer];
    }
    NSArray<CALayer *> *sublayers = [[[_materials subarrayWithRange:NSMakeRange(0, materials.count)]
        arrayByAddingObjectsFromArray:_movingLayers] arrayByAddingObject:_content];
    if (![host.sublayers isEqualToArray:sublayers]) {
        host.sublayers = sublayers;
    }
    for (NSUInteger i = 0; i < materials.count; i++) {
        [self showMaterial:materials[i] inLayer:_materials[i]];
    }
    if ([view respondsToSelector:@selector(layoutSkinMovingLayers:)]) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [view layoutSkinMovingLayers:self];
        [CATransaction commit];
    }
    _contentFrame = [self contentFrame];
    _content.frame = [view convertRectToLayer:_contentFrame];
    _content.contentsScale = self.scale;
    [_content setNeedsDisplay];
}

- (void)showMaterial:(QLMSkinMaterial *)material inLayer:(CALayer *)layer {
    layer.contents = material.image;
    if (material == nil) {
        return;
    }
    layer.contentsScale = material.scale;
    layer.contentsCenter = material.center;
    layer.frame = [_view convertRectToLayer:material.frame];
}

- (__kindof CALayer *)makeLayerOfClass:(Class)layerClass {
    CALayer *layer = [layerClass layer];
    layer.delegate = self;
    return layer;
}

- (void)setMovingLayers:(NSArray<CALayer *> *)movingLayers {
    _movingLayers = [movingLayers copy];
    for (CALayer *layer in _movingLayers) {
        layer.delegate = self;
    }
    _view.needsDisplay = YES;
}

- (void)drawReference:(NSRect)dirtyRect {
    NSView<QLMSkinLayered> *view = _view;
    for (QLMSkinMaterial *material in [view skinMaterials:self]) {
        material.draw();
    }
    if ([view respondsToSelector:@selector(drawSkinMovingReference)]) {
        [view drawSkinMovingReference];
    }
    [view drawSkinContent:dirtyRect];
}

- (void)setNeedsDisplayInRect:(NSRect)rect {
    CGRect inLayer = NSOffsetRect(rect, -_contentFrame.origin.x, -_contentFrame.origin.y);
    if (!_content.contentsAreFlipped) {
        inLayer.origin.y = _content.bounds.size.height - CGRectGetMaxY(inLayer);
    }
    [_content setNeedsDisplayInRect:inLayer];
}

// A new size sets the materials again. A move off the pixels the content
// was drawn on draws it again. A hidden view waits for viewDidUnhide.
// TRAP: a size change within a pixel keeps the content's frame, but not
// the materials', so the size is checked too.
- (void)viewFrameDidChange:(NSNotification *)notification {
    NSView *view = _view;
    if (view.isHiddenOrHasHiddenAncestor) {
        return;
    }
    if (!NSEqualSizes(view.bounds.size, _size) || !NSEqualRects([self contentFrame], _contentFrame)) {
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
    CGContextTranslateCTM(context, -_contentFrame.origin.x, -_contentFrame.origin.y);
    // Core Animation clears a partial redraw's rect first, as a test checks
    // in a window, so no old text shows under the new.
    NSRect dirty = CGContextGetClipBoundingBox(context);
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

@end
