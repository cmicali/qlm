#import <Cocoa/Cocoa.h>

#import "QLMSkinControls.h"

NS_ASSUME_NONNULL_BEGIN

// The knob, in the skin's knob element. Its doubleValue is the level in dB,
// from minValue to maxValue. It draws, in order, the shadow, the tick ring,
// a drawn knob's arc, the body, the pointer, and the focus ring. Only the
// pointer turns.
//
// A drag points the knob at the mouse, a scroll wheel moves it one step a
// tick, and the arrow keys one step. Each move snaps to GLM's 0.5 dB steps
// and sends the action at once. A level set in code is drawn as given,
// kept in the range.
@interface QLMKnobControl : QLMSkinControl
@property (nonatomic) double minValue;
@property (nonatomic) double maxValue;
@end

NS_ASSUME_NONNULL_END
