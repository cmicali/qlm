#import "QLMReportLink.h"

#include "QLMCommands.h"
#include "QLMReplies.h"

// The shapes a reply can be told apart by. A sync asks for a shape that no
// late reply could have.
typedef NS_OPTIONS(NSUInteger, QLMReplyShape) {
    QLMReplyShapeOther = 1 << 0,
    QLMReplyShapeAdapterStatus = 1 << 1,  // to 01 08
    QLMReplyShapeSystemInfo = 1 << 2,     // to 39
    // Since an open: one reply to another host, of any shape, ahead of the
    // link's own. A status is likeliest, so the first sync treats it as one.
    QLMReplyShapeAny = 1 << 3,
};

// When both may be late, no sync is left.
static const QLMReplyShape QLMReplyShapeSyncs = QLMReplyShapeAdapterStatus | QLMReplyShapeSystemInfo;

static QLMReplyShape QLMReplyShapeFor(const QLMMessage *message) {
    if (message->address == QLMAddressAdapter && message->payload[0] == 0x08) {
        return QLMReplyShapeAdapterStatus;
    }
    return message->payload[0] == 0x39 ? QLMReplyShapeSystemInfo : QLMReplyShapeOther;
}

// A sync's reply queues behind the late one, so the first waits five
// timeouts before the link stalls. Each sync after it in a run waits twice
// as long as the one before, and a run writes at most four.
static const NSUInteger QLMSyncTimeouts = 5;
static const NSUInteger QLMSyncAttempts = 4;

static NSError *QLMStalledError(void) {
    return QLMAdapterErrorMake(QLMAdapterErrorUnresponsive, @"The GLM adapter stopped answering.");
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
    id<QLMClock> _clock;
    QLMReportWriter _writer;
    QLMReportAssembly _assembly;
    QLMReportLinkRequest *_waiting;
    // Ends a timer's claim: each wait for a reply has its own.
    uint64_t _generation;
    // The shapes of replies that may still come. While any may, the link is
    // out of step, and the next request waits for a sync.
    QLMReplyShape _late;
    // A sync is overdue. Every send fails until a sync's reply comes.
    BOOL _stalled;
    // The syncs written in this run, all of one shape, whose replies may
    // still come, and how many the run has tried.
    NSUInteger _syncsOut;
    NSUInteger _syncAttempts;
    QLMReportLinkRequest *_held;
    NSError *_closed;  // while the device is closed
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock writer:(QLMReportWriter)writer {
    self = [super init];
    if (self) {
        _queue = queue;
        _clock = clock;
        _writer = [writer copy];
        _replyTimeout = 0.1;
        _late = QLMReplyShapeAny;
        QLMReportAssemblyReset(&_assembly);
    }
    return self;
}

- (void)finish:(QLMAdapterReplyHandler)handler reply:(const QLMMessage *_Nullable)reply error:(NSError *_Nullable)error {
    BOOL answered = reply != NULL;
    QLMMessage copy = answered ? *reply : QLMMessageMake(0, NULL, 0);
    [_clock async:_queue run:^{
        handler(answered ? &copy : NULL, error);
    }];
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
    if (_late != 0) {
        _held = request;
        if (_waiting == nil) {
            [self sync];
        }
        return;
    }
    [self write:request];
}

// A request, not a sync.
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
    _waiting = request;
    [self after:_replyTimeout run:^(QLMReportLink *link) {
        link->_timeouts += 1;
        [link loseReply:QLMAdapterErrorMake(QLMAdapterErrorTimeout, @"The adapter did not answer.")];
    }];
}

// The block runs after `seconds`, unless a reply, a close, or another wait
// ends this one first.
- (void)after:(NSTimeInterval)seconds run:(void (^)(QLMReportLink *link))block {
    _generation += 1;
    uint64_t generation = _generation;
    __weak QLMReportLink *weakSelf = self;
    [_clock after:seconds queue:_queue run:^{
        QLMReportLink *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_generation == generation) {
            block(strongSelf);
        }
    }];
}

// The sync's reply is overdue, and may still come. The link stalls: it
// fails the held request, and every send, until a reply to one of its syncs
// comes. Meanwhile it sends more syncs of the same shape, in case a reply
// was lost. That shape stays safe, since no late reply but a sync's own can
// have it.
- (void)syncOverdue {
    _timeouts += 1;
    if (!_stalled) {
        _stalled = YES;
        QLMReportLinkRequest *held = _held;
        _held = nil;
        if (held != nil) {
            [self finish:held.handler reply:NULL error:QLMStalledError()];
        }
    }
    if (_syncAttempts < QLMSyncAttempts) {
        [self writeSync:_waiting.shape];
    }
}

// One sync of the run's shape. A sync that did not go out fails the request
// it held. With none out, the next send syncs again. Otherwise the link
// waits on for the others, and tries again in turn.
- (void)writeSync:(QLMReplyShape)shape {
    QLMMessage query = shape == QLMReplyShapeSystemInfo ? QLMCommandSystemInfo(QLMAddressAdapter) : QLMCommandPoll(QLMAddressAdapter);
    QLMReportLinkRequest *sync = [self requestFor:&query error:NULL];
    if (sync == nil) {
        NSAssert(NO, @"the allowlist refused a sync");
        return;
    }
    sync.sync = YES;
    _syncAttempts += 1;
    NSTimeInterval wait = _replyTimeout * QLMSyncTimeouts * (double)(1u << (_syncAttempts - 1));
    NSError *error = _writer(sync.report.bytes);
    if (error != nil) {
        QLMReportLinkRequest *held = _held;
        _held = nil;
        if (held != nil) {
            [self finish:held.handler reply:NULL error:error];
        }
        if (_syncsOut == 0) {
            _syncAttempts = 0;
            return;
        }
    } else {
        QLMReportAssemblyReset(&_assembly);
        _waiting = sync;
        _syncsOut += 1;
    }
    [self after:wait run:^(QLMReportLink *link) {
        [link syncOverdue];
    }];
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

// Starts a run of syncs: the adapter's status poll, or else its system info.
// GLM sends both. closeWithError: leaves at least one that no late reply
// could be taken for.
- (void)sync {
    NSAssert((_late & QLMReplyShapeSyncs) != QLMReplyShapeSyncs, @"no sync is left");
    BOOL info = (_late & QLMReplyShapeSystemInfo) == 0 && (_late & (QLMReplyShapeAdapterStatus | QLMReplyShapeAny)) != 0;
    _syncsOut = 0;
    _syncAttempts = 0;
    [self writeSync:info ? QLMReplyShapeSystemInfo : QLMReplyShapeAdapterStatus];
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
        BOOL another = _syncsOut > 1 || (_late & QLMReplyShapeAny) != 0;
        _waiting = nil;
        _generation += 1;
        _stalled = NO;
        _syncsOut = 0;
        _syncAttempts = 0;
        if (another) {
            // This may have been an earlier sync's reply, or the other
            // host's, and then a later one of this shape may still come.
            // Every reply ahead of them has come or never will, so a sync of
            // the other shape drops the rest.
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
    _syncsOut = 0;
    _syncAttempts = 0;
    if (waiting != nil) {
        // Every sync of a run has the waiting one's shape.
        _late |= waiting.shape;
        // The other host's reply comes first, and may have either shape.
        if ((_late & QLMReplyShapeAny) != 0) {
            _late |= QLMReplyShapeSyncs;
        }
        if (waiting.handler != nil) {
            [self finish:waiting.handler reply:NULL error:error];
        }
    }
    if (_held != nil) {
        [self finish:_held.handler reply:NULL error:error];
        _held = nil;
    }
    if ((_late & QLMReplyShapeSyncs) == QLMReplyShapeSyncs) {
        _failure = QLMAdapterErrorMake(QLMAdapterErrorLostTrack,
                                       @"qlm lost track of the GLM adapter's replies. Unplug the adapter and plug it back in.");
    }
    _closed = _failure ?: error;
}

- (void)reopen {
    if (_failure != nil) {
        return;
    }
    _closed = nil;
    _late |= QLMReplyShapeAny;
    QLMReportAssemblyReset(&_assembly);
}

@end
