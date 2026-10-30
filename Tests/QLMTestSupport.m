#import "QLMTestSupport.h"

#include <math.h>

#include "QLMReport.h"
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

BOOL QLMIsControl(QLMMessage message) {
    if (message.address == QLMAddressMulticast || message.length == 0) {
        return NO;
    }
    switch (message.payload[0]) {
    case 0x08:  // a poll
    case 0x19:  // a serial
    case 0x39:  // system info
    case 0xFE:  // the probe
        return NO;
    default:
        return YES;
    }
}

NSSet<NSData *> *QLMOutputReports(NSString *scenario, uint8_t opcode) {
    NSMutableSet<NSData *> *reports = [NSMutableSet set];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (message.length > 0 && message.payload[0] == opcode) {
            [reports addObject:exchange.outputReport];
        }
    }
    return reports;
}

@implementation XCTestCase (QLMCaptureRun)

- (nullable NSArray<QLMCaptureExchange *> *)qlm_frames:(NSUInteger)count
                                                     of:(NSString *)scenario
                                                   from:(NSTimeInterval)time
                                                   keep:(BOOL (*_Nullable)(QLMMessage))keep {
    NSMutableArray<QLMCaptureExchange *> *run = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        if (run.count == 0 && fabs(exchange.time - time) >= 0.0005) {
            continue;
        }
        if (keep != NULL && !keep(exchange.message)) {
            continue;
        }
        [run addObject:exchange];
        if (run.count == count) {
            return run;
        }
    }
    XCTFail(@"%@ has %lu of %lu frames from %.6f s", scenario, (unsigned long)run.count, (unsigned long)count, time);
    return nil;
}

- (void)qlm_assertExchange:(QLMCaptureExchange *)exchange is:(QLMMessage)message {
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&message, report), QLMReportOK, @"%.6f s", exchange.time);
    XCTAssertEqualObjects(exchange.outputReport, QLMBytes(report, sizeof report), @"%.6f s", exchange.time);
}

- (void)qlm_assertExchange:(QLMCaptureExchange *)exchange isExchange:(QLMCaptureExchange *)other {
    XCTAssertEqualObjects(exchange.outputReport, other.outputReport, @"%.6f s against %.6f s", exchange.time, other.time);
}

@end

@implementation QLMCaptureDevice {
    dispatch_queue_t _queue;
    id<QLMClock> _clock;
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

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    _queue = queue;
    _clock = clock;
    __weak QLMCaptureDevice *weakSelf = self;
    _link = [[QLMReportLink alloc] initWithQueue:queue clock:clock writer:^NSError *(const uint8_t *report) {
        [weakSelf answer:[NSData dataWithBytes:report length:QLMReportLength]];
        return nil;
    }];
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
    NSTimeInterval now = _clock.now;
    NSTimeInterval due = MAX(now + delay, _lastDue);
    _lastDue = due;
    [_replies addObject:[QLMCaptureDevice inputReportsForFrame:exchange.replyFrame]];
    _repliesDue += 1;
    NSUInteger number = _repliesDue;
    __weak QLMCaptureDevice *weakSelf = self;
    [_clock after:due - now queue:_queue run:^{
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

- (BOOL)qlm_send:(QLMMessage)message
              to:(id<QLMAdapter>)adapter
           queue:(dispatch_queue_t)queue
           clock:(QLMVirtualClock *)clock
           reply:(QLMMessage *)reply
           error:(NSError **)error {
    __block BOOL finished = NO;
    __block BOOL answered = NO;
    __block NSError *failure = nil;
    [clock async:queue run:^{
        [adapter sendMessage:message replyHandler:^(const QLMMessage *received, NSError *sendError) {
            if (received != NULL) {
                answered = YES;
                if (reply != NULL) {
                    *reply = *received;
                }
            }
            failure = sendError;
            finished = YES;
        }];
    }];
    XCTAssertTrue([clock runUntil:^BOOL {
        return finished;
    } within:60]);
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
    NSMutableArray<NSArray *> *_hops;  // queue, block
    dispatch_group_t _group;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _timers = [NSMutableArray array];
        _hops = [NSMutableArray array];
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
    @synchronized(self) {
        [_hops addObject:@[queue, [block copy]]];
    }
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

- (void)after:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    [self schedule:seconds period:0 queue:queue run:block];
}

- (id<QLMTimer>)every:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    return [self schedule:seconds period:seconds queue:queue run:block];
}

// In the group, or in place on the main queue from the main thread, which is
// the thread waiting on the group.
- (void)run:(dispatch_block_t)block on:(dispatch_queue_t)queue {
    if (queue == dispatch_get_main_queue() && NSThread.isMainThread) {
        block();
    } else {
        dispatch_group_async(_group, queue, block);
    }
}

// Runs the hops in rounds, each in the order they came, until none is left.
- (void)settle {
    for (;;) {
        if (dispatch_group_wait(_group, dispatch_time(DISPATCH_TIME_NOW, 30 * (int64_t)NSEC_PER_SEC)) != 0) {
            [NSException raise:NSInternalInconsistencyException format:@"the clock's work did not settle"];
        }
        NSArray<NSArray *> *hops;
        @synchronized(self) {
            hops = [_hops copy];
            [_hops removeAllObjects];
        }
        if (hops.count == 0) {
            return;
        }
        for (NSArray *hop in hops) {
            [self run:hop[1] on:hop[0]];
        }
    }
}

// The next timer due by `limit`, with now at its time. A one-shot is taken
// off. A repeating one moves on past now, so after a stall it runs once.
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
            while (next.due <= _now) {
                next.due += next.period;
            }
            next.order = _order++;
        } else {
            [_timers removeObject:next];
        }
        return next;
    }
}

// Runs the timer's block, unless it is cancelled, and settles.
- (void)fire:(QLMVirtualTimer *)timer {
    [self run:^{
        if (!timer.cancelled) {
            timer.block();
        }
    } on:timer.queue];
    [self settle];
}

- (BOOL)runUntil:(BOOL (^)(void))condition within:(NSTimeInterval)seconds {
    NSTimeInterval limit;
    @synchronized(self) {
        limit = _now + seconds;
    }
    [self settle];
    while (!condition()) {
        QLMVirtualTimer *timer = [self takeDueBy:limit];
        if (timer == nil) {
            @synchronized(self) {
                _now = MAX(_now, limit);
            }
            return NO;
        }
        [self fire:timer];
    }
    return YES;
}

- (void)advanceBy:(NSTimeInterval)seconds {
    [self runUntil:^BOOL {
        return NO;
    } within:seconds];
}

- (BOOL)wait:(dispatch_semaphore_t)semaphore timeout:(NSTimeInterval)seconds {
    return [self runUntil:^BOOL {
        return dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) == 0;
    } within:seconds];
}

- (void)stallFor:(NSTimeInterval)seconds {
    [self settle];
    NSTimeInterval end;
    @synchronized(self) {
        _now += seconds;
        end = _now;
    }
    QLMVirtualTimer *timer = nil;
    while ((timer = [self takeDueBy:end]) != nil) {
        [self fire:timer];
    }
}

@end
