#import <Cocoa/Cocoa.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QLMMonitorPresence) {
    QLMMonitorPresenceIdentifying = 0,  // leased, with no telemetry yet
    QLMMonitorPresenceOnline,
    QLMMonitorPresenceStandby,
    QLMMonitorPresenceOffline,          // missing polls, or dropped by System
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

// "Not answering (3)" for a tracked monitor that misses polls, else the
// presence's name.
NSString *QLMEntryStatusText(QLMMonitorEntry *entry);

// The latest snapshot, and every monitor seen since launch. System drops a
// monitor that stops answering, and the list keeps it, offline. Entries
// only append, in the order first seen. On the main queue.
@interface QLMMonitorList : NSObject

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot;

@property (nonatomic, readonly, nullable) QLMSnapshot *snapshot;
@property (nonatomic, readonly) NSArray<QLMMonitorEntry *> *entries;

@end

NS_ASSUME_NONNULL_END
