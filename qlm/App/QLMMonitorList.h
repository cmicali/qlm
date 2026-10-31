#import <Cocoa/Cocoa.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QLMMonitorPresence) {
    QLMMonitorPresenceIdentifying = 0,  // leased, with no telemetry yet
    QLMMonitorPresenceOnline,
    QLMMonitorPresenceStandby,
    QLMMonitorPresenceOffline,          // offline by System's rule, or dropped by System
};

NSColor *QLMPresenceColor(QLMMonitorPresence presence);
NSString *QLMPresenceName(QLMMonitorPresence presence);

// One monitor the app has seen. Immutable.
@interface QLMMonitorEntry : NSObject

// The latest state a snapshot carried. For a dropped monitor, its last.
@property (nonatomic, readonly) QLMMonitorState *state;
@property (nonatomic, readonly) QLMMonitorPresence presence;
// System still tracks it, so it can take commands.
@property (nonatomic, readonly) BOOL tracked;

@end

// "Not answering (4)" for a tracked monitor System calls offline, else the
// presence's name.
NSString *QLMEntryStatusText(QLMMonitorEntry *entry);

// The latest snapshot, and every monitor seen on this bus. System drops a
// monitor that stops answering, and the list keeps it, offline. Entries
// only append, in the order first seen, until the list forgets them. On the
// main queue.
@interface QLMMonitorList : NSObject

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot;
// Forgets every monitor seen, for a System on another bus.
- (void)forgetMonitors;

@property (nonatomic, readonly, nullable) QLMSnapshot *snapshot;
@property (nonatomic, readonly) NSArray<QLMMonitorEntry *> *entries;
// The monitors System tracked in the snapshot before this one and dropped in
// this one, as last seen.
@property (nonatomic, readonly) NSArray<QLMMonitorState *> *dropped;

@end

NS_ASSUME_NONNULL_END
