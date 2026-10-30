#import <Foundation/Foundation.h>

#import "QLMAdapter.h"
#import "QLMSetup.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QLMSystemErrorDomain;

// Why System refused or failed a group apply. A refusal sends nothing.
typedef NS_ERROR_ENUM(QLMSystemErrorDomain, QLMSystemError) {
    QLMSystemErrorUnverifiedRate = 1,  // a node's filter design rate is unverified on the wire
    QLMSystemErrorUnknownMonitor,      // a node matches no leased monitor
    QLMSystemErrorBlocksFailed,        // the DSP blocks could not be built; see NSUnderlyingErrorKey
    QLMSystemErrorAlreadyApplying,
    QLMSystemErrorNotRunning,          // also given to an apply cut short by stop
    QLMSystemErrorNoVolume,            // no volume is set, so the restore has nothing to send
    QLMSystemErrorSendFailed,          // a frame failed or a monitor did not ack it
};

@interface QLMSystemSettings : NSObject <NSCopying>

// The user's ceiling. Every volume frame is capped at it. The default is low.
@property (nonatomic) double ceilingDecibels;           // -20
@property (nonatomic) NSTimeInterval cycleInterval;     // 0.57 s: probe, volume, a poll to each monitor
@property (nonatomic) NSTimeInterval volumeInterval;    // 0.05 s: at most one volume frame per interval
@property (nonatomic) NSUInteger missedPollsLimit;      // 4 polls unanswered, then the retry burst
@property (nonatomic) NSUInteger retryBurst;            // 4 polls to the dead address before re-discovery
// 0.107 s: a pair of 01 08 to the adapter, as GLM polls it. 0 polls it only
// at start.
@property (nonatomic) NSTimeInterval adapterPollInterval;
// YES: the cycle probes, leases, and polls monitors. NO talks to the adapter
// alone, and sends the volume only once one is set.
@property (nonatomic) BOOL discoversMonitors;
// The mute record to start from, as a snapshot gave it: the muted hardware
// IDs, and whether mute all is on. No reply reports a monitor's mute, so
// System's record is the truth, and its rounds restate it.
@property (nonatomic, copy) NSSet<NSData *> *mutedHardwareIDs;  // empty
@property (nonatomic) BOOL mutingAll;                           // NO
// TRAP: AGENTS.md's Safety rule refuses a group apply for any model whose
// filter design rate is unverified, such as the 8351B. Only qlmctl's
// supervised test sets this, behind --unverified-rate. The app never does.
@property (nonatomic) BOOL allowsUnverifiedRates;  // NO

@end

typedef void (^QLMSnapshotHandler)(QLMSnapshot *snapshot);

// Owns the bus on one serial queue. It reads the adapter's identity and polls
// its status. It runs discovery, the session leases, the poll cycle, and
// volume. After a change it publishes an immutable snapshot once nothing is
// queued for the bus or in flight. Every method may be called from any thread.
@interface QLMSystem : NSObject

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter settings:(QLMSystemSettings *)settings;

@property (atomic, readonly) QLMSystemSettings *settings;  // replaced whole when the ceiling changes
@property (atomic, readonly) QLMSnapshot *snapshot;  // the latest

// The handler gets the latest snapshot at once, then every one published.
- (void)setSnapshotHandler:(nullable QLMSnapshotHandler)handler queue:(dispatch_queue_t)queue;

- (void)start;
// Before it lets go, sends the knob's level when the knob is at or below the
// level System sends, so the adapter's take-over changes nothing. The
// snapshot's handBack says what it did. A start while that goes out runs
// once the stop is done.
- (void)stop;

// Goes out at once, coalesced to one frame per volumeInterval, again every
// cycle, and ahead of everything else when a monitor is leased. Clamped to
// the ceiling in the builder. Once one is set, a turn of the adapter's knob
// sets it too, as GLM lets it (QLMKnob). At start the knob sets nothing.
- (void)setVolumeDecibels:(double)decibels;

// Caps every volume frame after this. A volume already set goes out again at
// once, under the new ceiling.
- (void)setCeilingDecibels:(double)ceilingDecibels;

// While dimmed, every volume frame is the volume less QLMDimDecibels. A
// change sends GLM's dim sequence, or nothing while no volume is set.
- (void)setDimmed:(BOOL)dimmed;

// Each sends two rounds of 2B, restating the state of every monitor that is
// on: its mute in the active group, and GLM's 05 and 07 outside it. Mute all
// also re-sends the volume and sets the adapter's own mute, as GLM does. A
// mute holds by hardware ID until the user lifts it, across a lease that
// lapses, a stop and a start, and for a monitor that first appears while all
// are muted. A muted monitor leased again, or one that was not on, hears its
// state after its next poll that says on. No 2B System sends unmutes it.
- (void)setMuted:(BOOL)muted forMonitorWithHardwareID:(NSData *)hardwareID;
- (void)setAllMuted:(BOOL)muted;
// Adds to the record monitors already muted elsewhere, as in GLM, and sends
// nothing. The next rounds restate them as muted.
- (void)recordMutedHardwareIDs:(NSSet<NSData *> *)hardwareIDs;

// Broadcasts the power sequences, with GLM's spacing between the steps.
// Nothing else goes out between them. The wake ends with a level, as GLM's
// does: the volume once one is set, else the knob's position under the
// ceiling, else the bottom level. The monitors' power state comes back in
// their telemetry.
- (void)sleep;
- (void)wake;

// The first apply sends what GLM sends at launch: each leased monitor's
// block in turn, off nodes included. Each one after is GLM's group switch:
// the duck, the wake, the routing pass, the blocks of the nodes that are
// on, the mute state, and the restore. QLMApplySequence has both. The group
// stays active, across stop: a monitor leased later gets its block once the
// probe finds no more, as GLM's do at a wake. Refused, with nothing sent,
// for a node with a leased monitor whose block fails or whose design rate
// is unverified, for a node that is on with no leased monitor, and while no
// volume is set. The completion runs on the main queue.
- (void)applyGroup:(QLMSetupGroup *)group completion:(void (^)(NSError *_Nullable error))completion;
// GLM's group switch, even as the first apply. The rest is as applyGroup:.
- (void)switchToGroup:(QLMSetupGroup *)group completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
