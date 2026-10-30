#import <Foundation/Foundation.h>

#import "QLMDSPBlock.h"
#include "QLMFrame.h"
#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

// A leased monitor, as GLM's sequences see it.
@interface QLMApplyMonitor : NSObject

- (instancetype)initWithHardwareID:(NSData *)hardwareID session:(uint8_t)session;

@property (nonatomic, readonly) NSData *hardwareID;
@property (nonatomic, readonly) uint8_t session;
@property (nonatomic) BOOL on;     // its last telemetry says on
@property (nonatomic) BOOL muted;  // the user's mute

@end

// GLM's sequences, as frames: the address, then the payload. System sends
// them, and the dry run prints them. Every one reads only what it is given.
//
// A monitor is in the group if its node is on. One with no node counts as in
// it, as does every monitor while no group is active. Rounds of 2B go only
// to monitors that are on, in the group's device order, then any with no
// node, in lease order.
@interface QLMApplySequence : NSObject

// `monitors` in lease order. With no group, rounds run in lease order.
- (instancetype)initWithGroup:(nullable QLMSetupGroup *)group
                     monitors:(NSArray<QLMApplyMonitor *> *)monitors
                 adapterMuted:(BOOL)adapterMuted;

@property (nonatomic, readonly) NSArray<QLMApplyMonitor *> *monitors;

// In the group: its node is on, or it has none, or no group is active.
- (BOOL)isMember:(QLMApplyMonitor *)monitor;

// In the group: 2B 04, or 03 when muted. Outside: 2B 05 then 07, and 07
// alone in the first of two rounds.
- (NSArray<NSData *> *)stateOf:(QLMApplyMonitor *)monitor firstOfTwo:(BOOL)first;
- (NSArray<NSData *> *)rounds:(NSUInteger)count;
// The adapter's mute at 01, then two rounds.
- (NSArray<NSData *> *)muteState;

// GLM's group switch: the duck, the wake, the routing pass in node order, a
// round, the DSP pass in device order, the adapter's mute and two rounds,
// then the volume three times, a round, and broadcast 2D 00 and 3D 00 00.
// `blocks` holds a block for each node with a leased monitor, keyed by
// hardware ID.
- (NSArray<NSData *> *)switchWithBlocks:(NSDictionary<NSData *, QLMDSPBlock *> *)blocks volume:(QLMMessage)volume;

// Broadcast 2D 00 then 3D 00 00, the pair GLM sends after configuring
// monitors, after dim, and after a wake (docs/refused-frames.md).
+ (NSArray<NSData *> *)inputPair;

// GLM's apply to monitors newly leased, as at startup and wake: each one's
// block in turn, then a round to the others and 2D 00 and 3D 00 00. Each
// gets its state after its next poll, which System sends. Nothing, when no
// monitor has a block.
- (NSArray<NSData *> *)enumerationOf:(NSArray<QLMApplyMonitor *> *)fresh
                              blocks:(NSDictionary<NSData *, QLMDSPBlock *> *)blocks;

@end

// A record's message: its first byte is the address, the rest the payload.
QLMMessage QLMApplyMessage(NSData *record);

NS_ASSUME_NONNULL_END
