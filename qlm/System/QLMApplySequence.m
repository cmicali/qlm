#import "QLMApplySequence.h"

#import "QLMAdapter.h"
#include "QLMCommands.h"

@implementation QLMApplyMonitor

- (instancetype)initWithHardwareID:(NSData *)hardwareID session:(uint8_t)session {
    self = [super init];
    if (self) {
        _hardwareID = [hardwareID copy];
        _session = session;
    }
    return self;
}

@end

QLMMessage QLMApplyMessage(NSData *record) {
    const uint8_t *bytes = record.bytes;
    return QLMMessageMake(bytes[0], bytes + 1, record.length - 1);
}

static NSData *QLMRecord(QLMMessage message) {
    return QLMAdapterRecord(&message);
}

static NSData *QLMRecordTo(uint8_t session, NSData *payload) {
    return QLMRecord(QLMMessageMake(session, payload.bytes, payload.length));
}

@implementation QLMApplySequence {
    QLMSetupGroup *_group;
    BOOL _adapterMuted;
    NSDictionary<NSData *, QLMApplyMonitor *> *_byHardwareID;
    // The monitors in device order, then those with no node, in lease order.
    NSArray<QLMApplyMonitor *> *_inDeviceOrder;
}

- (instancetype)initWithGroup:(QLMSetupGroup *)group monitors:(NSArray<QLMApplyMonitor *> *)monitors adapterMuted:(BOOL)adapterMuted {
    self = [super init];
    if (self) {
        _group = group;
        _monitors = [monitors copy];
        _adapterMuted = adapterMuted;
        NSMutableDictionary<NSData *, QLMApplyMonitor *> *byHardwareID = [NSMutableDictionary dictionary];
        for (QLMApplyMonitor *monitor in _monitors.reverseObjectEnumerator) {
            byHardwareID[monitor.hardwareID] = monitor;
        }
        _byHardwareID = byHardwareID;
        NSMutableOrderedSet<QLMApplyMonitor *> *ordered = [NSMutableOrderedSet orderedSet];
        for (QLMSetupNode *node in group.nodesInDeviceOrder) {
            QLMApplyMonitor *monitor = [self monitorFor:node];
            if (monitor != nil) {
                [ordered addObject:monitor];
            }
        }
        [ordered addObjectsFromArray:_monitors];
        _inDeviceOrder = ordered.array;
    }
    return self;
}

- (nullable QLMApplyMonitor *)monitorFor:(QLMSetupNode *)node {
    return node.hardwareID != nil ? _byHardwareID[node.hardwareID] : nil;
}

- (BOOL)isMember:(QLMApplyMonitor *)monitor {
    QLMSetupNode *node = [_group nodeWithHardwareID:monitor.hardwareID];
    return node == nil || node.on;
}

// captures/knob-sweep, 19.135 s: in the group 04, and outside 07 in the
// first round and 05 then 07 in the second.
- (NSArray<NSData *> *)stateOf:(QLMApplyMonitor *)monitor firstOfTwo:(BOOL)first {
    if ([self isMember:monitor]) {
        uint8_t value = monitor.muted ? QLMMuteValueMuted : QLMMuteValueUnmuted;
        return @[QLMRecord(QLMCommandMute(monitor.session, value))];
    }
    NSData *outside = QLMRecord(QLMCommandMute(monitor.session, QLMMuteValueOutside));
    if (first) {
        return @[outside];
    }
    return @[QLMRecord(QLMCommandMute(monitor.session, QLMMuteValueOutsideLead)), outside];
}

- (NSArray<NSData *> *)roundFirstOfTwo:(BOOL)first excluding:(NSArray<QLMApplyMonitor *> *)excluded {
    NSArray<NSNumber *> *excludedSessions = [excluded valueForKey:@"session"];
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    for (QLMApplyMonitor *monitor in _inDeviceOrder) {
        if (monitor.on && ![excludedSessions containsObject:@(monitor.session)]) {
            [frames addObjectsFromArray:[self stateOf:monitor firstOfTwo:first]];
        }
    }
    return frames;
}

- (NSArray<NSData *> *)rounds:(NSUInteger)count {
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    for (NSUInteger round = 0; round < count; round++) {
        [frames addObjectsFromArray:[self roundFirstOfTwo:count == 2 && round == 0 excluding:@[]]];
    }
    return frames;
}

// captures/mute-dim, 46.19 s.
- (NSArray<NSData *> *)muteState {
    uint8_t value = _adapterMuted ? QLMMuteValueAdapterMuted : QLMMuteValueAdapterUnmuted;
    NSMutableArray<NSData *> *frames = [NSMutableArray arrayWithObject:QLMRecord(QLMCommandMute(QLMAddressAdapter, value))];
    [frames addObjectsFromArray:[self rounds:2]];
    return frames;
}

// The block, from prepare on. A two-way gets a keep-alive right after
// prepare (captures/startup-idle, 8.540 s, and
// group-switch-main-2x2-main-4x2, 10.947 s). The 8351B and the subwoofers
// do not.
- (void)addBlock:(QLMDSPBlock *)block to:(QLMApplyMonitor *)monitor into:(NSMutableArray<NSData *> *)frames {
    BOOL twoWay = block.node.nodeClass == QLMSetupNodeClassTwoWay;
    [block.payloads enumerateObjectsUsingBlock:^(NSData *payload, NSUInteger index, BOOL *stop) {
        [frames addObject:QLMRecordTo(monitor.session, payload)];
        if (twoWay && index == 0) {
            [frames addObject:QLMRecord(QLMCommandKeepAlive())];
        }
    }];
}

// The pair GLM sends after configuring monitors (docs/refused-frames.md).
- (void)addPairInto:(NSMutableArray<NSData *> *)frames {
    [frames addObject:QLMRecord(QLMCommandInputPreamble())];
    [frames addObject:QLMRecord(QLMCommandInputSync(QLMAddressBroadcast))];
}

// captures/group-switch-main-4x2-main-2x1, 12.359 to 13.476 s. GLM also
// sends each monitor 05 04, the generator stop, before its first 2B in the
// routing pass; 05 is never-send, so qlm skips it.
- (NSArray<NSData *> *)switchWithBlocks:(NSDictionary<NSData *, QLMDSPBlock *> *)blocks volume:(QLMMessage)volume {
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    [frames addObject:QLMRecord(QLMCommandVolumeWord(QLMVolumeWordMin, QLMVolumeWordMax))];
    [frames addObject:QLMRecord(QLMCommandDuck())];
    [frames addObject:QLMRecord(QLMCommandPower(QLMPowerStepWakeFirst))];
    [frames addObject:QLMRecord(QLMCommandPower(QLMPowerStepWakeFirst))];

    // A monitor in the group wakes; one outside it is told to prepare for
    // standby. One in standby gets no 2B.
    for (QLMSetupNode *node in _group.nodes) {
        QLMApplyMonitor *monitor = [self monitorFor:node];
        QLMDSPBlock *block = monitor != nil ? blocks[monitor.hardwareID] : nil;
        if (block == nil) {
            continue;
        }
        if (node.on) {
            [frames addObject:QLMRecord(QLMCommandMonitorPower(monitor.session, QLMPowerStepWakeSecond))];
            [frames addObject:QLMRecord(QLMCommandMonitorPower(monitor.session, QLMPowerStepWakeSecond))];
        } else {
            [frames addObject:QLMRecord(QLMCommandMonitorPower(monitor.session, QLMPowerStepStandbyPrepare))];
        }
        if (node.nodeClass == QLMSetupNodeClassSubwoofer) {
            [frames addObject:QLMRecordTo(monitor.session, block.crossoverPayload)];
        }
        NSArray<NSData *> *state = monitor.on ? [self stateOf:monitor firstOfTwo:NO] : @[];
        [frames addObjectsFromArray:state];
        for (NSData *routing in block.routingPayloads) {
            [frames addObject:QLMRecordTo(monitor.session, routing)];
        }
        [frames addObjectsFromArray:state];
    }
    [frames addObjectsFromArray:[self rounds:1]];

    // A keep-alive for every device, and a block for each one on.
    for (QLMSetupNode *node in _group.nodesInDeviceOrder) {
        [frames addObject:QLMRecord(QLMCommandKeepAlive())];
        QLMApplyMonitor *monitor = [self monitorFor:node];
        QLMDSPBlock *block = monitor != nil ? blocks[monitor.hardwareID] : nil;
        if (node.on && block != nil) {
            [self addBlock:block to:monitor into:frames];
        }
    }

    [frames addObjectsFromArray:[self muteState]];
    for (int i = 0; i < 3; i++) {
        [frames addObject:QLMRecord(volume)];
    }
    [frames addObjectsFromArray:[self rounds:1]];
    [self addPairInto:frames];
    return frames;
}

// captures/startup-idle, 8.534 to 9.302 s. GLM also sends 05 04 before
// each prepare, which qlm skips.
- (NSArray<NSData *> *)enumerationOf:(NSArray<QLMApplyMonitor *> *)fresh blocks:(NSDictionary<NSData *, QLMDSPBlock *> *)blocks {
    NSMutableArray<NSData *> *frames = [NSMutableArray array];
    for (QLMApplyMonitor *monitor in fresh) {
        QLMDSPBlock *block = blocks[monitor.hardwareID];
        if (block == nil) {
            continue;
        }
        [frames addObject:QLMRecord(QLMCommandKeepAlive())];
        if (block.node.nodeClass == QLMSetupNodeClassSubwoofer) {
            [frames addObject:QLMRecordTo(monitor.session, block.crossoverPayload)];
        }
        [self addBlock:block to:monitor into:frames];
        [frames addObject:QLMRecord(QLMCommandSystemInfo(monitor.session))];
        [frames addObject:QLMRecord(QLMCommandSerialNumber(monitor.session))];
    }
    if (frames.count == 0) {
        return frames;
    }
    [frames addObjectsFromArray:[self roundFirstOfTwo:NO excluding:fresh]];
    [self addPairInto:frames];
    return frames;
}

@end
