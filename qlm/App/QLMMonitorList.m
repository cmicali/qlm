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

NSString *QLMEntryStatusText(QLMMonitorEntry *entry) {
    if (entry.presence == QLMMonitorPresenceOffline && entry.tracked) {
        return [NSString stringWithFormat:@"Not answering (%lu)", (unsigned long)entry.state.missedPolls];
    }
    return QLMPresenceName(entry.presence);
}

@implementation QLMMonitorList {
    NSMutableArray<NSData *> *_order;  // hardware IDs, first seen first
    NSMutableDictionary<NSData *, QLMMonitorState *> *_lastStates;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _order = [NSMutableArray array];
        _lastStates = [NSMutableDictionary dictionary];
        [self forgetMonitors];
    }
    return self;
}

- (void)forgetMonitors {
    [_order removeAllObjects];
    [_lastStates removeAllObjects];
    _entries = @[];
    _dropped = @[];
}

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot {
    _snapshot = snapshot;
    NSMutableSet<NSData *> *tracked = [NSMutableSet setWithCapacity:snapshot.monitors.count];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if (_lastStates[monitor.hardwareID] == nil) {
            [_order addObject:monitor.hardwareID];
        }
        _lastStates[monitor.hardwareID] = monitor;
        [tracked addObject:monitor.hardwareID];
    }
    NSMutableArray<QLMMonitorState *> *dropped = [NSMutableArray array];
    for (QLMMonitorEntry *entry in _entries) {
        if (entry.tracked && ![tracked containsObject:entry.state.hardwareID]) {
            [dropped addObject:entry.state];
        }
    }
    _dropped = dropped;
    NSMutableArray<QLMMonitorEntry *> *entries = [NSMutableArray arrayWithCapacity:_order.count];
    for (NSData *hardwareID in _order) {
        QLMMonitorEntry *entry = [[QLMMonitorEntry alloc] init];
        entry.state = _lastStates[hardwareID];
        entry.tracked = [tracked containsObject:hardwareID];
        if (!entry.tracked || entry.state.offline) {
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
