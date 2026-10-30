#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Turns the knob's readings into volume, as GLM does. Touched only on
// System's queue.
//
// - A reading more than a whole dB from the last one the volume followed
//   moves the volume to the knob's nearest step, however slowly the knob
//   got there.
// - Then, for 2.54 s, the volume follows every change in the reading. Each
//   move of more than a whole dB starts that time again, so the volume
//   follows a turn to its end.
// - Outside that time, a change of a whole dB or less moves nothing, so
//   jitter at rest moves nothing.
// - The first reading is where the knob rests, so the volume stays put at
//   connect. GLM follows its first change of any size after it opens; qlm
//   waits for more than a whole dB, so jitter at connect moves nothing.
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
