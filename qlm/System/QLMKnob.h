#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The knob's position, in tenths of a dB, at the nearest step, from
// QLMVolumeDecibelsMin to 0 dB. No tenth falls halfway between two steps.
double QLMKnobStep(NSInteger tenths);

// The knob moved from one reading to the other, by GLM's rule: more than a
// whole dB, 11 tenths or more. Jitter at rest never strays that far.
BOOL QLMKnobMoved(NSInteger fromTenths, NSInteger toTenths);

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

// The knob came out at `time`. The volume to go back to, or nil to leave
// `volume` alone: the lowest the volume was before any of the knob's follows
// of the last second, when that is lower. So every raise in that second is
// taken back, and no lowering. A follow from before it stands. Then it
// forgets where the knob rests, as reset does.
- (nullable NSNumber *)volumeAtUnplugAtTime:(NSTimeInterval)time volume:(nullable NSNumber *)volume;

// A level set since stands, so a pull of the knob takes back none of the
// follows before it.
- (void)forgetFollows;

// Forgets where the knob rests, and its follows: at start. Not on a
// reconnect: GLM follows a knob turned while the adapter was away.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
