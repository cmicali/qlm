#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Turns the knob's readings into volume, by GLM's rule (docs/protocol.md,
// "Volume and the knob"). A reading more than a whole dB from the last one
// the volume followed moves the volume to the knob's nearest step, and for
// 2.54 s after each such move, every change does. The first reading is
// where the knob rests. Touched only on System's queue.
@interface QLMKnob : NSObject

// The volume for this reading, in dB at the nearest step, or nil to leave
// the volume alone. `tenths` is the knob's position from the adapter's
// status. `time` is in seconds, on a clock that never steps back. `volume`
// is the volume now. With none set, the knob sets none.
- (nullable NSNumber *)volumeForReading:(NSInteger)tenths atTime:(NSTimeInterval)time volume:(nullable NSNumber *)volume;

// Forgets where the knob rests: at start, and when the knob comes out. Not
// on a reconnect: GLM follows a knob turned while the adapter was away.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
