#import "QLMReplayAdapter.h"

@implementation QLMReplayAdapter {
    dispatch_queue_t _queue;
    // For each distinct output report, its unplayed exchanges, in order.
    NSMutableDictionary<NSData *, NSMutableArray<QLMCaptureExchange *> *> *_unplayed;
    NSMutableArray<NSData *> *_unmatched;
    NSUInteger _played;
}

- (instancetype)initWithCapture:(QLMCapture *)capture {
    self = [super init];
    if (self) {
        _unmatched = [NSMutableArray array];
        _unplayed = [NSMutableDictionary dictionary];
        _clock = QLMRealClock.shared;
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

- (NSString *)deviceDescription {
    return @"a replay of a capture";
}

- (NSUInteger)playedCount {
    @synchronized(self) {
        return _played;
    }
}

- (NSArray<NSData *> *)unmatchedMessages {
    @synchronized(self) {
        return [_unmatched copy];
    }
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    _queue = queue;
}

- (void)stop {
    _queue = NULL;
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    dispatch_queue_t queue = _queue;
    NSAssert(queue != NULL, @"send before start");

    uint8_t report[QLMReportLength];
    NSError *refusal = nil;
    if (!QLMAdapterPackReport(&message, report, &refusal)) {
        [self.clock async:queue run:^{
            handler(NULL, refusal);
        }];
        return;
    }
    QLMCaptureExchange *exchange = nil;
    @synchronized(self) {
        NSMutableArray<QLMCaptureExchange *> *exchanges = _unplayed[[NSData dataWithBytes:report length:sizeof report]];
        exchange = exchanges.firstObject;
        if (exchange != nil) {
            [exchanges removeObjectAtIndex:0];
            _played += 1;
        } else {
            [_unmatched addObject:QLMAdapterRecord(&message)];
        }
    }

    BOOL answered = exchange.answered;
    QLMMessage reply = answered ? exchange.reply : QLMMessageMake(0, NULL, 0);
    [self.clock async:queue run:^{
        handler(answered ? &reply : NULL, nil);
    }];
}

@end
