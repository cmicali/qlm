#import "QLMMonitorList.h"

NSColor *QLMPresenceColor(QLMMonitorPresence presence) {
    switch (presence) {
    case QLMMonitorPresenceOnline: return NSColor.systemGreenColor;
    case QLMMonitorPresenceStandby: return NSColor.systemYellowColor;
    case QLMMonitorPresenceOffline: return NSColor.systemRedColor;
    case QLMMonitorPresenceIdentifying: break;
    }
    return NSColor.systemGrayColor;
}

NSString *QLMPresenceName(QLMMonitorPresence presence) {
    switch (presence) {
    case QLMMonitorPresenceOnline: return @"On";
    case QLMMonitorPresenceStandby: return @"Standby";
    case QLMMonitorPresenceOffline: return @"Offline";
    case QLMMonitorPresenceIdentifying: break;
    }
    return @"Identifying";
}

@interface QLMMonitorEntry ()
@property (nonatomic, readwrite) QLMMonitorState *state;
@property (nonatomic, readwrite) QLMMonitorPresence presence;
@property (nonatomic, readwrite) BOOL tracked;
@end

@implementation QLMMonitorEntry
@end

@implementation QLMMonitorList {
    NSMutableArray<NSData *> *_order;  // hardware IDs, first seen first
    NSMutableDictionary<NSData *, QLMMonitorState *> *_lastStates;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _order = [NSMutableArray array];
        _lastStates = [NSMutableDictionary dictionary];
        _entries = @[];
    }
    return self;
}

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot {
    NSMutableSet<NSData *> *tracked = [NSMutableSet setWithCapacity:snapshot.monitors.count];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if (_lastStates[monitor.hardwareID] == nil) {
            [_order addObject:monitor.hardwareID];
        }
        _lastStates[monitor.hardwareID] = monitor;
        [tracked addObject:monitor.hardwareID];
    }
    NSMutableArray<QLMMonitorEntry *> *entries = [NSMutableArray arrayWithCapacity:_order.count];
    for (NSData *hardwareID in _order) {
        QLMMonitorEntry *entry = [[QLMMonitorEntry alloc] init];
        entry.state = _lastStates[hardwareID];
        entry.tracked = [tracked containsObject:hardwareID];
        if (!entry.tracked || entry.state.missedPolls > 0) {
            entry.presence = QLMMonitorPresenceOffline;
        } else if (entry.state.status == QLMMonitorStatusOn) {
            entry.presence = QLMMonitorPresenceOnline;
        } else if (entry.state.status == QLMMonitorStatusStandby) {
            entry.presence = QLMMonitorPresenceStandby;
        } else {
            entry.presence = QLMMonitorPresenceIdentifying;
        }
        [entries addObject:entry];
    }
    _entries = entries;
}

@end
