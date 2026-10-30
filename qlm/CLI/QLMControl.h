#import <Foundation/Foundation.h>

#include "QLMFrame.h"
#import "QLMSnapshot.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

// A stated ceiling above this takes --allow-high-ceiling. Unstated, the
// ceiling is this. GLMProtocol caps every volume frame at the ceiling.
extern const double QLMCeilingLimit;

typedef NS_ENUM(NSInteger, QLMControlCommand) {
    QLMControlCommandVolume,
    QLMControlCommandMute,
    QLMControlCommandDim,
    QLMControlCommandSleep,
    QLMControlCommandWake,
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
// The stated --ceiling, or QLMCeilingLimit.
@property (nonatomic, readonly) double ceilingDecibels;
@property (nonatomic, readonly) NSTimeInterval seconds;  // --seconds, or 0
// System's settings, with the ceiling.
@property (nonatomic, readonly) QLMSystemSettings *settings;

@end

typedef BOOL (^QLMSnapshotTest)(QLMSnapshot *snapshot);

// The first snapshot that passes, or nil after the timeout.
QLMSnapshot *_Nullable QLMWaitForSnapshot(QLMSystem *system, NSTimeInterval timeout, QLMSnapshotTest test);

// TRAP: the snapshot replayed when a handler is installed may predate an
// action just taken, and a no-op can leave it already passing. This test
// skips it, so only a snapshot published after the action counts.
QLMSnapshotTest QLMAfterReplay(QLMSnapshotTest test);

// Runs a command on System, given what discovery found. Returns an exit
// code; 0 means the command went to System.
typedef int (^QLMControlAction)(QLMSystem *system, QLMSnapshot *discovered);

// The dry run. It runs the action on a fake bus that mirrors the monitors in
// `discovered`, never on the bus that found them, and returns every frame
// the action sent there but discovery's, addressed as `discovered` has each
// monitor. `status` gets the action's exit code, EX_TEMPFAIL when `effect`
// did not show and the list may be short, or EX_SOFTWARE when the mirror did
// not find every monitor. Nil when the action did not run.
NSArray<NSData *> *_Nullable QLMDryRunRecords(QLMSnapshot *discovered, QLMSystemSettings *settings, QLMControlAction action,
                                              QLMSnapshotTest effect, int *status);

// The wake. A volume, when given, is set first, so the wake ends with it, as
// GLM's does.
QLMControlAction QLMWakeAction(NSNumber *_Nullable volumeDecibels);

// The word a volume frame carries. The frame is rebuilt from it, so only a
// true volume frame passes.
BOOL QLMVolumeFrameWord(const QLMMessage *message, uint32_t *word);

NS_ASSUME_NONNULL_END
