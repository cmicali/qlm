#import "QLMReplayAdapter.h"

#include "QLMReplies.h"
#include "QLMReport.h"

@implementation QLMReplayAdapter {
    dispatch_queue_t _queue;
    // For each distinct output report, the indexes of its unplayed exchanges, in order.
    NSMutableDictionary<NSData *, NSMutableArray<NSNumber *> *> *_unplayed;
    NSMutableArray<NSData *> *_unmatched;
    NSUInteger _played;
}

- (instancetype)initWithCapture:(QLMCapture *)capture {
    self = [super init];
    if (self) {
        _capture = capture;
        _unmatched = [NSMutableArray array];
        _unplayed = [NSMutableDictionary dictionary];
        NSArray<QLMCaptureExchange *> *exchanges = capture.exchanges;
        for (NSUInteger i = 0; i < exchanges.count; i++) {
            NSData *report = exchanges[i].outputReport;
            NSMutableArray<NSNumber *> *indexes = _unplayed[report];
            if (indexes == nil) {
                indexes = [NSMutableArray array];
                _unplayed[report] = indexes;
            }
            [indexes addObject:@(i)];
        }
    }
    return self;
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

    uint8_t bytes[QLMReportLength];
    if (QLMReportPackOutput(&message, bytes) != QLMReportOK) {
        NSError *error = [NSError errorWithDomain:QLMAdapterErrorDomain code:QLMAdapterErrorForbidden userInfo:nil];
        dispatch_async(queue, ^{
            handler(NULL, error);
        });
        return;
    }
    NSData *report = [NSData dataWithBytes:bytes length:sizeof bytes];
    QLMCaptureExchange *exchange = nil;
    @synchronized(self) {
        NSMutableArray<NSNumber *> *indexes = _unplayed[report];
        if (indexes.count > 0) {
            exchange = _capture.exchanges[indexes.firstObject.unsignedIntegerValue];
            [indexes removeObjectAtIndex:0];
            _played += 1;
        } else {
            NSMutableData *record = [NSMutableData dataWithBytes:&message.address length:1];
            [record appendBytes:message.payload length:message.length];
            [_unmatched addObject:record];
        }
    }

    QLMMessage reply;
    memset(&reply, 0, sizeof reply);
    BOOL answered = NO;
    if (exchange != nil && exchange.hasReply) {
        reply = exchange.reply;
        answered = !QLMReplyIsNoAnswer(&reply);
    }
    dispatch_async(queue, ^{
        handler(answered ? &reply : NULL, nil);
    });
}

@end
