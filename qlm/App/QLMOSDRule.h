#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import "QLMPreferences.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// When the OSD shows, and for how long. Foundation only, so the tests cover
// it. On the main queue.
//
// It shows when it is enabled, the snapshot's volumeFromKnob is set, and
// its level differs from the snapshot before. So the slider, the window's
// knob, qlmctl, a ceiling, and a start or gap that lowered the level never
// show it: each clears the flag. A snapshot that changes no level never
// shows it either, whatever the flag. While it shows, a change to mute all
// or dim shows it again, so its subtitle never lies. The first snapshot
// only sets the level to compare with: a launch never shows it.
@interface QLMOSDRule : NSObject

// `now` gives seconds, never going back.
- (instancetype)initWithNow:(NSTimeInterval (^)(void))now NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// From the preferences. Disabling hides it.
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSTimeInterval seconds;

// Takes each snapshot, in order. YES when the OSD shows it now. Each show
// restarts the timer.
- (BOOL)showsSnapshot:(QLMSnapshot *)snapshot;
// Shows at once and restarts the timer, as a turn does.
- (void)show;
- (void)hide;

// Shown, and the timer not yet ended.
@property (nonatomic, readonly) BOOL showing;
// When the timer ends, on `now`'s clock.
@property (nonatomic, readonly) NSTimeInterval hidesAt;

@end

// The active group's name, else "Monitors".
NSString *QLMOSDTitle(QLMSnapshot *snapshot);
// "MUTED" while every monitor is muted, else "DIM" while dimmed, else
// "qlm · Output level".
NSString *QLMOSDSubtitle(QLMSnapshot *snapshot);
// The level's place in the slider's range, 0 at the bottom, 1 at the
// ceiling.
double QLMOSDFraction(double decibels, double lowestDecibels, double ceilingDecibels);
// The OSD's frame on a screen whose visible frame is `visible`, 24 points
// in from its edges. Screen coordinates, so y grows upward.
CGRect QLMOSDFrame(CGRect visible, CGSize size, QLMOSDPlacement placement);

NS_ASSUME_NONNULL_END
