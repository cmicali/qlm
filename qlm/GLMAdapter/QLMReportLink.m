#import "QLMReportLink.h"

#include "QLMCommands.h"
#include "QLMReplies.h"

// The shapes a reply can be told apart by. A sync asks for a shape that no
// late reply could have.
typedef NS_OPTIONS(NSUInteger, QLMReplyShape) {
    QLMReplyShapeOther = 1 << 0,
    QLMReplyShapeAdapterStatus = 1 << 1,  // to 01 08
    QLMReplyShapeSystemInfo = 1 << 2,     // to 39
};

static QLMReplyShape QLMReplyShapeFor(const QLMMessage *message) {
    if (message->address == QLMAddressAdapter && message->payload[0] == 0x08) {
        return QLMReplyShapeAdapterStatus;
    }
    return message->payload[0] == 0x39 ? QLMReplyShapeSystemInfo : QLMReplyShapeOther;
}

// A sync's reply queues behind the late one, so it has longer before the
// link stalls.
static const NSUInteger QLMSyncTimeouts = 5;

static NSError *QLMStalledError(void) {
    return QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The GLM adapter stopped answering.");
}

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
    // The shapes of replies that may still come. While any may, the link is
    // out of step, and the next request waits for a sync.
    QLMReplyShape _late;
    // Since an open, a reply to another host may still come, of any shape.
    BOOL _otherHostLate;
    // The sync is overdue. Every send fails until its reply comes.
    BOOL _stalled;
    QLMReportLinkRequest *_held;
    NSError *_closed;  // while the device is closed
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue writer:(QLMReportWriter)writer {
    self = [super init];
    if (self) {
        _queue = queue;
        _writer = [writer copy];
        _replyTimeout = 0.1;
        _otherHostLate = YES;
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
    if (_stalled) {
        [self finish:handler reply:NULL error:QLMStalledError()];
        return;
    }
    if ((_waiting != nil && !_waiting.sync) || _held != nil) {
        NSAssert(NO, @"a send while another is in flight");
        [self finish:handler reply:NULL error:QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"A request was already in flight.")];
        return;
    }
    request.handler = handler;
    if (_late != 0 || _otherHostLate) {
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
        [self stall];
        return;
    }
    [self loseReply:QLMAdapterErrorMake(QLMAdapterErrorTimeout, @"The adapter did not answer.")];
}

// Only the sync's reply can put the link back in step, so the link keeps
// waiting for it, however long, and fails every send meanwhile.
- (void)stall {
    _stalled = YES;
    QLMReportLinkRequest *held = _held;
    _held = nil;
    if (held != nil) {
        [self finish:held.handler reply:NULL error:QLMStalledError()];
    }
}

// The request in flight ends without its reply, which may still come.
- (void)loseReply:(NSError *)error {
    QLMReportLinkRequest *request = _waiting;
    _waiting = nil;
    _generation += 1;
    QLMReportAssemblyReset(&_assembly);
    _late |= request.shape;
    [self finish:request.handler reply:NULL error:error];
    [self sync];
}

// The adapter's status poll, or else its system info. GLM sends both.
// closeWithError: leaves at least one that no late reply could be taken for.
// Another host's late reply is likeliest a status, so after an open the
// system info goes first.
- (void)sync {
    BOOL statusLate = (_late & QLMReplyShapeAdapterStatus) != 0;
    BOOL infoLate = (_late & QLMReplyShapeSystemInfo) != 0;
    NSAssert(!statusLate || !infoLate, @"no sync is left");
    BOOL info = statusLate || (_otherHostLate && !infoLate);
    QLMMessage query = info ? QLMCommandSystemInfo(QLMAddressAdapter) : QLMCommandPoll(QLMAddressAdapter);
    QLMReportLinkRequest *sync = [self requestFor:&query error:NULL];
    if (sync == nil) {
        NSAssert(NO, @"the allowlist refused a sync");
        return;
    }
    sync.sync = YES;
    [self write:sync];
}

- (void)receiveReport:(const uint8_t *)report length:(size_t)length {
    if (_closed != nil) {
        return;
    }
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
        _waiting = nil;
        _generation += 1;
        _stalled = NO;
        if (_otherHostLate) {
            // This may have been the other host's reply, and then the sync's
            // own is late. A sync of the other shape drops it.
            _otherHostLate = NO;
            _late = request.shape;
            [self sync];
            return;
        }
        // Replies come in order, so every late one has come or never will.
        _late = 0;
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
    QLMReportLinkRequest *waiting = _waiting;
    _waiting = nil;
    _generation += 1;
    _stalled = NO;
    if (waiting != nil) {
        _late |= waiting.shape;
        // The other host's reply comes first, and may have either shape.
        if (_otherHostLate) {
            _late |= QLMReplyShapeAdapterStatus | QLMReplyShapeSystemInfo;
        }
        if (waiting.handler != nil) {
            [self finish:waiting.handler reply:NULL error:error];
        }
    }
    if (_held != nil) {
        [self finish:_held.handler reply:NULL error:error];
        _held = nil;
    }
    if ((_late & QLMReplyShapeAdapterStatus) != 0 && (_late & QLMReplyShapeSystemInfo) != 0) {
        _failure = QLMAdapterErrorMake(QLMAdapterErrorDisconnected,
                                       @"qlm lost track of the GLM adapter's replies. Unplug the adapter and plug it back in.");
    }
    _closed = _failure ?: error;
}

- (void)reopen {
    if (_failure != nil) {
        return;
    }
    _closed = nil;
    _otherHostLate = YES;
    QLMReportAssemblyReset(&_assembly);
}

@end
