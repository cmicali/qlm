#import <Foundation/Foundation.h>

#import "QLMAdapter.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

@interface QLMSystemSettings : NSObject <NSCopying>

// The user's ceiling. Every volume frame is capped at it. The default is low.
@property (nonatomic) double ceilingDecibels;           // -20
@property (nonatomic) NSTimeInterval cycleInterval;     // 1.5 s: volume, keep-alive, polls, probe
@property (nonatomic) NSTimeInterval volumeInterval;    // 0.05 s: at most one volume frame per interval
@property (nonatomic) NSUInteger missedPollsLimit;      // 4 polls unanswered, then the retry burst
@property (nonatomic) NSUInteger retryBurst;            // 4 polls to the dead address before re-discovery

@end

typedef void (^QLMSnapshotHandler)(QLMSnapshot *snapshot);

// Owns the bus on one serial queue. It runs discovery, the session leases,
// the keep-alive and poll cycle, and volume, and it publishes an immutable
// snapshot after each change. Every method may be called from any thread.
@interface QLMSystem : NSObject

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter settings:(QLMSystemSettings *)settings;

@property (nonatomic, readonly) QLMSystemSettings *settings;
@property (atomic, readonly) QLMSnapshot *snapshot;  // the latest

- (void)setSnapshotHandler:(nullable QLMSnapshotHandler)handler queue:(dispatch_queue_t)queue;

- (void)start;
- (void)stop;

// Goes out at once, coalesced to one frame per volumeInterval, and again
// every cycle. Clamped to the ceiling in the builder.
- (void)setVolumeDecibels:(double)decibels;

@end

NS_ASSUME_NONNULL_END
