#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMSkinLayers;

// A piece of a view's material: an image in a frame of the view, which its
// layer stretches through the image's centre, as cap insets do.
@interface QLMSkinMaterial : NSObject

// The style's material for `state` in `frame`. An image style's is its
// file, decoded once. A drawn style's is drawn into a bitmap per size,
// state, scale, and place on the pixels, and kept among its family's last
// 4. A clear overlay lays nothing over it.
+ (nullable instancetype)materialOfStyle:(QLMSkinStyle *)style
                                    skin:(QLMSkin *)skin
                                   state:(QLMSkinState)state
                                   frame:(NSRect)frame
                                  circle:(BOOL)circle
                                 overlay:(QLMSkinColor)overlay
                                  layers:(QLMSkinLayers *)layers;

// An LED in `frame`, with its glow, drawn into a bitmap, as every shadow
// is.
+ (nullable instancetype)materialOfLED:(QLMSkinLED *)led
                                  skin:(QLMSkin *)skin
                                   lit:(BOOL)lit
                               enabled:(BOOL)enabled
                                 frame:(NSRect)frame
                                layers:(QLMSkinLayers *)layers;

// What `paint` draws in the rect it is handed, `frame` grown by `margin`,
// drawn into a bitmap on the window's pixels, among `family`'s last 4.
+ (nullable instancetype)materialPainting:(void (^)(NSRect rect))paint
                                    frame:(NSRect)frame
                                   margin:(CGFloat)margin
                                   family:(NSString *)family
                                     skin:(QLMSkin *)skin
                                   layers:(QLMSkinLayers *)layers;

- (instancetype)init NS_UNAVAILABLE;

// Where its layer sits, in the view.
@property (nonatomic, readonly) NSRect frame;

@end

// A view whose skin material is layer contents.
@protocol QLMSkinLayered <NSObject>
// The material for the view's state, bottom first.
- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers;
// What the view draws over its material, in its flipped bounds.
- (void)drawSkinContent:(NSRect)dirtyRect;
@optional
// Sets the moving layers' geometry and look for the view's state, with no
// ease. Each update of the layers calls it, after the materials.
- (void)layoutSkinMovingLayers:(QLMSkinLayers *)layers;
// What the moving layers show at rest, drawn: the tests' reference.
- (void)drawSkinMovingReference;
@end

// A view's material as its layer's contents, beneath the content it draws,
// so a change of its text composites the material rather than drawing it
// again. No image draws in drawRect:, which on the screen costs far more
// than a composite.
//
// The view's layer holds one sublayer per material, then one for the
// drawn content on top. The view is a leaf: a subview's layer would sit
// among them. It returns YES from wantsUpdateLayer, and calls updateLayer
// here from its own. Each setNeedsDisplay of the view sets the material
// and draws the content again, as each change of the view's size does.
// The content draws no shadow: a layer's own context casts one apart from
// a view's.
//
// What moves with a level, as the knob's pointer and the OSD's bar do, is
// in moving layers between the material and the content. A change of the
// level sets a property of one, which the render server eases, so a step
// draws nothing.
@interface QLMSkinLayers : NSObject <CALayerDelegate>

- (instancetype)initWithView:(NSView<QLMSkinLayered> *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The window's backing scale, or the view's layer's outside a window.
@property (nonatomic, readonly) CGFloat scale;
// How far past the view's bounds its content draws, as a focus ring does.
@property (nonatomic) CGFloat contentOutset;

- (void)updateLayer;
// Each material's own drawing, then the content, into the current context:
// the tests' reference for what the layers composite.
- (void)drawReference:(NSRect)dirtyRect;
// Draws only part of the content again, and sets no material.
- (void)setNeedsDisplayInRect:(NSRect)rect;

// A layer that takes no implicit animation, for a moving layer or one
// inside it.
- (__kindof CALayer *)makeLayerOfClass:(Class)layerClass;
// The view's own layers, bottom first, over its material.
@property (nonatomic, copy) NSArray<CALayer *> *movingLayers;
// Puts `material` in `layer`, at the material's frame in the view, in the
// view's layer's coordinates.
- (void)showMaterial:(nullable QLMSkinMaterial *)material inLayer:(CALayer *)layer;

@end

// How long a level's change eases, ending slow.
extern const CFTimeInterval QLMSkinEaseSeconds;

// Whether a change in `view` eases: its window is seen, the user hasn't
// asked for less motion, and no QLMSkinWithoutEase is running.
BOOL QLMSkinEases(NSView *view);
// Runs `block` with no ease, as a window coming into view catches up.
void QLMSkinWithoutEase(void (^block)(void));
// What QLMSkinEases asks. The tests swap them.
extern BOOL (*QLMSkinEaseWindowIsSeen)(NSWindow *_Nullable window);
extern BOOL (*QLMSkinEaseMotionIsReduced)(void);

// Sets `value` at `keyPath`. With `eases`, it eases there from where the
// layer shows now, so a change during an ease turns on from where it is,
// rather than restart or queue. Without, it stops any ease.
void QLMSkinSetLayerValue(CALayer *layer, NSString *keyPath, id value, BOOL eases);

// A view with skin material, as the display, the OSD, and the panel are.
@interface QLMSkinLayerView : NSView <QLMSkinLayered>
- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@property (nonatomic, readonly) QLMSkinLayers *layers;
@end

NS_ASSUME_NONNULL_END
