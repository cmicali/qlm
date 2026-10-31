#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// What a value with no reading shows.
extern NSString *const QLMEmDash;

// "−30.0 dB", with a true minus sign.
NSString *QLMDecibelsText(double decibels);

// "38 °C", or an em dash when absent.
NSString *QLMTemperatureText(NSInteger temperature);

// A raw meter reading as counts above the meter's floor, 80. A count is
// about 1 dB (docs/refused-frames.md). -1 when absent.
NSInteger QLMMeterCounts(NSInteger raw);

// "0.4 s ago" within a minute, then the time of day. An em dash for nil.
// On the main queue: it keeps one formatter.
NSString *QLMReplyAgeText(NSDate *_Nullable date);

// What the adapter's take-over does to the level, from the snapshot's
// hand-back: the knob against qlm's level, or why the level is unknown.
NSString *QLMTakeOverText(QLMSnapshot *snapshot);

// The same as a line for Settings, "Now: the knob reads ...". Nil before
// the adapter's status reads, and for no snapshot.
NSString *_Nullable QLMHandBackLine(QLMSnapshot *_Nullable snapshot);

// Whether a stop now may make the monitors louder: qlm holds the adapter,
// and the take-over is above qlm's level, or its level is unknown. While
// the adapter is refused or gone, qlm sent nothing, so a stop hands nothing
// back.
BOOL QLMStopMayRaiseLevel(QLMSnapshot *_Nullable snapshot);

// The banner's lines: the snapshot's adapterProblem, else its busProblem.
// The title is nil when there is none.
NSString *_Nullable QLMBusProblemTitle(QLMSnapshot *_Nullable snapshot);
NSString *QLMBusProblemDetail(QLMSnapshot *snapshot);

// System runs and tracks a monitor, so Mute, the power button, and the group
// picker take a click. The debug channel's verbs refuse by it too.
BOOL QLMSnapshotTracksMonitors(QLMSnapshot *_Nullable snapshot);

NS_ASSUME_NONNULL_END
