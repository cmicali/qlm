#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

@class QLMSetup;

NS_ASSUME_NONNULL_BEGIN

// What a value with no reading shows.
extern NSString *const QLMEmDash;

// "−30.0", with a true minus sign and `decimals` places. A level that
// rounds to zero reads 0, never −0.
NSString *QLMDecibelsNumberText(double decibels, int decimals);

// "−30.0 dB": the number to one place, and the unit.
NSString *QLMDecibelsText(double decibels);

// After the user moves a level, by the popover's slider or the window's
// knob, snapshots leave it alone this long, so one from before the move
// cannot pull it back mid-drag.
extern const NSTimeInterval QLMLevelHoldInterval;

// Whether the level still holds at `now`, after a move at `movedAt`, both in
// seconds of system uptime. 0 is never moved.
BOOL QLMLevelHolds(NSTimeInterval movedAt, NSTimeInterval now);

// The ceiling a UI shows. With a volume set, the snapshot is a published
// one, so its ceiling is the one System caps at. Before that, the
// preferences say it.
double QLMShownCeiling(QLMSnapshot *_Nullable snapshot, double preferredCeiling);

// The active group's name, else "Monitors".
NSString *QLMGroupNameText(QLMSnapshot *snapshot);

// "MUTED" while every monitor is muted, else "DIM" while dimmed, else nil.
NSString *_Nullable QLMOutputStateText(QLMSnapshot *snapshot);

// Why a level typed for the ceiling, or the range's bottom, is refused, or
// nil. 0 dB is the monitors' full level, so a level above it is refused, not
// clamped: a clamp would make 35, typed for −35, the loudest ceiling. It
// refuses what the preferences refuse, NaN too.
NSString *_Nullable QLMTypedLevelRefusal(double decibels);

// Settings' level fields: one decimal, with a true minus sign. It refuses an
// empty field, which would read as 0 dB, and what QLMTypedLevelRefusal
// refuses, with the reason as its error.
@interface QLMDecibelsFormatter : NSNumberFormatter
@end

// What a person calls the monitor: its name in the setup file, else its
// serial. Nil with neither.
NSString *_Nullable QLMMonitorLabel(QLMMonitorState *monitor, QLMSetup *_Nullable setup);

// "38 °C", or an em dash when absent.
NSString *QLMTemperatureText(NSInteger temperature);

// A raw output meter reading as counts above the meter's floor, 80. A
// count is about 1 dB (docs/telemetry.md: The meters). -1 when absent.
NSInteger QLMMeterCounts(NSInteger raw);

// An output meter's counts from its floor, 80, to the byte's top, FF. With
// music, the outputs rose about 100 counts over the floor, to 246 at most
// (captures/qlm-poll-meters, captures/qlm-control-all).
extern const NSInteger QLMOutputMeterSpan;

typedef NS_ENUM(NSInteger, QLMInputSignal) {
    QLMInputSignalAbsent,  // not in the last telemetry
    QLMInputSignalNone,
    QLMInputSignalPresent,
};

// The input meter's raw reading at or above this is a signal. With nothing
// playing, every model's input rested at 161 or below. With music, it read
// 199 or more, but for fades, and 252 on a digital input
// (captures/qlm-poll-meters, docs/telemetry.md: The meters).
extern const NSInteger QLMInputSignalThreshold;

// Whether the input meter's raw reading is a signal.
QLMInputSignal QLMInputSignalOf(NSInteger raw);

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

// Whether a stop's mute all can reach the monitors: the bus takes frames.
// An adapter that stopped answering or taking reports takes none.
BOOL QLMStopCanMute(QLMSnapshot *_Nullable snapshot);

// What System's stop did to the level, from its snapshot once stopped.
NSString *QLMStopText(QLMSnapshot *_Nullable stopped);

// What a quit does before qlm lets go.
typedef NS_ENUM(NSInteger, QLMQuitStep) {
    QLMQuitStepStop = 0,   // the take-over is no louder
    QLMQuitStepAsk,        // the user's own quit asks first
    QLMQuitStepMuteFirst,  // a logout, restart, or shutdown mutes every monitor
};

// `reason` is the quit Apple event's kAEQuitReason, or 0 with none, as at
// Cmd-Q and the popover's Quit. A logout, restart, or shutdown can't wait
// on an alert, so where the user's quit asks, it stops with System's
// stopMutingIfLouderWithCompletion:.
QLMQuitStep QLMQuitStepFor(BOOL stopMayRaiseLevel, OSType reason);

// The banner's lines: the snapshot's adapterProblem, else its busProblem.
// The title is nil when there is none.
NSString *_Nullable QLMBusProblemTitle(QLMSnapshot *_Nullable snapshot);
NSString *QLMBusProblemDetail(QLMSnapshot *snapshot);

// System runs and tracks a monitor, so Mute, the power button, and the group
// picker take a click. The debug channel's verbs refuse by it too.
BOOL QLMSnapshotTracksMonitors(QLMSnapshot *_Nullable snapshot);

// The monitor answers and is on: not offline, and not in standby.
BOOL QLMMonitorIsOnline(QLMMonitorState *monitor);

NS_ASSUME_NONNULL_END
