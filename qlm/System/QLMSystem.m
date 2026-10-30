#import "QLMSystem.h"

#include "QLMCommands.h"
#include "QLMReplies.h"
#import "QLMDSPBlock.h"
#import "QLMSnapshotInternal.h"

NSErrorDomain const QLMSystemErrorDomain = @"com.commonwealthrecordings.qlm.system";

static NSError *QLMSystemErrorMake(QLMSystemError code, NSString *description, NSError *_Nullable underlying) {
    NSMutableDictionary<NSErrorUserInfoKey, id> *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = description;
    if (underlying != nil) {
        info[NSUnderlyingErrorKey] = underlying;
    }
    return [NSError errorWithDomain:QLMSystemErrorDomain code:code userInfo:info];
}

@implementation QLMSystemSettings

- (instancetype)init {
    self = [super init];
    if (self) {
        _ceilingDecibels = -20;
        _cycleInterval = 1.5;
        _volumeInterval = 0.05;
        _missedPollsLimit = 4;
        _retryBurst = 4;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    QLMSystemSettings *copy = [[[self class] allocWithZone:zone] init];
    copy.ceilingDecibels = self.ceilingDecibels;
    copy.cycleInterval = self.cycleInterval;
    copy.volumeInterval = self.volumeInterval;
    copy.missedPollsLimit = self.missedPollsLimit;
    copy.retryBurst = self.retryBurst;
    return copy;
}

@end

// A monitor System is tracking. Touched only on the queue.
@interface QLMMonitorRecord : NSObject
@property (nonatomic) NSData *hardwareID;
@property (nonatomic) uint8_t session;
@property (nonatomic) NSString *serialNumber;
@property (nonatomic) NSString *systemInfo;
@property (nonatomic) NSString *model;
@property (nonatomic) NSString *firmwareVersion;
@property (nonatomic) BOOL hasTelemetry;
@property (nonatomic) QLMTelemetry telemetry;
@property (nonatomic) NSUInteger missedPolls;
@property (nonatomic) NSDate *lastReply;
@property (nonatomic) BOOL retrying;
@property (nonatomic) BOOL muted;
@end

@implementation QLMMonitorRecord
@end

static uint8_t QLMMuteValueFor(QLMMonitorRecord *monitor) {
    return monitor.muted ? QLMMuteValueMuted : QLMMuteValueUnmuted;
}

static QLMMonitorStatus QLMMonitorStatusFor(const QLMTelemetry *telemetry) {
    if (telemetry->status == QLMTelemetryStatusOn) {
        return QLMMonitorStatusOn;
    }
    return telemetry->status == QLMTelemetryAbsent ? QLMMonitorStatusUnknown : QLMMonitorStatusStandby;
}

static QLMMonitorClass QLMMonitorClassFor(const QLMTelemetry *telemetry) {
    switch (telemetry->deviceClass) {
    case QLMTelemetryClassSubwoofer: return QLMMonitorClassSubwoofer;
    case QLMTelemetryClassTwoWay: return QLMMonitorClassTwoWay;
    default: return QLMMonitorClassUnknown;
    }
}

typedef void (^QLMSendCompletion)(const QLMMessage *_Nullable reply, NSError *_Nullable error);

@interface QLMSystem ()
@property (atomic, readwrite) QLMSnapshot *snapshot;
@end

@implementation QLMSystem {
    dispatch_queue_t _queue;
    id<QLMAdapter> _adapter;
    NSMutableArray<QLMMonitorRecord *> *_monitors;
    uint8_t _nextSession;
    NSMutableArray<dispatch_block_t> *_sends;
    BOOL _inFlight;
    BOOL _running;
    BOOL _dirty;
    dispatch_source_t _cycleTimer;
    NSNumber *_volumeDecibels;
    BOOL _volumeSendPending;
    NSDate *_lastVolumeSend;
    BOOL _dimmed;
    NSString *_activeGroupName;
    void (^_applyFinish)(NSError *_Nullable error);  // set while an apply runs
    QLMSnapshotHandler _snapshotHandler;
    dispatch_queue_t _snapshotQueue;
}

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter settings:(QLMSystemSettings *)settings {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.commonwealthrecordings.qlm.system", DISPATCH_QUEUE_SERIAL);
        _adapter = adapter;
        _settings = [settings copy];
        _monitors = [NSMutableArray array];
        _nextSession = QLMAddressSessionFirst;
        _sends = [NSMutableArray array];
        _snapshot = [[QLMSnapshot alloc] init];
    }
    return self;
}

- (void)dealloc {
    if (_cycleTimer != NULL) {
        dispatch_source_cancel(_cycleTimer);
    }
}

// Every public method's work runs here, so the publishing rule holds after it.
- (void)onQueue:(dispatch_block_t)block {
    dispatch_async(_queue, ^{
        block();
        [self publishIfSettled];
    });
}

- (void)setSnapshotHandler:(QLMSnapshotHandler)handler queue:(dispatch_queue_t)queue {
    QLMSnapshotHandler copied = [handler copy];
    [self onQueue:^{
        self->_snapshotHandler = copied;
        self->_snapshotQueue = queue;
        if (copied != nil) {
            QLMSnapshot *latest = self.snapshot;
            dispatch_async(queue, ^{
                copied(latest);
            });
        }
    }];
}

#pragma mark - Lifecycle

- (void)start {
    [self onQueue:^{
        if (self->_running) {
            return;
        }
        self->_running = YES;
        [self->_adapter startOnQueue:self->_queue];
        self->_dirty = YES;
        [self runCycle];

        __weak QLMSystem *weakSelf = self;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
        uint64_t interval = (uint64_t)(self.settings.cycleInterval * (double)NSEC_PER_SEC);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval), interval, interval / 10);
        dispatch_source_set_event_handler(timer, ^{
            [weakSelf runCycle];
        });
        dispatch_resume(timer);
        self->_cycleTimer = timer;
    }];
}

- (void)stop {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        self->_running = NO;
        if (self->_cycleTimer != NULL) {
            dispatch_source_cancel(self->_cycleTimer);
            self->_cycleTimer = NULL;
        }
        [self->_sends removeAllObjects];
        // A reply that never comes must not stall the next start.
        self->_inFlight = NO;
        [self->_adapter stop];
        [self->_monitors removeAllObjects];
        if (self->_applyFinish != nil) {
            [self finishApplyOfGroup:nil error:QLMSystemErrorMake(QLMSystemErrorNotRunning, @"System stopped during the apply.", nil)];
        }
        [self publish];
    }];
}

#pragma mark - Sending

// One item at a time: the bus is half-duplex and the adapter keeps one
// request in flight. A send waits in line until the previous reply lands.
- (void)enqueue:(dispatch_block_t)item {
    [_sends addObject:item];
    [self pump];
}

- (void)send:(QLMMessage)message then:(nullable QLMSendCompletion)completion {
    __weak QLMSystem *weakSelf = self;
    [self enqueue:^{
        QLMSystem *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf->_adapter sendMessage:message replyHandler:^(const QLMMessage *reply, NSError *error) {
            [weakSelf finishItem:completion == nil ? nil : ^{
                completion(reply, error);
            }];
        }];
    }];
}

// Not a send: the block runs when the line reaches it, after every item
// queued before it.
- (void)afterSends:(dispatch_block_t)block {
    __weak QLMSystem *weakSelf = self;
    [self enqueue:^{
        [weakSelf finishItem:block];
    }];
}

// Ends the item in flight. The work runs only while System runs.
- (void)finishItem:(nullable dispatch_block_t)work {
    _inFlight = NO;
    if (work != nil && _running) {
        work();
    }
    [self publishIfSettled];
    [self pump];
}

- (void)pump {
    if (_inFlight || _sends.count == 0 || !_running) {
        return;
    }
    dispatch_block_t next = _sends.firstObject;
    [_sends removeObjectAtIndex:0];
    _inFlight = YES;
    next();
}

- (BOOL)isIdle {
    return !_inFlight && _sends.count == 0;
}

#pragma mark - The cycle

// What GLM sends every 1.2 to 1.8 s: the volume, the keep-alive, a poll to
// each monitor, then a probe for monitors without a lease. A cycle is
// skipped while the previous one is still on the bus.
- (void)runCycle {
    if (!_running || ![self isIdle]) {
        return;
    }
    if (_volumeDecibels != nil) {
        [self sendVolume];
    }
    [self send:QLMCommandKeepAlive() then:nil];
    for (QLMMonitorRecord *monitor in [_monitors copy]) {
        [self pollMonitor:monitor];
    }
    [self probe];
}

#pragma mark - Discovery and leases

- (uint8_t)takeSession {
    for (unsigned attempt = 0; attempt < 256; attempt++) {
        uint8_t candidate = _nextSession;
        _nextSession = (uint8_t)(candidate >= QLMAddressSessionLast ? QLMAddressSessionFirst : candidate + 1);
        BOOL used = NO;
        for (QLMMonitorRecord *monitor in _monitors) {
            if (monitor.session == candidate) {
                used = YES;
                break;
            }
        }
        if (!used) {
            return candidate;
        }
    }
    return 0;
}

- (nullable QLMMonitorRecord *)monitorWithHardwareID:(NSData *)hardwareID {
    for (QLMMonitorRecord *monitor in _monitors) {
        if ([monitor.hardwareID isEqualToData:hardwareID]) {
            return monitor;
        }
    }
    return nil;
}

// A probe is answered by one monitor without a lease. It gets the next
// session ID, then its identity is read, and the probe repeats for the next.
- (void)probe {
    [self send:QLMCommandProbe() then:^(const QLMMessage *reply, NSError *error) {
        uint8_t hardwareID[3];
        if (reply != NULL && QLMReplyHardwareID(reply, hardwareID)) {
            [self assignSessionTo:hardwareID];
        }
    }];
}

- (void)assignSessionTo:(const uint8_t[3])hardwareID {
    NSData *identity = [NSData dataWithBytes:hardwareID length:3];
    // A monitor answering the probe holds no lease. If we still track one
    // under this ID, that lease is gone.
    QLMMonitorRecord *stale = [self monitorWithHardwareID:identity];
    if (stale != nil) {
        [_monitors removeObject:stale];
        _dirty = YES;
    }
    uint8_t session = [self takeSession];
    if (session == 0) {
        return;
    }
    [self send:QLMCommandAssignSession(hardwareID, session) then:^(const QLMMessage *reply, NSError *error) {
        uint8_t acked = 0;
        if (reply == NULL || !QLMReplySessionAck(reply, &acked) || acked != session) {
            return;
        }
        QLMMonitorRecord *monitor = [[QLMMonitorRecord alloc] init];
        monitor.hardwareID = identity;
        monitor.session = session;
        monitor.lastReply = [NSDate date];
        [self->_monitors addObject:monitor];
        self->_dirty = YES;
        [self identify:monitor];
        [self pollMonitor:monitor];
        [self probe];
    }];
}

- (void)identify:(QLMMonitorRecord *)monitor {
    [self ask:QLMCommandSystemInfo(monitor.session) then:^(const char *text) {
        monitor.systemInfo = @(text);
        char model[QLMPayloadMax];
        char firmware[QLMPayloadMax];
        if (QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware)) {
            monitor.model = @(model);
            monitor.firmwareVersion = firmware[0] != '\0' ? @(firmware) : nil;
        }
    }];
    [self ask:QLMCommandSerialNumber(monitor.session) then:^(const char *text) {
        monitor.serialNumber = @(text);
    }];
}

// Sends a query whose reply is text, and hands over the text if it reads.
- (void)ask:(QLMMessage)query then:(void (^)(const char *text))store {
    [self send:query then:^(const QLMMessage *reply, NSError *error) {
        char text[QLMPayloadMax];
        if (reply != NULL && QLMReplyText(reply, text, sizeof text)) {
            store(text);
            self->_dirty = YES;
        }
    }];
}

#pragma mark - Polling

- (void)pollMonitor:(QLMMonitorRecord *)monitor {
    if (monitor.retrying) {
        return;
    }
    [self send:QLMCommandPoll(monitor.session) then:^(const QLMMessage *reply, NSError *error) {
        if (reply != NULL) {
            [self monitor:monitor replied:reply];
        } else {
            monitor.missedPolls += 1;
            self->_dirty = YES;
            if (monitor.missedPolls >= self.settings.missedPollsLimit) {
                [self retryMonitor:monitor];
            }
        }
    }];
}

- (void)monitor:(QLMMonitorRecord *)monitor replied:(const QLMMessage *)reply {
    monitor.missedPolls = 0;
    monitor.lastReply = [NSDate date];
    QLMTelemetry telemetry;
    QLMTelemetryStatus status = QLMReplyTelemetry(reply, &telemetry);
    if (status == QLMTelemetryOK || status == QLMTelemetryErrorUnknownTag) {
        monitor.telemetry = telemetry;
        monitor.hasTelemetry = YES;
    }
    // A bare ack or a busy marker carries no data this round.
    _dirty = YES;
}

// After the limit of missed polls, a burst of polls to the dead address.
// If none is answered the lease is gone, and the next probe finds the
// monitor again under the next session ID.
- (void)retryMonitor:(QLMMonitorRecord *)monitor {
    monitor.retrying = YES;
    __block NSUInteger remaining = self.settings.retryBurst;
    __block BOOL answered = NO;
    for (NSUInteger i = 0; i < self.settings.retryBurst; i++) {
        [self send:QLMCommandPoll(monitor.session) then:^(const QLMMessage *reply, NSError *error) {
            if (reply != NULL && !answered) {
                answered = YES;
                [self monitor:monitor replied:reply];
            }
            remaining -= 1;
            if (remaining == 0) {
                monitor.retrying = NO;
                if (!answered) {
                    [self->_monitors removeObject:monitor];
                    self->_dirty = YES;
                    [self probe];
                }
            }
        }];
    }
}

#pragma mark - Volume

- (void)setVolumeDecibels:(double)decibels {
    [self onQueue:^{
        self->_volumeDecibels = @(decibels);
        self->_dirty = YES;
        [self scheduleVolumeSend];
    }];
}

- (void)scheduleVolumeSend {
    if (_volumeSendPending || !_running) {
        return;
    }
    NSTimeInterval interval = self.settings.volumeInterval;
    NSTimeInterval since = _lastVolumeSend == nil ? interval : -[_lastVolumeSend timeIntervalSinceNow];
    if (since >= interval) {
        [self sendVolume];
        return;
    }
    _volumeSendPending = YES;
    __weak QLMSystem *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((interval - since) * (double)NSEC_PER_SEC)), _queue, ^{
        QLMSystem *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf->_volumeSendPending = NO;
        if (strongSelf->_running) {
            [strongSelf sendVolume];
        }
    });
}

- (QLMMessage)volumeMessage {
    double decibels = _volumeDecibels.doubleValue;
    double ceiling = self.settings.ceilingDecibels;
    return _dimmed ? QLMCommandDim(decibels, ceiling) : QLMCommandVolume(decibels, ceiling);
}

- (void)sendVolume {
    _lastVolumeSend = [NSDate date];
    [self send:[self volumeMessage] then:nil];
}

#pragma mark - Dim

- (void)setDimmed:(BOOL)dimmed {
    [self onQueue:^{
        if (self->_dimmed == dimmed) {
            return;
        }
        self->_dimmed = dimmed;
        self->_dirty = YES;
        if (self->_volumeDecibels != nil) {
            [self scheduleVolumeSend];
        }
    }];
}

#pragma mark - Mute

- (void)setMuted:(BOOL)muted forMonitorWithHardwareID:(NSData *)hardwareID {
    NSData *identity = [hardwareID copy];
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        QLMMonitorRecord *monitor = [self monitorWithHardwareID:identity];
        if (monitor != nil) {
            monitor.muted = muted;
            [self sendMuteRounds];
        }
    }];
}

- (void)setAllMuted:(BOOL)muted {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        for (QLMMonitorRecord *monitor in self->_monitors) {
            monitor.muted = muted;
        }
        if (self->_volumeDecibels != nil) {
            // Part of the sequence, so it skips the coalescing timer.
            [self sendVolume];
        }
        [self sendMuteRounds];
    }];
}

// Two rounds, each restating every monitor's mute state. A 2B reply is a
// bare ack, and a missed one is a lost send, not a missed poll.
- (void)sendMuteRounds {
    NSArray<QLMMonitorRecord *> *monitors = [_monitors copy];
    for (NSUInteger round = 0; round < 2; round++) {
        for (QLMMonitorRecord *monitor in monitors) {
            [self send:QLMCommandMute(monitor.session, QLMMuteValueFor(monitor)) then:nil];
        }
    }
    [self afterSends:^{
        self->_dirty = YES;
    }];
}

#pragma mark - Power

// Sent back to back. GLM spaces them about 22 ms apart.
- (void)sleep {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        const QLMPowerStep steps[] = {QLMPowerStepStandbyPrepare, QLMPowerStepStandbyPrepare, QLMPowerStepPowerOff, QLMPowerStepPowerOff};
        for (size_t i = 0; i < sizeof steps / sizeof steps[0]; i++) {
            [self send:QLMCommandPower(steps[i]) then:nil];
        }
    }];
}

// The monitors come back under new sessions, and the probe finds them.
- (void)wake {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        for (int pair = 0; pair < 3; pair++) {
            [self send:QLMCommandPower(QLMPowerStepWakeFirst) then:nil];
            [self send:QLMCommandPower(QLMPowerStepWakeSecond) then:nil];
        }
    }];
}

#pragma mark - Group apply

- (void)applyGroup:(QLMSetupGroup *)group completion:(void (^)(NSError *_Nullable error))completion {
    void (^finish)(NSError *) = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    };
    [self onQueue:^{
        NSArray<QLMMonitorRecord *> *targets = nil;
        NSError *refusal = nil;
        NSArray<QLMDSPBlock *> *blocks = [self checkGroup:group targets:&targets error:&refusal];
        if (blocks == nil) {
            finish(refusal);
            return;
        }
        [self sendGroup:group blocks:blocks targets:targets finish:finish];
    }];
}

// Every check runs before the first frame. On success, `targets` holds the
// monitor for each block, in the same order.
- (nullable NSArray<QLMDSPBlock *> *)checkGroup:(QLMSetupGroup *)group
                                       targets:(NSArray<QLMMonitorRecord *> *_Nullable *_Nonnull)targets
                                         error:(NSError **)error {
    if (_applyFinish != nil) {
        *error = QLMSystemErrorMake(QLMSystemErrorAlreadyApplying, @"A group apply is already running.", nil);
        return nil;
    }
    if (!_running) {
        *error = QLMSystemErrorMake(QLMSystemErrorNotRunning, @"System is not running.", nil);
        return nil;
    }
    NSError *underlying = nil;
    NSArray<QLMDSPBlock *> *blocks = [QLMDSPBlock blocksForGroup:group error:&underlying];
    if (blocks == nil) {
        *error = QLMSystemErrorMake(QLMSystemErrorBlocksFailed, @"The DSP blocks could not be built.", underlying);
        return nil;
    }
    for (QLMDSPBlock *block in blocks) {
        if (!block.rateVerified) {
            NSString *description = [NSString stringWithFormat:@"The design rate of node %@ (%@) is unverified.", block.node.serial, block.node.className];
            *error = QLMSystemErrorMake(QLMSystemErrorUnverifiedRate, description, nil);
            return nil;
        }
    }
    NSMutableArray<QLMMonitorRecord *> *matched = [NSMutableArray arrayWithCapacity:blocks.count];
    for (QLMDSPBlock *block in blocks) {
        NSData *hardwareID = block.node.hardwareID;
        QLMMonitorRecord *monitor = hardwareID != nil ? [self monitorWithHardwareID:hardwareID] : nil;
        if (monitor == nil || [matched containsObject:monitor]) {
            NSString *description = [NSString stringWithFormat:@"Node %@ matches no single leased monitor.", block.node.serial];
            *error = QLMSystemErrorMake(QLMSystemErrorUnknownMonitor, description, nil);
            return nil;
        }
        [matched addObject:monitor];
    }
    if (_volumeDecibels == nil) {
        *error = QLMSystemErrorMake(QLMSystemErrorNoVolume, @"Set a volume before a group apply.", nil);
        return nil;
    }
    *targets = matched;
    return blocks;
}

// GLM's apply: duck, wake, unmute and route, the blocks, then restore. Every
// frame is queued at once, so no cycle runs until the apply finishes.
- (void)sendGroup:(QLMSetupGroup *)group
           blocks:(NSArray<QLMDSPBlock *> *)blocks
          targets:(NSArray<QLMMonitorRecord *> *)targets
           finish:(void (^)(NSError *_Nullable error))finish {
    _applyFinish = finish;

    __block NSError *failure = nil;
    QLMSendCompletion broadcast = ^(const QLMMessage *reply, NSError *error) {
        if (error != nil && failure == nil) {
            failure = QLMSystemErrorMake(QLMSystemErrorSendFailed, @"A frame of the apply failed.", error);
        }
    };
    QLMSendCompletion acked = ^(const QLMMessage *reply, NSError *error) {
        if ((reply == NULL || error != nil) && failure == nil) {
            failure = QLMSystemErrorMake(QLMSystemErrorSendFailed, @"A monitor did not ack a frame of the apply.", error);
        }
    };

    [self send:QLMCommandVolumeWord(QLMVolumeWordMin, QLMVolumeWordMax) then:broadcast];
    [self send:QLMCommandDuck() then:broadcast];

    [self send:QLMCommandPower(QLMPowerStepWakeFirst) then:broadcast];
    [self send:QLMCommandPower(QLMPowerStepWakeFirst) then:broadcast];
    [self send:QLMCommandPower(QLMPowerStepWakeSecond) then:broadcast];

    // GLM also sends each monitor 05 04 00, the test signal off. 05 is on
    // the never-send list, so qlm skips it.
    for (NSUInteger i = 0; i < blocks.count; i++) {
        uint8_t session = targets[i].session;
        NSData *routing = blocks[i].payloads.lastObject;
        [self send:QLMCommandMute(session, QLMMuteValueUnmuted) then:acked];
        [self send:QLMMessageMake(session, routing.bytes, routing.length) then:acked];
    }

    for (NSUInteger i = 0; i < blocks.count; i++) {
        uint8_t session = targets[i].session;
        [self send:QLMCommandKeepAlive() then:broadcast];
        for (NSData *payload in blocks[i].payloads) {
            [self send:QLMMessageMake(session, payload.bytes, payload.length) then:acked];
        }
    }

    for (int i = 0; i < 5; i++) {
        _lastVolumeSend = [NSDate date];
        [self send:[self volumeMessage] then:broadcast];
    }
    for (QLMMonitorRecord *monitor in targets) {
        [self send:QLMCommandMute(monitor.session, QLMMuteValueFor(monitor)) then:acked];
        [self send:QLMCommandInputSync(monitor.session) then:acked];
    }
    NSString *name = [group.name copy];
    [self afterSends:^{
        [self finishApplyOfGroup:name error:failure];
    }];

    // The frames are queued, so this is the one snapshot published mid-send.
    [self publish];
}

- (void)finishApplyOfGroup:(nullable NSString *)name error:(nullable NSError *)error {
    void (^finish)(NSError *) = _applyFinish;
    _applyFinish = nil;
    if (error == nil) {
        _activeGroupName = name;
    }
    _dirty = YES;
    if (finish != nil) {
        finish(error);
    }
}

#pragma mark - Snapshots

- (void)publishIfSettled {
    if (_dirty && [self isIdle]) {
        [self publish];
    }
}

- (void)publish {
    _dirty = NO;
    NSMutableArray<QLMMonitorState *> *states = [NSMutableArray arrayWithCapacity:_monitors.count];
    BOOL allIdentified = _monitors.count > 0;
    BOOL allMuted = _monitors.count > 0;
    BOOL anyOn = NO;
    for (QLMMonitorRecord *monitor in _monitors) {
        QLMMonitorState *state = [[QLMMonitorState alloc] init];
        state.hardwareID = monitor.hardwareID;
        state.session = monitor.session;
        state.serialNumber = monitor.serialNumber;
        state.systemInfo = monitor.systemInfo;
        state.model = monitor.model;
        state.firmwareVersion = monitor.firmwareVersion;
        state.missedPolls = monitor.missedPolls;
        state.lastReply = monitor.lastReply;
        state.muted = monitor.muted;
        if (monitor.hasTelemetry) {
            QLMTelemetry telemetry = monitor.telemetry;
            state.temperature = telemetry.temperature;
            state.deviceClass = QLMMonitorClassFor(&telemetry);
            state.inputMeter = telemetry.inputMeter;
            state.hfMeter = telemetry.hfMeter;
            state.lfMeter = telemetry.lfMeter;
            state.subMeter = telemetry.subMeter;
            state.status = QLMMonitorStatusFor(&telemetry);
        }
        state.identified = state.serialNumber != nil && state.systemInfo != nil && state.status != QLMMonitorStatusUnknown;
        allIdentified = allIdentified && state.identified;
        allMuted = allMuted && state.muted;
        anyOn = anyOn || state.status == QLMMonitorStatusOn;
        [states addObject:state];
    }
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = _running;
    snapshot.monitors = states;
    snapshot.volumeDecibels = _volumeDecibels;
    snapshot.dimmed = _dimmed;
    snapshot.applying = _applyFinish != nil;
    snapshot.activeGroupName = _activeGroupName;
    snapshot.idle = [self isIdle];
    snapshot.allIdentified = allIdentified;
    snapshot.allMuted = allMuted;
    snapshot.anyOn = anyOn;
    self.snapshot = snapshot;
    QLMSnapshotHandler handler = _snapshotHandler;
    if (handler != nil && _snapshotQueue != NULL) {
        dispatch_async(_snapshotQueue, ^{
            handler(snapshot);
        });
    }
}

@end
