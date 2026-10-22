#import "QLMSystem.h"

#include "QLMCommands.h"
#include "QLMReplies.h"
#import "QLMSnapshotInternal.h"

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
@property (nonatomic) BOOL hasTelemetry;
@property (nonatomic) QLMTelemetry telemetry;
@property (nonatomic) NSUInteger missedPolls;
@property (nonatomic) NSDate *lastReply;
@property (nonatomic) BOOL retrying;
@end

@implementation QLMMonitorRecord
@end

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
        _snapshot = [[QLMSnapshot alloc] initWithRunning:NO monitors:@[] volumeDecibels:nil];
    }
    return self;
}

- (void)dealloc {
    if (_cycleTimer != NULL) {
        dispatch_source_cancel(_cycleTimer);
    }
}

- (void)setSnapshotHandler:(QLMSnapshotHandler)handler queue:(dispatch_queue_t)queue {
    dispatch_async(_queue, ^{
        self->_snapshotHandler = [handler copy];
        self->_snapshotQueue = queue;
    });
}

#pragma mark - Lifecycle

- (void)start {
    dispatch_async(_queue, ^{
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
    });
}

- (void)stop {
    dispatch_async(_queue, ^{
        if (!self->_running) {
            return;
        }
        self->_running = NO;
        if (self->_cycleTimer != NULL) {
            dispatch_source_cancel(self->_cycleTimer);
            self->_cycleTimer = NULL;
        }
        [self->_sends removeAllObjects];
        [self->_adapter stop];
        [self->_monitors removeAllObjects];
        [self publish];
    });
}

#pragma mark - Sending

// One message at a time: the bus is half-duplex and the adapter keeps one
// request in flight. A send waits in line until the previous reply lands.
- (void)send:(QLMMessage)message then:(nullable QLMSendCompletion)completion {
    __weak QLMSystem *weakSelf = self;
    [_sends addObject:^{
        QLMSystem *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf->_adapter sendMessage:message replyHandler:^(const QLMMessage *reply, NSError *error) {
            QLMSystem *handlerSelf = weakSelf;
            if (handlerSelf == nil) {
                return;
            }
            handlerSelf->_inFlight = NO;
            if (completion != nil && handlerSelf->_running) {
                completion(reply, error);
            }
            if (handlerSelf->_dirty) {
                [handlerSelf publish];
            }
            [handlerSelf pump];
        }];
    }];
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

#pragma mark - The cycle

// What GLM sends every 1.2 to 1.8 s: the volume, the keep-alive, a poll to
// each monitor, then a probe for monitors without a lease. A cycle is
// skipped while the previous one is still on the bus.
- (void)runCycle {
    if (!_running || _inFlight || _sends.count > 0) {
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
    for (QLMMonitorRecord *monitor in [_monitors copy]) {
        if ([monitor.hardwareID isEqualToData:identity]) {
            [_monitors removeObject:monitor];
            _dirty = YES;
        }
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
    [self send:QLMCommandSystemInfo(monitor.session) then:^(const QLMMessage *reply, NSError *error) {
        char text[QLMPayloadMax];
        if (reply != NULL && QLMReplyText(reply, text, sizeof text)) {
            monitor.systemInfo = @(text);
            self->_dirty = YES;
        }
    }];
    [self send:QLMCommandSerialNumber(monitor.session) then:^(const QLMMessage *reply, NSError *error) {
        char text[QLMPayloadMax];
        if (reply != NULL && QLMReplyText(reply, text, sizeof text)) {
            monitor.serialNumber = @(text);
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
    dispatch_async(_queue, ^{
        self->_volumeDecibels = @(decibels);
        self->_dirty = YES;
        [self scheduleVolumeSend];
    });
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

- (void)sendVolume {
    _lastVolumeSend = [NSDate date];
    [self send:QLMCommandVolume(_volumeDecibels.doubleValue, self.settings.ceilingDecibels) then:nil];
}

#pragma mark - Snapshots

- (void)publish {
    _dirty = NO;
    NSMutableArray<QLMMonitorState *> *states = [NSMutableArray arrayWithCapacity:_monitors.count];
    for (QLMMonitorRecord *monitor in _monitors) {
        QLMMonitorState *state = [[QLMMonitorState alloc] initWithHardwareID:monitor.hardwareID session:monitor.session];
        state.serialNumber = monitor.serialNumber;
        state.systemInfo = monitor.systemInfo;
        state.missedPolls = monitor.missedPolls;
        state.lastReply = monitor.lastReply;
        if (monitor.hasTelemetry) {
            QLMTelemetry telemetry = monitor.telemetry;
            state.temperature = telemetry.temperature;
            state.deviceClass = telemetry.deviceClass;
            state.inputMeter = telemetry.inputMeter;
            state.hfMeter = telemetry.hfMeter;
            state.lfMeter = telemetry.lfMeter;
            state.subMeter = telemetry.subMeter;
            if (telemetry.status == QLMTelemetryStatusOn) {
                state.status = QLMMonitorStatusOn;
            } else if (telemetry.status != QLMTelemetryAbsent) {
                state.status = QLMMonitorStatusStandby;
            }
        }
        [states addObject:state];
    }
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] initWithRunning:_running monitors:states volumeDecibels:_volumeDecibels];
    self.snapshot = snapshot;
    QLMSnapshotHandler handler = _snapshotHandler;
    if (handler != nil && _snapshotQueue != NULL) {
        dispatch_async(_snapshotQueue, ^{
            handler(snapshot);
        });
    }
}

@end
