#import "QLMReportLink.h"

@interface QLMReportLinkRequest : NSObject
@property (nonatomic) NSData *report;
@property (nonatomic) BOOL expectsReply;
@property (nonatomic, copy) QLMAdapterReplyHandler handler;
@end

@implementation QLMReportLinkRequest
@end

@implementation QLMReportLink {
    dispatch_queue_t _queue;
    QLMReportWriter _writer;
    QLMReportAssembly _assembly;
    QLMAdapterReplyHandler _waiting;
    // Ends a timer's claim: each wait for a reply, and each settle, has its own.
    uint64_t _generation;
    // A reply timed out and may still come. Until it does, or a timeout
    // passes, the next request is held, so it cannot take that reply.
    BOOL _settling;
    QLMReportLinkRequest *_held;
    NSError *_closed;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue writer:(QLMReportWriter)writer {
    self = [super init];
    if (self) {
        _queue = queue;
        _writer = [writer copy];
        _replyTimeout = 0.1;
        QLMReportAssemblyReset(&_assembly);
    }
    return self;
}

- (void)finish:(QLMAdapterReplyHandler)handler reply:(const QLMMessage *_Nullable)reply error:(NSError *_Nullable)error {
    BOOL answered = reply != NULL;
    QLMMessage copy = answered ? *reply : QLMMessageMake(0, NULL, 0);
    dispatch_async(_queue, ^{
        handler(answered ? &copy : NULL, error);
    });
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    if (_closed != nil) {
        [self finish:handler reply:NULL error:_closed];
        return;
    }
    uint8_t report[QLMReportLength];
    NSError *refusal = nil;
    if (!QLMAdapterPackReport(&message, report, &refusal)) {
        [self finish:handler reply:NULL error:refusal];
        return;
    }
    if (_waiting != nil || _held != nil) {
        NSAssert(NO, @"a send while another is in flight");
        [self finish:handler reply:NULL error:QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"A request was already in flight.")];
        return;
    }
    QLMReportLinkRequest *request = [[QLMReportLinkRequest alloc] init];
    request.report = [NSData dataWithBytes:report length:sizeof report];
    request.expectsReply = QLMReportExpectsReply(&message);
    request.handler = handler;
    if (_settling) {
        _held = request;
        return;
    }
    [self write:request];
}

// Runs the action after a timeout, unless the wait it belongs to has ended.
- (void)afterTimeout:(void (^)(QLMReportLink *link))action {
    uint64_t generation = _generation;
    __weak QLMReportLink *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_replyTimeout * (double)NSEC_PER_SEC)), _queue, ^{
        QLMReportLink *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_generation == generation) {
            action(strongSelf);
        }
    });
}

- (void)write:(QLMReportLinkRequest *)request {
    NSError *error = _writer(request.report.bytes);
    if (error != nil) {
        [self finish:request.handler reply:NULL error:error];
        return;
    }
    if (!request.expectsReply) {
        [self finish:request.handler reply:NULL error:nil];
        return;
    }
    QLMReportAssemblyReset(&_assembly);
    _waiting = request.handler;
    _generation += 1;
    [self afterTimeout:^(QLMReportLink *link) {
        [link timeOut];
    }];
}

// The request ends without its reply, which may yet come.
- (void)failWaiting:(NSError *)error {
    QLMAdapterReplyHandler handler = _waiting;
    _waiting = nil;
    QLMReportAssemblyReset(&_assembly);
    _settling = YES;
    _generation += 1;
    [self afterTimeout:^(QLMReportLink *link) {
        [link endSettling];
    }];
    [self finish:handler reply:NULL error:error];
}

- (void)timeOut {
    if (_waiting == nil) {
        return;
    }
    _timeouts += 1;
    [self failWaiting:QLMAdapterErrorMake(QLMAdapterErrorTimeout, @"The adapter did not answer.")];
}

- (void)endSettling {
    _settling = NO;
    _generation += 1;
    QLMReportLinkRequest *held = _held;
    _held = nil;
    if (held != nil) {
        [self write:held];
    }
}

- (void)receiveReport:(const uint8_t *)report length:(size_t)length {
    QLMMessage reply;
    QLMReportStatus status = QLMReportReadInput(&_assembly, report, length, &reply);
    if (status == QLMReportPending) {
        return;
    }
    if (_waiting == nil) {
        _strayReplies += 1;
        if (_settling) {
            [self endSettling];
        }
        return;
    }
    if (status != QLMReportOK && status != QLMReportNoAnswer) {
        [self failWaiting:QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"The adapter's reply did not read.")];
        return;
    }
    QLMAdapterReplyHandler handler = _waiting;
    _waiting = nil;
    _generation += 1;
    [self finish:handler reply:status == QLMReportOK ? &reply : NULL error:nil];
}

- (void)closeWithError:(NSError *)error {
    _closed = error;
    _settling = NO;
    _generation += 1;
    if (_waiting != nil) {
        QLMAdapterReplyHandler handler = _waiting;
        _waiting = nil;
        [self finish:handler reply:NULL error:error];
    }
    if (_held != nil) {
        [self finish:_held.handler reply:NULL error:error];
        _held = nil;
    }
}

@end
