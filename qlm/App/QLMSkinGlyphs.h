#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMSkinLayers;

// A slot's one line of text as a layer per glyph, for a number that
// changes with each step of the level. Each layer's contents is the
// glyph's image, drawn once per skin, font, size, color, overlay, scale,
// and place on the pixels, and kept by QLMSkinImages. So a new text sets
// layers' contents and frames, and rasterizes nothing once its glyphs have
// shown. It lays the glyphs out as QLMSkinDrawSlot draws the text: its
// kerning, its alignment, and its cut with an ellipsis. Dimmed, each glyph
// takes the overlay in its own shape, as QLMSkinDrawDimmed lays it.
@interface QLMSkinGlyphLine : NSObject

- (instancetype)initWithLayers:(QLMSkinLayers *)layers NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// One of its view's moving layers. It spans the view's layer.
@property (nonatomic, readonly) CALayer *layer;

// Lays `text` out in `view`, at the slot's frame and font scale, over
// layers it reuses. A clear overlay lays none. A call that changes nothing
// since the last does nothing.
- (void)showText:(nullable NSString *)text
            slot:(QLMSkinTextSlot *)slot
           frame:(NSRect)frame
       fontScale:(CGFloat)fontScale
      monoDigits:(BOOL)monoDigits
         overlay:(QLMSkinColor)overlay
            skin:(QLMSkin *)skin
          inView:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
