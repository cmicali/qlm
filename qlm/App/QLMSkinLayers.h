#import <Cocoa/Cocoa.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMSkinLayers;

// A piece of a view's material: an image in a frame of the view, which its
// layer stretches through the image's centre, as cap insets do.
@interface QLMSkinMaterial : NSObject

// The style's material for `state` in `frame`. An image style's is its
// file, decoded once. A drawn style's is drawn once per size, state, scale,
// and place on the pixels, and kept on the skin. A clear overlay lays
// nothing over it.
+ (nullable instancetype)materialOfStyle:(QLMSkinStyle *)style
                                    skin:(QLMSkin *)skin
                                   state:(QLMSkinState)state
                                   frame:(NSRect)frame
                                  circle:(BOOL)circle
                                 overlay:(QLMSkinColor)overlay
                                  layers:(QLMSkinLayers *)layers;

// An image made at the layers' scale to fill `frame`.
+ (instancetype)materialOfImage:(CGImageRef)image frame:(NSRect)frame layers:(QLMSkinLayers *)layers;

- (instancetype)init NS_UNAVAILABLE;

@end

// A view whose skin material is layer contents.
@protocol QLMSkinLayered <NSObject>
// The material for the view's state, bottom first.
- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers;
// What the view draws over its material, in its flipped bounds.
- (void)drawSkinContent:(NSRect)dirtyRect;
@end

// A view's material as its layer's contents, beneath the content it draws,
// so a change of its text composites the material rather than drawing it
// again. On the screen, an image drawn in drawRect: costs 50 to 100 times
// its draw offscreen, most of all a stretched one.
//
// The view's layer holds one sublayer per material, then one for the
// drawn content on top. The view has no subviews. It returns YES from
// wantsUpdateLayer, and calls updateLayer, drawRect:, and viewDidMove here
// from its own. Each setNeedsDisplay of the view sets the material and
// draws the content again.
@interface QLMSkinLayers : NSObject <CALayerDelegate>

- (instancetype)initWithView:(NSView<QLMSkinLayered> *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The window's backing scale, or the view's layer's outside a window.
@property (nonatomic, readonly) CGFloat scale;
// How far past the view's bounds its content draws, as a focus ring does.
@property (nonatomic) CGFloat contentOutset;
// `rect`, grown to the window's pixels, in the view.
- (NSRect)pixelRect:(NSRect)rect;

- (void)updateLayer;
// The material, then the content, drawn, for whatever draws the view
// rather than composite its layers, as a cached display or a print does.
- (void)drawRect:(NSRect)dirtyRect;
// Draws only part of the content again, and sets no material.
- (void)setNeedsDisplayInRect:(NSRect)rect;
// From the view's setFrameOrigin:. A move off the pixels the content was
// drawn on draws it again.
- (void)viewDidMove;

@end

// A view with skin material, as the display, the OSD, and the panel are.
// Subclasses implement QLMSkinLayered.
@interface QLMSkinLayerView : NSView <QLMSkinLayered>
- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@property (nonatomic, readonly) QLMSkinLayers *layers;
@end

NS_ASSUME_NONNULL_END
