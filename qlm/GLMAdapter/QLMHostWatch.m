#import "QLMHostWatch.h"

#import "QLMHostCheck.h"

const NSTimeInterval QLMHostWatchClientInterval = 1;
const NSTimeInterval QLMHostWatchFallbackInterval = 30;

typedef NS_ENUM(NSInteger, QLMHostWatchCheck) {
    QLMHostWatchCheckNone = 0,
    QLMHostWatchCheckClients,
    QLMHostWatchCheckFull,
};

@implementation QLMHostWatch {
    dispatch_queue_t _queue;
    dispatch_queue_t _checkQueue;
    id<QLMClock> _clock;
    NSString *_Nullable (^_check)(void);
    NSString *_Nullable (^_clientCheck)(void);
    void (^_found)(NSString *_Nullable host);
    id<QLMTimer> _clientTimer;
    id<QLMTimer> _fallback;
    BOOL _running;
    BOOL _checking;
    // What an event during a check asked for, since the check may have read
    // the state before it.
    QLMHostWatchCheck _again;
    NSUInteger _run;  // a stop ends a check in flight
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                        clock:(id<QLMClock>)clock
                        check:(NSString *_Nullable (^)(void))check
                  clientCheck:(NSString *_Nullable (^)(void))clientCheck
                        found:(void (^)(NSString *_Nullable host))found {
    self = [super init];
    if (self) {
        _queue = queue;
        _clock = clock;
        _check = [check copy];
        _clientCheck = [clientCheck copy];
        _found = [found copy];
        _checkQueue = dispatch_queue_create("com.commonwealthrecordings.qlm.hostcheck", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    if (_running) {
        return;
    }
    _running = YES;
    __weak QLMHostWatch *weakSelf = self;
    _clientTimer = [_clock every:QLMHostWatchClientInterval queue:_queue run:^{
        [weakSelf request:QLMHostWatchCheckClients];
    }];
    _fallback = [_clock every:QLMHostWatchFallbackInterval queue:_queue run:^{
        [weakSelf request:QLMHostWatchCheckFull];
    }];
}

- (void)stop {
    _running = NO;
    _run += 1;
    _checking = NO;
    _again = QLMHostWatchCheckNone;
    [_clientTimer cancel];
    _clientTimer = nil;
    [_fallback cancel];
    _fallback = nil;
}

- (void)appChangedAtPath:(NSString *)executablePath {
    if (QLMHostCheckIsGLMExecutable(executablePath)) {
        [self adapterChanged];
    }
}

- (void)adapterChanged {
    __weak QLMHostWatch *weakSelf = self;
    [_clock async:_queue run:^{
        [weakSelf request:QLMHostWatchCheckFull];
    }];
}

- (void)request:(QLMHostWatchCheck)kind {
    if (!_running) {
        return;
    }
    if (_checking) {
        _again = MAX(_again, kind);
        return;
    }
    _checking = YES;
    NSUInteger run = _run;
    dispatch_queue_t queue = _queue;
    id<QLMClock> clock = _clock;
    NSString *_Nullable (^check)(void) = kind == QLMHostWatchCheckFull ? _check : _clientCheck;
    __weak QLMHostWatch *weakSelf = self;
    // The process scan takes milliseconds, so it runs off the adapter's queue.
    [clock async:_checkQueue run:^{
        NSString *host = check();
        [clock async:queue run:^{
            [weakSelf finishCheck:host run:run];
        }];
    }];
}

- (void)finishCheck:(nullable NSString *)host run:(NSUInteger)run {
    if (!_running || run != _run) {
        return;
    }
    _checking = NO;
    _found(host);
    QLMHostWatchCheck again = _again;
    _again = QLMHostWatchCheckNone;
    if (again != QLMHostWatchCheckNone) {
        [self request:again];
    }
}

@end
