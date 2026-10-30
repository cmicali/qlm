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

// Every monitor seen since launch, in the order first seen. System drops a
// monitor that stops answering, and the list keeps it, offline. On the main
// queue.
@interface QLMMonitorList : NSObject

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot;

@property (nonatomic, readonly) NSArray<QLMMonitorEntry *> *entries;

@end

NS_ASSUME_NONNULL_END
