#import <Foundation/Foundation.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// The resize pass: each element's frame in a window at or above the skin's
// size. The extra room goes by each element's anchors, as springs and
// struts. Pure, so the hostless tests cover it.

// `size`, grown on each axis to at least `minimum`.
static inline CGSize QLMSizeAtLeast(CGSize size, CGSize minimum) {
    return CGSizeMake(MAX(size.width, minimum.width), MAX(size.height, minimum.height));
}

// A frame moved by `extra`, the room its container gained. Anchored to both
// edges of an axis, it stretches. To one, it keeps its distance to that
// edge. To neither, it keeps centered.
CGRect QLMSkinSpring(CGRect frame, QLMSkinAnchors anchors, CGSize extra);

// The cells of the skin's groups grid. The window shows at most six
// groups, as QLMShownGroupButtons gives.
NSUInteger QLMSkinGroupButtonCount(QLMSkin *skin);

// What a slot's font size is multiplied by in its element laid out at
// `size`: 1, or for a slot that scales, the smaller of the element's height
// and width over the skin's.
CGFloat QLMSkinSlotScale(QLMSkinElement *element, QLMSkinTextSlot *slot, CGSize size);

// A slot's frame in its element laid out at `size`.
CGRect QLMSkinSlotFrame(QLMSkinElement *element, QLMSkinTextSlot *slot, CGSize size);

@interface QLMSkinLayout : NSObject

// A size below the skin's is taken as the skin's.
- (instancetype)initWithSkin:(QLMSkin *)skin size:(CGSize)size NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) QLMSkin *skin;
@property (nonatomic, readonly) CGSize size;

// In the window.
- (CGRect)frameOfElement:(NSString *)name;
// In the element's laid-out frame.
- (CGRect)frameOfSlot:(NSString *)slot inElement:(NSString *)element;
- (CGFloat)scaleOfSlot:(NSString *)slot inElement:(NSString *)element;
// A grid element's cells, in the window, row by row, each the same size.
- (NSArray<NSValue *> *)cellsOfElement:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
