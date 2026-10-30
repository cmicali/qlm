#import "QLMSystem.h"

#import "QLMApplySequence.h"
#include "QLMCommands.h"
#include "QLMReplies.h"
#import "QLMDSPBlock.h"
#import "QLMKnob.h"
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
        _cycleInterval = 0.57;
        _volumeInterval = 0.05;
        _missedPollsLimit = 4;
        _retryBurst = 4;
        _adapterPollInterval = 0.107;
        _discoversMonitors = YES;
        _mutedHardwareIDs = [NSSet set];
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
    copy.adapterPollInterval = self.adapterPollInterval;
    copy.discoversMonitors = self.discoversMonitors;
    copy.mutedHardwareIDs = self.mutedHardwareIDs;
    copy.mutingAll = self.mutingAll;
    return copy;
}

@end

// GLM polls the adapter in pairs, 2.4 ms apart (docs/adapter-status.md).
static const NSUInteger QLMAdapterPollsPerRound = 2;

// GLM's spacing between the power steps.
static const NSTimeInterval QLMSleepStepSpacing = 0.022;
static const NSTimeInterval QLMWakePairSpacing = 0.2;
static const NSTimeInterval QLMWakeVolumeDelay = 0.235;

// A monitor System is tracking. Touched only on the queue.
@interface QLMMonitorRecord : NSObject
@property (nonatomic) NSData *hardwareID;
@property (nonatomic) uint8_t session;
@property (nonatomic) NSString *serialNumber;
@property (nonatomic) NSString *systemInfo;
@property (nonatomic) NSString *model;
@property (nonatomic) NSString *firmwareVersion;
@property (nonatomic) BOOL identifying;  // its identity queries are queued
@property (nonatomic) BOOL hasTelemetry;
@property (nonatomic) QLMTelemetry telemetry;
@property (nonatomic) NSUInteger missedPolls;
@property (nonatomic) NSDate *lastReply;
@property (nonatomic) BOOL retrying;
// Holds the active group's block for this lease, or needs none.
@property (nonatomic) BOOL configured;
// Hears its state of 2B after its next poll that says on.
@property (nonatomic) BOOL needsState;
@property (nonatomic, readonly) BOOL isOn;  // its last telemetry says on
@end

@implementation QLMMonitorRecord

- (BOOL)isOn {
    QLMTelemetry telemetry = self.telemetry;
    return self.hasTelemetry && telemetry.status == QLMTelemetryStatusOn;
}

@end

// The adapter itself, at 01. Touched only on the queue.
@interface QLMTrackedAdapter : NSObject
@property (nonatomic) NSString *serialNumber;
@property (nonatomic) NSString *systemInfo;
@property (nonatomic) NSString *model;
@property (nonatomic) NSString *firmwareVersion;
@property (nonatomic) BOOL identifying;
@property (nonatomic) BOOL hasStatus;
@property (nonatomic) QLMAdapterStatus status;
@property (nonatomic) NSUInteger missedPolls;
@property (nonatomic) NSDate *lastReply;
@end

@implementation QLMTrackedAdapter
@end

static BOOL QLMAdapterStatusDiffers(const QLMAdapterStatus *a, const QLMAdapterStatus *b) {
    return a->knob != b->knob || a->mic != b->mic || a->hasKnobPosition != b->hasKnobPosition || a->knobTenths != b->knobTenths;
}

// The frame went out, whether or not a reply came back.
static BOOL QLMSendWentOut(NSError *_Nullable error) {
    return error == nil || ([error.domain isEqualToString:QLMAdapterErrorDomain] &&
                            (error.code == QLMAdapterErrorTimeout || error.code == QLMAdapterErrorBadReply));
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
    NSUInteger _run;  // counts stops
    BOOL _dirty;
    dispatch_source_t _cycleTimer;
    BOOL _cycleQueued;
    QLMTrackedAdapter *_adapterRecord;
    NSError *_adapterError;
    dispatch_source_t _adapterTimer;
    NSUInteger _adapterPollsQueued;
    QLMKnob *_knob;
    NSNumber *_volumeDecibels;
    BOOL _volumeSendPending;
    NSDate *_lastVolumeSend;
    BOOL _dimmed;
    // The hardware IDs the user muted. Kept by ID, so a mute outlives a
    // lease that lapses and the monitor's next lease.
    NSMutableSet<NSData *> *_mutedIDs;
    BOOL _adapterMuted;
    NSString *_activeGroupName;
    // Set when an apply starts, since GLM's routing pass already treats the
    // new group's members as such; _activeGroupName waits for it to finish.
    // It decides membership, and the block each new lease gets. It outlives
    // stop, so the next start applies it in full.
    QLMSetupGroup *_activeGroup;
    NSDictionary<NSData *, QLMDSPBlock *> *_activeBlocks;  // its blocks, by hardware ID
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
        _mutedIDs = [settings.mutedHardwareIDs mutableCopy];
        _adapterMuted = settings.mutingAll;
        _adapterRecord = [[QLMTrackedAdapter alloc] init];
        _knob = [[QLMKnob alloc] init];
        _snapshot = [[QLMSnapshot alloc] init];
    }
    return self;
}

- (void)dealloc {
    if (_cycleTimer != NULL) {
        dispatch_source_cancel(_cycleTimer);
    }
    if (_adapterTimer != NULL) {
        dispatch_source_cancel(_adapterTimer);
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
        // GLM's opening, less what qlm never sends: the adapter's status,
        // its system info, its serial, then the cycle (captures/startup-idle,
        // 7.29 s). GLM's 01 22, 01 51 82, and wake are left out.
        [self pollAdapter];
        [self identifyAdapter];
        [self runCycle];

        __weak QLMSystem *weakSelf = self;
        self->_cycleTimer = [self timerEvery:self.settings.cycleInterval run:^{
            [weakSelf runCycle];
        }];
        if (self.settings.adapterPollInterval > 0) {
            self->_adapterTimer = [self timerEvery:self.settings.adapterPollInterval run:^{
                [weakSelf pollAdapter];
            }];
        }
    }];
}

- (dispatch_source_t)timerEvery:(NSTimeInterval)seconds run:(dispatch_block_t)block {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    uint64_t interval = (uint64_t)(seconds * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval), interval, interval / 10);
    dispatch_source_set_event_handler(timer, block);
    dispatch_resume(timer);
    return timer;
}

- (void)stop {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        self->_running = NO;
        self->_run += 1;
        if (self->_cycleTimer != NULL) {
            dispatch_source_cancel(self->_cycleTimer);
            self->_cycleTimer = NULL;
        }
        if (self->_adapterTimer != NULL) {
            dispatch_source_cancel(self->_adapterTimer);
            self->_adapterTimer = NULL;
        }
        [self->_sends removeAllObjects];
        // A reply that never comes must not stall the next start.
        self->_inFlight = NO;
        self->_cycleQueued = NO;
        self->_adapterPollsQueued = 0;
        [self->_adapter stop];
        [self->_monitors removeAllObjects];
        [self->_knob reset];
        self->_adapterRecord = [[QLMTrackedAdapter alloc] init];
        self->_adapterError = nil;
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

- (dispatch_block_t)itemSending:(QLMMessage)message then:(nullable QLMSendCompletion)completion {
    __weak QLMSystem *weakSelf = self;
    return ^{
        QLMSystem *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf->_adapter sendMessage:message replyHandler:^(const QLMMessage *reply, NSError *error) {
            [weakSelf noteSendError:error];
            [weakSelf finishItem:completion == nil ? nil : ^{
                completion(reply, error);
            }];
        }];
    };
}

- (void)send:(QLMMessage)message then:(nullable QLMSendCompletion)completion {
    [self enqueue:[self itemSending:message then:completion]];
}

// `completionFor`, if given, picks each frame's completion by its address.
- (void)sendRecords:(NSArray<NSData *> *)records then:(nullable QLMSendCompletion (^)(uint8_t address))completionFor {
    for (NSData *record in records) {
        QLMMessage message = QLMApplyMessage(record);
        [self send:message then:completionFor != nil ? completionFor(message.address) : nil];
    }
}

// Ahead of everything queued, in order. Call it only from an item's
// completion, which runs before the next item goes out.
- (void)enqueueNext:(NSArray<dispatch_block_t> *)items {
    [_sends insertObjects:items atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, items.count)]];
}

- (void)sendRecordsNext:(NSArray<NSData *> *)records {
    NSMutableArray<dispatch_block_t> *items = [NSMutableArray arrayWithCapacity:records.count];
    for (NSData *record in records) {
        [items addObject:[self itemSending:QLMApplyMessage(record) then:nil]];
    }
    [self enqueueNext:items];
}

// A busy or missing adapter shows in the snapshot until a send goes out.
- (void)noteSendError:(nullable NSError *)error {
    if (!_running) {
        return;
    }
    BOOL noBus = [error.domain isEqualToString:QLMAdapterErrorDomain] &&
                 (error.code == QLMAdapterErrorBusy || error.code == QLMAdapterErrorDisconnected);
    if (noBus) {
        [self forgetAdapter];
    }
    if (noBus && ![_adapterError isEqual:error]) {
        _adapterError = error;
        _dirty = YES;
    } else if (error == nil && _adapterError != nil) {
        _adapterError = nil;
        _dirty = YES;
    }
}

// Not a send: holds the line, so the next item goes out `seconds` after the
// one before it ends. Nothing else goes out meanwhile.
- (void)hold:(NSTimeInterval)seconds {
    NSUInteger run = _run;
    dispatch_queue_t queue = _queue;
    __weak QLMSystem *weakSelf = self;
    [self enqueue:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * (double)NSEC_PER_SEC)), queue, ^{
            QLMSystem *strongSelf = weakSelf;
            // TRAP: a stop empties the line. A hold from before it must not
            // end an item of the next start.
            if (strongSelf != nil && strongSelf->_run == run) {
                [strongSelf finishItem:nil];
            }
        });
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

// What GLM sends about every 0.57 s: a probe for monitors without a lease,
// the volume, then a poll to each monitor. No keep-alive: GLM sends 04 only
// in a group apply (captures/startup-idle, from 10 s). Identity a lost reply
// left unread is asked again. A cycle is skipped while the last one is
// still queued.
- (void)runCycle {
    if (!_running || _cycleQueued) {
        return;
    }
    _cycleQueued = YES;
    [self identifyAdapter];
    if (self.settings.discoversMonitors) {
        [self probe];
    }
    if (_volumeDecibels != nil) {
        [self sendVolume];
    }
    if (self.settings.discoversMonitors) {
        for (QLMMonitorRecord *monitor in [_monitors copy]) {
            [self identify:monitor];
            [self pollMonitor:monitor];
        }
    }
    [self afterSends:^{
        self->_cycleQueued = NO;
    }];
}

#pragma mark - Discovery and leases

- (uint8_t)takeSession {
    for (unsigned attempt = 0; attempt < 256; attempt++) {
        uint8_t candidate = _nextSession;
        _nextSession = (uint8_t)(candidate >= QLMAddressSessionLast ? QLMAddressSessionFirst : candidate + 1);
        if (!QLMAddressIsLeasable(candidate)) {
            continue;
        }
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
// Once no monitor answers, the new ones get the active group's blocks.
- (void)probe {
    [self send:QLMCommandProbe() then:^(const QLMMessage *reply, NSError *error) {
        uint8_t hardwareID[3];
        if (reply != NULL && QLMReplyHardwareID(reply, hardwareID)) {
            [self assignSessionTo:hardwareID];
        } else {
            [self applyToNewMonitors];
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
        if (reply != NULL && (!QLMReplySessionAck(reply, &acked) || acked != session)) {
            return;
        }
        // A lost ack may hide a lease the monitor took, and then it never
        // answers a probe again. So it is tracked anyway. If it holds the
        // lease its polls answer; if not, the next probe finds it.
        if (reply == NULL && !QLMSendWentOut(error)) {
            return;
        }
        // TRAP: a monitor just switched on plays at its own stored level
        // until a host sends one, and that can be loud
        // (captures/qlm-control-first/notes.md, after the capture).
        if (self->_volumeDecibels != nil) {
            [self enqueueNext:@[[self volumeItem]]];
        }
        QLMMonitorRecord *monitor = [[QLMMonitorRecord alloc] init];
        monitor.hardwareID = identity;
        monitor.session = session;
        monitor.lastReply = [NSDate date];
        [self->_monitors addObject:monitor];
        self->_dirty = YES;
        // Mute all holds for a monitor that first appears after it.
        if (self->_adapterMuted) {
            [self->_mutedIDs addObject:identity];
        }
        // A monitor may come back unmuted, so a muted one hears its state
        // after its first poll, as GLM sends it. One that gets a block
        // hears it after the block instead.
        monitor.configured = self->_activeGroup == nil;
        monitor.needsState = monitor.configured && [self->_mutedIDs containsObject:identity];
        [self identify:monitor];
        [self pollMonitor:monitor];
        [self probe];
    }];
}

// Asks for whichever of the system info and the serial is still unknown.
- (void)identify:(QLMMonitorRecord *)monitor {
    if (monitor.identifying || monitor.retrying || (monitor.systemInfo != nil && monitor.serialNumber != nil)) {
        return;
    }
    monitor.identifying = YES;
    if (monitor.systemInfo == nil) {
        [self ask:QLMCommandSystemInfo(monitor.session) then:^(const char *text) {
            monitor.systemInfo = @(text);
            char model[QLMPayloadMax];
            char firmware[QLMPayloadMax];
            if (QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware)) {
                monitor.model = @(model);
                monitor.firmwareVersion = firmware[0] != '\0' ? @(firmware) : nil;
            }
        }];
    }
    if (monitor.serialNumber == nil) {
        [self ask:QLMCommandSerialNumber(monitor.session) then:^(const char *text) {
            monitor.serialNumber = @(text);
        }];
    }
    [self afterSends:^{
        monitor.identifying = NO;
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

#pragma mark - The adapter

// The connection is lost, and the adapter that answers next may be another.
// Its identity and status are asked again. Queries already queued fill them
// from whichever adapter answers.
- (void)forgetAdapter {
    QLMTrackedAdapter *adapter = _adapterRecord;
    if (adapter.systemInfo == nil && adapter.serialNumber == nil && !adapter.hasStatus) {
        return;
    }
    adapter.systemInfo = nil;
    adapter.serialNumber = nil;
    adapter.model = nil;
    adapter.firmwareVersion = nil;
    adapter.hasStatus = NO;
    _dirty = YES;
}

- (void)identifyAdapter {
    QLMTrackedAdapter *adapter = _adapterRecord;
    if (adapter.identifying || (adapter.systemInfo != nil && adapter.serialNumber != nil)) {
        return;
    }
    adapter.identifying = YES;
    if (adapter.systemInfo == nil) {
        [self ask:QLMCommandSystemInfo(QLMAddressAdapter) then:^(const char *text) {
            adapter.systemInfo = @(text);
            char model[QLMPayloadMax];
            char firmware[QLMPayloadMax];
            if (QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware)) {
                adapter.model = @(model);
                adapter.firmwareVersion = firmware[0] != '\0' ? @(firmware) : nil;
            }
        }];
    }
    if (adapter.serialNumber == nil) {
        [self ask:QLMCommandSerialNumber(QLMAddressAdapter) then:^(const char *text) {
            adapter.serialNumber = @(text);
        }];
    }
    [self afterSends:^{
        adapter.identifying = NO;
    }];
}

// A pair of 01 08, unless the last pair is still queued. The reply carries
// the knob and the mic. Only a change to them publishes a snapshot.
- (void)pollAdapter {
    if (!_running || _adapterPollsQueued > 0) {
        return;
    }
    QLMTrackedAdapter *adapter = _adapterRecord;
    for (NSUInteger i = 0; i < QLMAdapterPollsPerRound; i++) {
        _adapterPollsQueued += 1;
        [self send:QLMCommandPoll(QLMAddressAdapter) then:^(const QLMMessage *reply, NSError *error) {
            self->_adapterPollsQueued -= 1;
            QLMAdapterStatus status;
            if (reply == NULL || QLMReplyAdapterStatus(reply, &status) != QLMAdapterStatusOK) {
                adapter.missedPolls += 1;
                self->_dirty = YES;
                return;
            }
            QLMAdapterStatus last = adapter.status;
            if (!adapter.hasStatus || adapter.missedPolls > 0 || QLMAdapterStatusDiffers(&last, &status)) {
                self->_dirty = YES;
            }
            adapter.status = status;
            adapter.hasStatus = YES;
            adapter.missedPolls = 0;
            adapter.lastReply = [NSDate date];
            [self followKnob:&status];
        }];
    }
}

// A volume the knob sets goes out as GLM sends it: the level three times,
// the mute state, then the level again (captures/standby-wake, 0.99 s).
- (void)followKnob:(const QLMAdapterStatus *)status {
    if (!status->knob || !status->hasKnobPosition) {
        [_knob reset];
        return;
    }
    NSNumber *volume = [_knob volumeForReading:status->knobTenths atTime:NSProcessInfo.processInfo.systemUptime volume:_volumeDecibels];
    if (volume == nil) {
        return;
    }
    _volumeDecibels = volume;
    _dirty = YES;
    for (int i = 0; i < 3; i++) {
        [self sendVolume];
    }
    [self sendMuteState];
    [self sendVolume];
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
    // GLM sends the state right after the poll (captures/startup-idle,
    // 9.861 s).
    if (monitor.needsState && monitor.isOn) {
        monitor.needsState = NO;
        QLMApplyMonitor *stated = [self applyMonitor:monitor];
        QLMApplySequence *sequence = [[QLMApplySequence alloc] initWithGroup:_activeGroup monitors:@[stated] adapterMuted:_adapterMuted];
        [self sendRecordsNext:[sequence stateOf:stated firstOfTwo:NO]];
    }
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

- (dispatch_block_t)volumeItem {
    _lastVolumeSend = [NSDate date];
    return [self itemSending:[self volumeMessage] then:nil];
}

- (void)sendVolume {
    [self enqueue:[self volumeItem]];
}

- (void)sendInputPair {
    [self sendRecords:[QLMApplySequence inputPair] then:nil];
}

#pragma mark - Dim

// GLM's dim: the level twice, one round of 2B, then broadcast 2D 00 and
// 3D 00 00 (captures/mute-dim, 51.24 s).
- (void)setDimmed:(BOOL)dimmed {
    [self onQueue:^{
        if (self->_dimmed == dimmed) {
            return;
        }
        self->_dimmed = dimmed;
        self->_dirty = YES;
        if (!self->_running || self->_volumeDecibels == nil) {
            return;
        }
        // Part of the sequence, so it skips the coalescing timer.
        [self sendVolume];
        [self sendVolume];
        [self sendMuteRounds:1];
        [self sendInputPair];
    }];
}

#pragma mark - Mute

- (void)setMuted:(BOOL)muted forMonitorWithHardwareID:(NSData *)hardwareID {
    NSData *identity = [hardwareID copy];
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        if (muted) {
            [self->_mutedIDs addObject:identity];
        } else {
            [self->_mutedIDs removeObject:identity];
        }
        self->_dirty = YES;
        QLMMonitorRecord *monitor = [self monitorWithHardwareID:identity];
        if (monitor != nil) {
            // A round reaches only a monitor that is on.
            monitor.needsState = monitor.needsState || !monitor.isOn;
            [self sendMuteRounds:2];
        }
    }];
}

- (void)recordMutedHardwareIDs:(NSSet<NSData *> *)hardwareIDs {
    NSSet<NSData *> *copied = [hardwareIDs copy];
    [self onQueue:^{
        [self->_mutedIDs unionSet:copied];
        self->_dirty = YES;
    }];
}

- (void)setAllMuted:(BOOL)muted {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        if (muted) {
            for (QLMMonitorRecord *monitor in self->_monitors) {
                [self->_mutedIDs addObject:monitor.hardwareID];
            }
        } else {
            [self->_mutedIDs removeAllObjects];
        }
        for (QLMMonitorRecord *monitor in self->_monitors) {
            monitor.needsState = monitor.needsState || !monitor.isOn;
        }
        self->_adapterMuted = muted;
        if (self->_volumeDecibels != nil) {
            // Part of the sequence, so it skips the coalescing timer.
            [self sendVolume];
        }
        [self sendMuteState];
    }];
}

// The adapter's own mute at 01, then two rounds to the monitors
// (captures/mute-dim, 46.19 s). Only mute all changes the adapter's.
- (void)sendMuteState {
    [self sendStateRecords:[[self sequenceFor:_activeGroup] muteState]];
}

// Each round restates the state of every monitor that is on, as
// QLMApplySequence says.
- (void)sendMuteRounds:(NSUInteger)rounds {
    [self sendStateRecords:[[self sequenceFor:_activeGroup] rounds:rounds]];
}

// A 2B reply is a bare ack, and a missed one is a lost send, not a missed
// poll.
- (void)sendStateRecords:(NSArray<NSData *> *)records {
    [self sendRecords:records then:nil];
    [self afterSends:^{
        self->_dirty = YES;
    }];
}

#pragma mark - Sequences

- (QLMApplyMonitor *)applyMonitor:(QLMMonitorRecord *)record {
    QLMApplyMonitor *monitor = [[QLMApplyMonitor alloc] initWithHardwareID:record.hardwareID session:record.session];
    monitor.on = record.isOn;
    monitor.muted = [_mutedIDs containsObject:record.hardwareID];
    return monitor;
}

// The monitors as GLM's sequences see them, in lease order.
- (QLMApplySequence *)sequenceFor:(nullable QLMSetupGroup *)group {
    NSMutableArray<QLMApplyMonitor *> *monitors = [NSMutableArray arrayWithCapacity:_monitors.count];
    for (QLMMonitorRecord *record in _monitors) {
        [monitors addObject:[self applyMonitor:record]];
    }
    return [[QLMApplySequence alloc] initWithGroup:group monitors:monitors adapterMuted:_adapterMuted];
}

// GLM's apply to the monitors leased since the active group was set, once
// the probe finds no more (captures/startup-idle, 8.534 s).
- (void)applyToNewMonitors {
    NSMutableArray<QLMMonitorRecord *> *fresh = [NSMutableArray array];
    for (QLMMonitorRecord *monitor in _monitors) {
        if (!monitor.configured) {
            monitor.configured = YES;
            [fresh addObject:monitor];
        }
    }
    if (_activeGroup != nil && fresh.count > 0) {
        [self configure:fresh then:nil];
    }
}

// Sends `fresh` their blocks, as GLM's apply at launch does. Then each one
// that got a block, or is muted, hears its state after its next poll.
- (void)configure:(NSArray<QLMMonitorRecord *> *)fresh then:(nullable QLMSendCompletion (^)(uint8_t address))completionFor {
    NSMutableArray<QLMApplyMonitor *> *monitors = [NSMutableArray arrayWithCapacity:fresh.count];
    for (QLMMonitorRecord *record in fresh) {
        record.configured = YES;
        [monitors addObject:[self applyMonitor:record]];
    }
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = _activeBlocks;
    [self sendRecords:[[self sequenceFor:_activeGroup] enumerationOf:monitors blocks:blocks] then:completionFor];
    [self afterSends:^{
        for (QLMMonitorRecord *monitor in fresh) {
            monitor.needsState = blocks[monitor.hardwareID] != nil || [self->_mutedIDs containsObject:monitor.hardwareID];
        }
    }];
}

#pragma mark - Power

// GLM's four steps, about 22 ms apart (captures/standby-wake, 34.86 s).
- (void)sleep {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        const QLMPowerStep steps[] = {QLMPowerStepStandbyPrepare, QLMPowerStepStandbyPrepare, QLMPowerStepPowerOff, QLMPowerStepPowerOff};
        for (size_t i = 0; i < sizeof steps / sizeof steps[0]; i++) {
            if (i > 0) {
                [self hold:QLMSleepStepSpacing];
            }
            [self send:QLMCommandPower(steps[i]) then:nil];
        }
    }];
}

// GLM's three pairs, back to back within a pair and about 0.2 s apart
// (captures/startup-idle, 7.33 s). Once a volume is set, it follows 0.235 s
// later, then broadcast 2D 00 and 3D 00 00 (captures/standby-wake, 47.24 s).
// A woken monitor keeps its own level until a host sends one
// (captures/qlm-control-first/notes.md). The monitors come back under new
// sessions, and the probe finds them.
- (void)wake {
    [self onQueue:^{
        if (!self->_running) {
            return;
        }
        for (int pair = 0; pair < 3; pair++) {
            if (pair > 0) {
                [self hold:QLMWakePairSpacing];
            }
            [self send:QLMCommandPower(QLMPowerStepWakeFirst) then:nil];
            [self send:QLMCommandPower(QLMPowerStepWakeSecond) then:nil];
        }
        if (self->_volumeDecibels != nil) {
            [self hold:QLMWakeVolumeDelay];
            [self sendVolume];
            [self sendInputPair];
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
        NSError *refusal = nil;
        NSDictionary<NSData *, QLMDSPBlock *> *blocks = [self checkGroup:group error:&refusal];
        if (blocks == nil) {
            finish(refusal);
            return;
        }
        [self sendGroup:group blocks:blocks finish:finish];
    }];
}

// Every check runs before the first frame. Every block a monitor can get
// must build at a verified rate, on or off, leased or not. On success, a
// block for every node, keyed by hardware ID.
- (nullable NSDictionary<NSData *, QLMDSPBlock *> *)checkGroup:(QLMSetupGroup *)group error:(NSError **)error {
    if (_applyFinish != nil) {
        *error = QLMSystemErrorMake(QLMSystemErrorAlreadyApplying, @"A group apply is already running.", nil);
        return nil;
    }
    if (!_running) {
        *error = QLMSystemErrorMake(QLMSystemErrorNotRunning, @"System is not running.", nil);
        return nil;
    }
    NSError *underlying = nil;
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = [QLMDSPBlock blocksByHardwareIDForGroup:group error:&underlying];
    if (blocks == nil) {
        *error = QLMSystemErrorMake(QLMSystemErrorBlocksFailed, @"The DSP blocks could not be built.", underlying);
        return nil;
    }
    for (QLMSetupNode *node in group.nodes) {
        QLMDSPBlock *block = node.hardwareID != nil ? blocks[node.hardwareID] : nil;
        if (block != nil && !block.rateVerified) {
            NSString *description = [NSString stringWithFormat:@"The design rate of node %@ (%@) is unverified.", node.serial, node.className];
            *error = QLMSystemErrorMake(QLMSystemErrorUnverifiedRate, description, nil);
            return nil;
        }
    }
    NSCountedSet<NSData *> *hardwareIDs = [[NSCountedSet alloc] initWithArray:[group.nodes valueForKey:@"hardwareID"]];
    for (QLMSetupNode *node in group.nodes) {
        BOOL single = node.hardwareID != nil && [hardwareIDs countForObject:node.hardwareID] == 1;
        if (node.on && (!single || [self monitorWithHardwareID:node.hardwareID] == nil)) {
            NSString *description = [NSString stringWithFormat:@"Node %@ matches no single leased monitor.", node.serial];
            *error = QLMSystemErrorMake(QLMSystemErrorUnknownMonitor, description, nil);
            return nil;
        }
    }
    if (_volumeDecibels == nil) {
        *error = QLMSystemErrorMake(QLMSystemErrorNoVolume, @"Set a volume before a group apply.", nil);
        return nil;
    }
    return blocks;
}

// The first apply is GLM's at launch: every monitor's block in turn. Each
// one after is GLM's group switch. Every frame is queued at once, so a cycle
// or an adapter poll waits behind them, as GLM's polls do
// (docs/adapter-status.md: its longest gap, 1.70 s).
- (void)sendGroup:(QLMSetupGroup *)group
           blocks:(NSDictionary<NSData *, QLMDSPBlock *> *)blocks
           finish:(void (^)(NSError *_Nullable error))finish {
    _applyFinish = finish;
    BOOL switching = _activeGroup != nil;
    _activeGroup = group;
    _activeBlocks = blocks;
    QLMApplySequence *sequence = [self sequenceFor:group];

    // A monitor that is on and stays in the group must ack every frame. One
    // told to prepare for standby, or woken from it, may miss them, as GLM's
    // do (captures/group-switch-main-4x2-main-2x1, 12.577 s).
    NSMutableSet<NSNumber *> *mustAck = [NSMutableSet setWithObject:@(QLMAddressAdapter)];
    for (QLMApplyMonitor *monitor in sequence.monitors) {
        if (monitor.on && (!switching || [sequence isMember:monitor])) {
            [mustAck addObject:@(monitor.session)];
        }
    }
    __block NSError *failure = nil;
    QLMSendCompletion wentOut = ^(const QLMMessage *reply, NSError *error) {
        if (failure == nil && error != nil && !QLMSendWentOut(error)) {
            failure = QLMSystemErrorMake(QLMSystemErrorSendFailed, @"A frame of the apply failed.", error);
        }
    };
    QLMSendCompletion acked = ^(const QLMMessage *reply, NSError *error) {
        wentOut(reply, error);
        if (failure == nil && reply == NULL) {
            failure = QLMSystemErrorMake(QLMSystemErrorSendFailed, @"A monitor did not ack a frame of the apply.", error);
        }
    };
    QLMSendCompletion (^completionFor)(uint8_t) = ^QLMSendCompletion(uint8_t address) {
        return [mustAck containsObject:@(address)] ? acked : wentOut;
    };

    if (switching) {
        _lastVolumeSend = [NSDate date];
        for (QLMMonitorRecord *monitor in _monitors) {
            monitor.configured = YES;
        }
        [self sendRecords:[sequence switchWithBlocks:blocks volume:[self volumeMessage]] then:completionFor];
    } else {
        [self configure:[_monitors copy] then:completionFor];
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

- (QLMAdapterState *)adapterState {
    QLMTrackedAdapter *adapter = _adapterRecord;
    QLMAdapterState *state = [[QLMAdapterState alloc] init];
    state.device = _adapter.deviceDescription;
    state.systemInfo = adapter.systemInfo;
    state.model = adapter.model;
    state.firmwareVersion = adapter.firmwareVersion;
    state.serialNumber = adapter.serialNumber;
    state.hasStatus = adapter.hasStatus;
    if (adapter.hasStatus) {
        QLMAdapterStatus status = adapter.status;
        state.knobPresent = status.knob;
        state.micPresent = status.mic;
        state.knobTenths = status.knob && status.hasKnobPosition ? @(status.knobTenths) : nil;
    }
    state.missedPolls = adapter.missedPolls;
    state.lastReply = adapter.lastReply;
    state.identified = state.systemInfo != nil && state.serialNumber != nil && state.hasStatus;
    return state;
}

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
        state.muted = [_mutedIDs containsObject:monitor.hardwareID];
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
    snapshot.adapter = [self adapterState];
    snapshot.adapterError = _adapterError;
    snapshot.monitors = states;
    snapshot.volumeDecibels = _volumeDecibels;
    snapshot.dimmed = _dimmed;
    snapshot.applying = _applyFinish != nil;
    snapshot.activeGroupName = _activeGroupName;
    snapshot.idle = [self isIdle];
    snapshot.allIdentified = allIdentified;
    snapshot.allMuted = allMuted;
    snapshot.mutedHardwareIDs = [_mutedIDs copy];
    snapshot.mutingAll = _adapterMuted;
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
