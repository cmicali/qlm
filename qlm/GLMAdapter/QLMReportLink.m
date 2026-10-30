#import "QLMReportLink.h"

#include "QLMCommands.h"
#include "QLMReplies.h"

// The shapes a sync can tell apart. A late reply of one shape is told from
// a sync's reply of the other.
typedef NS_ENUM(NSUInteger, QLMReplyShape) {
    QLMReplyShapeOther,
    QLMReplyShapeAdapterStatus,  // to 01 08
    QLMReplyShapeSystemInfo,     // to 39
};

static QLMReplyShape QLMReplyShapeFor(const QLMMessage *message) {
    if (message->address == QLMAddressAdapter && message->payload[0] == 0x08) {
        return QLMReplyShapeAdapterStatus;
    }
    return message->payload[0] == 0x39 ? QLMReplyShapeSystemInfo : QLMReplyShapeOther;
}

// A sync's reply queues behind the late one, so it waits longer.
static const NSUInteger QLMSyncTimeouts = 5;

@interface QLMReportLinkRequest : NSObject
@property (nonatomic) NSData *report;
@property (nonatomic) BOOL expectsReply;
@property (nonatomic) QLMReplyShape shape;
@property (nonatomic) BOOL sync;
@property (nonatomic, copy, nullable) QLMAdapterReplyHandler handler;  // nil for a sync
@end

@implementation QLMReportLinkRequest
@end

@implementation QLMReportLink {
    dispatch_queue_t _queue;
    QLMReportWriter _writer;
    QLMReportAssembly _assembly;
    QLMReportLinkRequest *_waiting;
    // Ends a timer's claim: each wait for a reply has its own.
    uint64_t _generation;
    // A reply timed out and may still come. Until a sync's reply comes, the
    // next request is held.
    BOOL _outOfStep;
    QLMReplyShape _lateShape;
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

// Through the allowlist, or nil with why not.
- (nullable QLMReportLinkRequest *)requestFor:(const QLMMessage *)message error:(NSError **)error {
    uint8_t report[QLMReportLength];
    if (!QLMAdapterPackReport(message, report, error)) {
        return nil;
    }
    QLMReportLinkRequest *request = [[QLMReportLinkRequest alloc] init];
    request.report = [NSData dataWithBytes:report length:sizeof report];
    request.expectsReply = QLMReportExpectsReply(message);
    request.shape = QLMReplyShapeFor(message);
    return request;
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    if (_closed != nil) {
        [self finish:handler reply:NULL error:_closed];
        return;
    }
    NSError *refusal = nil;
    QLMReportLinkRequest *request = [self requestFor:&message error:&refusal];
    if (request == nil) {
        [self finish:handler reply:NULL error:refusal];
        return;
    }
    if ((_waiting != nil && !_waiting.sync) || _held != nil) {
        NSAssert(NO, @"a send while another is in flight");
        [self finish:handler reply:NULL error:QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"A request was already in flight.")];
        return;
    }
    request.handler = handler;
    if (_outOfStep) {
        _held = request;
        if (_waiting == nil) {
            [self sync];
        }
        return;
    }
    [self write:request];
}

- (void)write:(QLMReportLinkRequest *)request {
    NSError *error = _writer(request.report.bytes);
    if (error != nil) {
        // A sync that did not go out fails the request it held. The next
        // send syncs again.
        QLMReportLinkRequest *failed = request.sync ? _held : request;
        if (request.sync) {
            _held = nil;
        }
        if (failed != nil) {
            [self finish:failed.handler reply:NULL error:error];
        }
        return;
    }
    if (!request.expectsReply) {
        [self finish:request.handler reply:NULL error:nil];
        return;
    }
    QLMReportAssemblyReset(&_assembly);
    _waiting = request;
    _generation += 1;
    uint64_t generation = _generation;
    NSTimeInterval timeout = request.sync ? _replyTimeout * QLMSyncTimeouts : _replyTimeout;
    __weak QLMReportLink *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * (double)NSEC_PER_SEC)), _queue, ^{
        QLMReportLink *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_generation == generation) {
            [strongSelf timeOut];
        }
    });
}

- (void)timeOut {
    if (_waiting == nil) {
        return;
    }
    _timeouts += 1;
    if (_waiting.sync) {
        [self fail];
        return;
    }
    [self loseReply:QLMAdapterErrorMake(QLMAdapterErrorTimeout, @"The adapter did not answer.")];
}

// The request in flight ends without its reply, which may still come.
- (void)loseReply:(NSError *)error {
    QLMReportLinkRequest *request = _waiting;
    _waiting = nil;
    _generation += 1;
    QLMReportAssemblyReset(&_assembly);
    _outOfStep = YES;
    _lateShape = request.shape;
    [self finish:request.handler reply:NULL error:error];
    [self sync];
}

// The adapter's status poll, or its system info after a status poll. GLM
// sends both.
- (void)sync {
    QLMMessage query = _lateShape == QLMReplyShapeAdapterStatus ? QLMCommandSystemInfo(QLMAddressAdapter)
                                                                 : QLMCommandPoll(QLMAddressAdapter);
    QLMReportLinkRequest *sync = [self requestFor:&query error:NULL];
    if (sync == nil) {
        NSAssert(NO, @"the allowlist refused a sync");
        return;
    }
    sync.sync = YES;
    [self write:sync];
}

// The sync's reply never came, so no reply can be matched to its request.
- (void)fail {
    NSError *error = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The GLM adapter stopped answering.");
    [self closeWithError:error];
    void (^handler)(NSError *) = _failureHandler;
    if (handler != nil) {
        dispatch_async(_queue, ^{
            handler(error);
        });
    }
}

- (void)receiveReport:(const uint8_t *)report length:(size_t)length {
    QLMMessage reply;
    QLMReportStatus status = QLMReportReadInput(&_assembly, report, length, &reply);
    if (status == QLMReportPending) {
        return;
    }
    QLMReportLinkRequest *request = _waiting;
    if (request == nil) {
        _strayReplies += 1;
        return;
    }
    if (request.sync) {
        BOOL answers = status == QLMReportOK && (request.shape == QLMReplyShapeAdapterStatus ? QLMReplyIsAdapterStatus(&reply)
                                                                                             : QLMReplyIsSystemInfo(&reply));
        if (!answers) {
            _strayReplies += 1;
            return;
        }
        // Replies come in order, so every late one has come or never will.
        _waiting = nil;
        _generation += 1;
        _outOfStep = NO;
        QLMReportLinkRequest *held = _held;
        _held = nil;
        if (held != nil) {
            [self write:held];
        }
        return;
    }
    if (status != QLMReportOK && status != QLMReportNoAnswer) {
        [self loseReply:QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"The adapter's reply did not read.")];
        return;
    }
    _waiting = nil;
    _generation += 1;
    [self finish:request.handler reply:status == QLMReportOK ? &reply : NULL error:nil];
}

- (void)closeWithError:(NSError *)error {
    _closed = error;
    _generation += 1;
    QLMReportLinkRequest *waiting = _waiting;
    _waiting = nil;
    if (waiting.handler != nil) {
        [self finish:waiting.handler reply:NULL error:error];
    }
    if (_held != nil) {
        [self finish:_held.handler reply:NULL error:error];
        _held = nil;
    }
}

@end
