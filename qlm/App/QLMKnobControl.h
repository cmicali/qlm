#import <Cocoa/Cocoa.h>

#import "QLMSkinControls.h"

NS_ASSUME_NONNULL_BEGIN

// The knob, in the skin's knob element. Its doubleValue is the level in dB,
// from minValue to maxValue. A drag, the scroll wheel, and the arrow keys
// move it in GLM's 0.5 dB steps, and send the action only when the level
// changes. A click alone moves nothing.
@interface QLMKnobControl : QLMSkinControl
@property (nonatomic) double minValue;
@property (nonatomic) double maxValue;
// A turn by the user, to the nearest step in the range, as a drag's. It
// sends the action when the step changes.
- (void)moveTo:(double)decibels;
// A turn of `steps` of GLM's steps, as the arrow keys make, while enabled.
// NO where it moves nothing: disabled, or at an end of the range.
- (BOOL)canStepBy:(int)steps;
- (BOOL)stepBy:(int)steps;
@end

NS_ASSUME_NONNULL_END
