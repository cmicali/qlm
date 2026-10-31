#import <Foundation/Foundation.h>

#include "QLMFrame.h"
#import "QLMSnapshot.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

// A stated ceiling above this takes --allow-high-ceiling. Unstated, the
// ceiling is this. GLMProtocol caps every volume frame at the ceiling.
extern const double QLMCeilingLimit;

// The most --adapter-poll takes, in seconds.
extern const NSTimeInterval QLMAdapterPollLimit;

// info, discover, and poll send no control, but each refuses an argument
// it doesn't know, as a control does. So a misplaced option, such as
// volume's --adapter-poll, can't run with the defaults. Each flag maps to
// itself, and each option to its value. Nil, with the reason in `problem`,
// for an unknown or repeated argument, an option with no value, --seconds
// that is not a number of seconds, or --fake with --replay.
NSDictionary<NSString *, NSString *> *_Nullable QLMQueryArguments(NSString *command, NSArray<NSString *> *arguments,
                                                                  NSString *_Nullable *_Nonnull problem);

// compare-apply's: a setup file and a capture's reports.txt, then --group,
// --from, and --to, each at most once. The files map from "setup" and
// "reports". Nil, with the reason in `problem`, for anything else, or a
// window that is not from before to, in seconds from 0.
NSDictionary<NSString *, NSString *> *_Nullable QLMCompareArguments(NSArray<NSString *> *arguments, NSString *_Nullable *_Nonnull problem);

typedef NS_ENUM(NSInteger, QLMControlCommand) {
    QLMControlCommandVolume,
    QLMControlCommandMute,
    QLMControlCommandDim,
    QLMControlCommandSleep,
    QLMControlCommandWake,
    // Its file and group come before these options, and are not parsed here.
    QLMControlCommandApplyGroup,
};

// A control command's arguments, read and checked before any bus opens.
@interface QLMControlOptions : NSObject

// Nil, with the reason in `problem`, for an unknown or repeated argument, a
// bad value, or a gate not met. `arguments` follow the command's name.
+ (nullable instancetype)optionsForCommand:(QLMControlCommand)command
                                 arguments:(NSArray<NSString *> *)arguments
                                   problem:(NSString *_Nullable *_Nonnull)problem;

@property (nonatomic, readonly) BOOL fake;
@property (nonatomic, readonly, nullable) NSString *replayPath;
@property (nonatomic, readonly) BOOL overUSB;  // neither --fake nor --replay
@property (nonatomic, readonly) BOOL dryRun;
@property (nonatomic, readonly) BOOL on;  // mute and dim
// The volume's level, or dim's --volume. Nil for dim without it.
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;
@property (nonatomic, readonly, nullable) NSString *serial;  // mute's --serial
// --muted, a comma list: each names by text its serial contains a monitor
// already muted elsewhere, as in GLM. Empty when not given.
@property (nonatomic, readonly) NSArray<NSString *> *mutedSerials;
@property (nonatomic, readonly) BOOL launch;  // apply-group's --launch
// apply-group's --unverified-rate: the supervised test of a group with a
// model whose filter design rate is unverified, the 8351B. It sets the
// settings' allowsUnverifiedRates.
@property (nonatomic, readonly) BOOL unverifiedRate;
// The stated --ceiling, or QLMCeilingLimit.
@property (nonatomic, readonly) double ceilingDecibels;
@property (nonatomic, readonly) NSTimeInterval seconds;  // --seconds, or 0
// volume's --adapter-poll: one 01 08 every this many seconds, in place of
// GLM's pair every 0.107 s. 0 polls only at start. Nil when not given.
@property (nonatomic, readonly, nullable) NSNumber *adapterPollSeconds;
// System's settings, with the ceiling and the adapter's polling.
@property (nonatomic, readonly) QLMSystemSettings *settings;
// How the settings poll the adapter, for qlmctl to print at start.
@property (nonatomic, readonly) NSString *adapterPollText;

@end

typedef BOOL (^QLMSnapshotTest)(QLMSnapshot *snapshot);

// Puts a snapshot handler in place, then runs the action, so the handler
// sees every snapshot the action causes. Returns the first snapshot that
// passes, or nil after the timeout. An action that returns NO sent nothing,
// and the wait ends at once with nil.
// TRAP: an action run before the handler is in place can finish first. The
// handler then sees only the end state, as its replay, which a test made by
// QLMAfterReplay skips, and the wait runs out.
QLMSnapshot *_Nullable QLMWaitForSnapshot(QLMSystem *system, NSTimeInterval timeout, BOOL (^_Nullable action)(void),
                                          QLMSnapshotTest test);

// TRAP: the snapshot replayed when a handler is put in place predates the
// action, and a no-op can leave it already passing. This test skips it, so
// only a snapshot published after the action counts.
QLMSnapshotTest QLMAfterReplay(QLMSnapshotTest test);

// Runs a command on System, given what discovery found. Returns an exit
// code; 0 means the command went to System.
typedef int (^QLMControlAction)(QLMSystem *system, QLMSnapshot *discovered);

// A control, after discovery. First it records the monitors `mutedSerials`
// names as muted, sending nothing, and waits for a snapshot that shows the
// record. qlm cannot read a mute. Then it runs the action, and returns the
// first snapshot after it that passes `effect`, or nil after the timeout.
// `status` gets the action's exit code, or EX_DATAERR, with nothing
// recorded, when a text names no single monitor, or EX_TEMPFAIL when the
// record did not show.
QLMSnapshot *_Nullable QLMWaitForEffect(QLMSystem *system, QLMSnapshot *discovered, NSArray<NSString *> *mutedSerials,
                                        QLMControlAction action, QLMSnapshotTest effect, NSTimeInterval timeout, int *status);

// The dry run. It runs the control as QLMWaitForEffect does, on a fake bus
// that mirrors the monitors in `discovered`, never on the bus that found
// them. It returns every frame sent there but discovery's, addressed as
// `discovered` has each monitor. `status` gets QLMWaitForEffect's, or
// EX_TEMPFAIL when `effect` did not show and the list may be short, or
// EX_SOFTWARE when the mirror did not find every monitor. Nil when the
// action did not run.
NSArray<NSData *> *_Nullable QLMDryRunRecords(QLMSnapshot *discovered, QLMSystemSettings *settings, NSArray<NSString *> *mutedSerials,
                                              QLMControlAction action, QLMSnapshotTest effect, int *status);

// The volume. With fewer adapter polls, the adapter may take over during
// the run, at the knob's level, which the ceiling does not bound. So then
// it refuses, with EX_DATAERR and nothing sent, unless the knob reads at or
// below the level that goes out, by System's hand-back rule.
QLMControlAction QLMVolumeAction(double decibels, BOOL fewerAdapterPolls);

// Dim, as GLM sends it. System sends GLM's dim only when dim changes with a
// volume set, so this sets the state dim changes from, then the volume,
// which goes out at that state, then dim.
QLMControlAction QLMDimAction(BOOL on, NSNumber *_Nullable volumeDecibels);

// The wake. A volume, when given, is set first, so the wake ends with it, as
// GLM's does.
QLMControlAction QLMWakeAction(NSNumber *_Nullable volumeDecibels);

// The hardware ID of the one monitor in `discovered` whose serial contains
// each text. Nil, with the reason, when a text matches none or several.
NSSet<NSData *> *_Nullable QLMHardwareIDsForSerials(NSArray<NSString *> *serials, QLMSnapshot *discovered,
                                                   NSString *_Nullable *_Nonnull problem);

// What System's stop did about the adapter's take-over, for qlmctl to print
// at exit. It is a warning but for QLMHandBackKnobLevel.
NSString *QLMHandBackText(QLMHandBack *handBack);

// The word a volume frame carries. The frame is rebuilt from it, so only a
// true volume frame passes.
BOOL QLMVolumeFrameWord(const QLMMessage *message, uint32_t *word);

NS_ASSUME_NONNULL_END
