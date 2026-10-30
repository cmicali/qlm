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

@end

typedef void (^QLMSnapshotHandler)(QLMSnapshot *snapshot);

// Owns the bus on one serial queue. It reads the adapter's identity and polls
// its status. It runs discovery, the session leases, the poll cycle, and
// volume. After a change it publishes an immutable snapshot once nothing is
// queued for the bus or in flight. Every method may be called from any thread.
@interface QLMSystem : NSObject

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter settings:(QLMSystemSettings *)settings;

@property (nonatomic, readonly) QLMSystemSettings *settings;
@property (atomic, readonly) QLMSnapshot *snapshot;  // the latest

// The handler gets the latest snapshot at once, then every one published.
- (void)setSnapshotHandler:(nullable QLMSnapshotHandler)handler queue:(dispatch_queue_t)queue;

- (void)start;
- (void)stop;

// Goes out at once, coalesced to one frame per volumeInterval, and again
// every cycle. Clamped to the ceiling in the builder.
- (void)setVolumeDecibels:(double)decibels;

// While dimmed, every volume frame is the volume less QLMDimDecibels. A
// change sends GLM's dim: the level twice, a round of 2B, and 3D. With no
// volume set, it sends nothing.
- (void)setDimmed:(BOOL)dimmed;

// Each sends two rounds of 2B to every leased monitor, restating each one's
// mute state. Mute-all re-sends the volume first.
- (void)setMuted:(BOOL)muted forMonitorWithHardwareID:(NSData *)hardwareID;
- (void)setAllMuted:(BOOL)muted;

// Broadcasts the power sequences. The monitors' power state comes back in
// their telemetry.
- (void)sleep;
- (void)wake;

// Ducks, wakes, sends each monitor its DSP block, and restores the volume
// and mute. Refused, with nothing sent, for a node with an unverified design
// rate or with no leased monitor. A group whose nodes are all off still
// ducks, wakes, and restores the volume, with no per-monitor frames. The
// completion runs on the main queue.
- (void)applyGroup:(QLMSetupGroup *)group completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
