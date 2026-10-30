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
    dispatch_time_t _lastDue;
}

- (instancetype)initWithCapture:(QLMCapture *)capture {
    self = [super init];
    if (self) {
        _replyDelay = 0.001;
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
}

- (void)stop {
    [_link closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"stopped")];
}

- (void)answer:(NSData *)report {
    [_written addObject:report];
    QLMCaptureExchange *exchange = _unplayed[report].firstObject;
    if (exchange == nil) {
        _unmatchedReports += 1;
        return;
    }
    [_unplayed[report] removeObjectAtIndex:0];
    if (exchange.replyFrame == nil || self.silent) {
        return;
    }
    NSTimeInterval delay = self.replyDelay;
    if (self.nextReplyDelay > 0) {
        delay = self.nextReplyDelay;
        self.nextReplyDelay = 0;
    }
    dispatch_time_t due = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * (double)NSEC_PER_SEC));
    due = MAX(due, _lastDue);
    _lastDue = due;
    [_replies addObject:[QLMCaptureDevice inputReportsForFrame:exchange.replyFrame]];
    _repliesDue += 1;
    NSUInteger number = _repliesDue;
    __weak QLMCaptureDevice *weakSelf = self;
    dispatch_after(due, _queue, ^{
        [weakSelf deliverRepliesThrough:number];
    });
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
