#import "QLMTestSupport.h"

#import "QLMReportLink.h"
#import "QLMSetupReader.h"

NSData *QLMBytes(const uint8_t *bytes, size_t length) {
    return [NSData dataWithBytes:bytes length:length];
}

NSString *QLMFixturePath(NSString *name) {
    NSString *tests = [@(__FILE__) stringByDeletingLastPathComponent];
    return [[tests stringByAppendingPathComponent:@"Setups/Fixtures"] stringByAppendingPathComponent:name];
}

static NSString *QLMCapturesDirectory(void) {
    NSString *tests = [@(__FILE__) stringByDeletingLastPathComponent];
    return [[tests stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"captures"];
}

NSArray<NSString *> *QLMCaptureScenarios(void) {
    NSString *directory = QLMCapturesDirectory();
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *scenarios = [NSMutableArray array];
    for (NSString *name in [manager contentsOfDirectoryAtPath:directory error:NULL]) {
        NSString *reports = [[directory stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"reports.txt"];
        if ([manager fileExistsAtPath:reports]) {
            [scenarios addObject:name];
        }
    }
    return [scenarios sortedArrayUsingSelector:@selector(compare:)];
}

QLMCapture *QLMReadCapture(NSString *scenario, NSError **error) {
    static NSMutableDictionary<NSString *, QLMCapture *> *captures;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        captures = [NSMutableDictionary dictionary];
    });
    @synchronized(captures) {
        QLMCapture *capture = captures[scenario];
        if (capture == nil) {
            NSString *path = [[QLMCapturesDirectory() stringByAppendingPathComponent:scenario] stringByAppendingPathComponent:@"reports.txt"];
            capture = [QLMCapture captureWithContentsOfFile:path error:error];
            if (capture != nil) {
                captures[scenario] = capture;
            }
        }
        return capture;
    }
}

@implementation QLMCaptureDevice {
    dispatch_queue_t _queue;
    NSMutableDictionary<NSData *, NSMutableArray<QLMCaptureExchange *> *> *_unplayed;
    NSMutableArray<NSData *> *_written;
    NSMutableArray<NSArray<NSData *> *> *_replies;  // due, in order
    NSUInteger _repliesDue;
    NSTimeInterval _lastDue;  // on the clock
}

- (instancetype)initWithCapture:(QLMCapture *)capture {
    self = [super init];
    if (self) {
        _replyDelay = 0.001;
        _clock = QLMRealClock.shared;
        _lastDue = -INFINITY;
        _written = [NSMutableArray array];
        _replies = [NSMutableArray array];
        _unplayed = [NSMutableDictionary dictionary];
        for (QLMCaptureExchange *exchange in capture.exchanges) {
            NSMutableArray<QLMCaptureExchange *> *same = _unplayed[exchange.outputReport];
            if (same == nil) {
                same = [NSMutableArray array];
                _unplayed[exchange.outputReport] = same;
            }
            [same addObject:exchange];
        }
    }
    return self;
}

+ (NSArray<NSData *> *)inputReportsForFrame:(NSData *)frame {
    NSMutableArray<NSData *> *reports = [NSMutableArray array];
    const uint8_t *bytes = frame.bytes;
    for (NSUInteger offset = 0; offset < frame.length; offset += QLMReportFrameMax) {
        uint8_t report[QLMReportLength] = {QLMReportInputPrefix};
        NSUInteger count = MIN((NSUInteger)QLMReportFrameMax, frame.length - offset);
        memcpy(report + 1, bytes + offset, count);
        [reports addObject:[NSData dataWithBytes:report length:sizeof report]];
    }
    return reports;
}

- (NSString *)deviceDescription {
    return @"a capture, report by report";
}

- (NSArray<NSData *> *)writtenReports {
    return [_written copy];
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    _queue = queue;
    __weak QLMCaptureDevice *weakSelf = self;
    _link = [[QLMReportLink alloc] initWithQueue:queue writer:^NSError *(const uint8_t *report) {
        [weakSelf answer:[NSData dataWithBytes:report length:QLMReportLength]];
        return nil;
    }];
    _link.clock = self.clock;
}

- (void)stop {
    [_link closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"stopped")];
}

- (void)answer:(NSData *)report {
    [_written addObject:report];
    NSMutableArray<QLMCaptureExchange *> *same = _unplayed[report];
    QLMCaptureExchange *exchange = same.firstObject;
    if (exchange == nil) {
        _unmatchedReports += 1;
        return;
    }
    if (same.count > 1) {
        [same removeObjectAtIndex:0];
    }
    if (exchange.replyFrame == nil || self.silent) {
        return;
    }
    NSTimeInterval delay = self.replyDelay;
    if (self.nextReplyDelay > 0) {
        delay = self.nextReplyDelay;
        self.nextReplyDelay = 0;
    }
    NSTimeInterval now = self.clock.now;
    NSTimeInterval due = MAX(now + delay, _lastDue);
    _lastDue = due;
    [_replies addObject:[QLMCaptureDevice inputReportsForFrame:exchange.replyFrame]];
    _repliesDue += 1;
    NSUInteger number = _repliesDue;
    __weak QLMCaptureDevice *weakSelf = self;
    [self.clock after:due - now queue:_queue run:^{
        [weakSelf deliverRepliesThrough:number];
    }];
}

// The replies ahead of this one are due too, since none is due before them.
- (void)deliverRepliesThrough:(NSUInteger)number {
    while (_deliveredReplies < number) {
        NSArray<NSData *> *inputs = _replies.firstObject;
        [_replies removeObjectAtIndex:0];
        _deliveredReplies += 1;
        for (NSData *input in inputs) {
            [_link receiveReport:input.bytes length:input.length];
        }
    }
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    [_link sendMessage:message replyHandler:handler];
}

@end

@implementation XCTestCase (QLMAdapter)

- (BOOL)qlm_send:(QLMMessage)message to:(id<QLMAdapter>)adapter queue:(dispatch_queue_t)queue reply:(QLMMessage *)reply
           error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL answered = NO;
    __block NSError *failure = nil;
    dispatch_async(queue, ^{
        [adapter sendMessage:message replyHandler:^(const QLMMessage *received, NSError *sendError) {
            if (received != NULL) {
                answered = YES;
                if (reply != NULL) {
                    *reply = *received;
                }
            }
            failure = sendError;
            dispatch_semaphore_signal(done);
        }];
    });
    XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    if (error != NULL) {
        *error = failure;
    }
    return answered;
}

@end

QLMSetupGroup *QLMFixtureGroup(NSString *name) {
    for (QLMSetupGroup *group in QLMReadFixtureSetup().groups) {
        if ([group.name isEqualToString:name]) {
            return group;
        }
    }
    return nil;
}

@implementation QLMApplyFilter {
    NSMutableSet<NSNumber *> *_prepared;
    BOOL _cycleVolumeDue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _prepared = [NSMutableSet set];
    }
    return self;
}

- (BOOL)keeps:(NSData *)record {
    const uint8_t *bytes = record.bytes;
    uint8_t address = bytes[0];
    uint8_t opcode = bytes[1];
    if (record.length == 2 && opcode == 0x08) {
        return NO;
    }
    BOOL probing = (address == QLMAddressBroadcast && opcode == 0xFE) || (address == QLMAddressMulticast && opcode == 0x02);
    // The cycle's volume is its first after its probe, though the apply's
    // frames may come between.
    BOOL cycleVolume = _cycleVolumeDue && address == QLMAddressBroadcast && opcode == 0x1F;
    _cycleVolumeDue = probing || (_cycleVolumeDue && !cycleVolume);
    if (opcode == 0x17) {
        [_prepared addObject:@(address)];
    }
    BOOL identifying = opcode == 0x39 || (opcode == 0x19 && record.length == 3);
    return !probing && !cycleVolume && !(identifying && ![_prepared containsObject:@(address)]);
}

@end

QLMSetup *QLMReadFixtureSetup(void) {
    static QLMSetup *setup;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *error = nil;
        setup = [QLMSetupReader readFileAtPath:QLMFixturePath(@"Main.sam") error:&error];
        NSCAssert(setup != nil, @"the fixture does not parse: %@", error);
    });
    return setup;
}

@interface QLMVirtualTimer : NSObject <QLMTimer>
@property (nonatomic) NSTimeInterval due;
@property (nonatomic) NSTimeInterval period;  // 0 for once
@property (nonatomic) NSUInteger order;
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic, copy) dispatch_block_t block;
@property (atomic) BOOL cancelled;
@end

@implementation QLMVirtualTimer

- (void)cancel {
    self.cancelled = YES;
}

@end

@implementation QLMVirtualClock {
    NSTimeInterval _now;
    NSUInteger _order;
    NSMutableArray<QLMVirtualTimer *> *_timers;
    dispatch_group_t _group;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _timers = [NSMutableArray array];
        _group = dispatch_group_create();
    }
    return self;
}

- (NSTimeInterval)now {
    @synchronized(self) {
        return _now;
    }
}

- (void)async:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    dispatch_group_async(_group, queue, block);
}

- (id<QLMTimer>)schedule:(NSTimeInterval)seconds period:(NSTimeInterval)period queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    QLMVirtualTimer *timer = [[QLMVirtualTimer alloc] init];
    timer.period = period;
    timer.queue = queue;
    timer.block = block;
    @synchronized(self) {
        timer.due = _now + seconds;
        timer.order = _order++;
        [_timers addObject:timer];
    }
    return timer;
}

- (id<QLMTimer>)after:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    return [self schedule:seconds period:0 queue:queue run:block];
}

- (id<QLMTimer>)every:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    return [self schedule:seconds period:seconds queue:queue run:block];
}

- (BOOL)settle {
    return dispatch_group_wait(_group, dispatch_time(DISPATCH_TIME_NOW, 30 * (int64_t)NSEC_PER_SEC)) == 0;
}

// The next timer due by `limit`, taken off or moved on, with now at its time.
- (nullable QLMVirtualTimer *)takeDueBy:(NSTimeInterval)limit {
    @synchronized(self) {
        [_timers filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(QLMVirtualTimer *timer, NSDictionary *bindings) {
            return !timer.cancelled;
        }]];
        QLMVirtualTimer *next = nil;
        for (QLMVirtualTimer *timer in _timers) {
            if (timer.due <= limit && (next == nil || timer.due < next.due || (timer.due == next.due && timer.order < next.order))) {
                next = timer;
            }
        }
        if (next == nil) {
            return nil;
        }
        _now = MAX(_now, next.due);
        if (next.period > 0) {
            next.due += next.period;
            next.order = _order++;
        } else {
            [_timers removeObject:next];
        }
        return next;
    }
}

- (void)advanceBy:(NSTimeInterval)seconds {
    NSTimeInterval limit;
    @synchronized(self) {
        limit = _now + seconds;
    }
    NSAssert([self settle], @"work did not settle");
    QLMVirtualTimer *timer = nil;
    while ((timer = [self takeDueBy:limit]) != nil) {
        QLMVirtualTimer *fired = timer;
        dispatch_group_async(_group, fired.queue, ^{
            if (!fired.cancelled) {
                fired.block();
            }
        });
        NSAssert([self settle], @"work did not settle");
    }
    @synchronized(self) {
        _now = MAX(_now, limit);
    }
}

@end
