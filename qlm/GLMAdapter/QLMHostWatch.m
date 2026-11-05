#import "QLMHostWatch.h"

#import "QLMHostCheck.h"

const NSTimeInterval QLMHostWatchFallbackInterval = 30;

@implementation QLMHostWatch {
    dispatch_queue_t _queue;
    dispatch_queue_t _checkQueue;
    id<QLMClock> _clock;
    NSString *_Nullable (^_check)(void);
    void (^_found)(NSString *_Nullable host);
    id<QLMTimer> _fallback;
    BOOL _running;
    BOOL _checking;
    // An event came during a check, which may have read the state before it.
    BOOL _checkAgain;
    NSUInteger _run;  // a stop ends a check in flight
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                        clock:(id<QLMClock>)clock
                        check:(NSString *_Nullable (^)(void))check
                        found:(void (^)(NSString *_Nullable host))found {
    self = [super init];
    if (self) {
        _queue = queue;
        _clock = clock;
        _check = [check copy];
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
    _fallback = [_clock every:QLMHostWatchFallbackInterval queue:_queue run:^{
        [weakSelf requestCheck];
    }];
}

- (void)stop {
    _running = NO;
    _run += 1;
    _checking = NO;
    _checkAgain = NO;
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
        [weakSelf requestCheck];
    }];
}

- (void)requestCheck {
    if (!_running) {
        return;
    }
    if (_checking) {
        _checkAgain = YES;
        return;
    }
    _checking = YES;
    NSUInteger run = _run;
    dispatch_queue_t queue = _queue;
    id<QLMClock> clock = _clock;
    NSString *_Nullable (^check)(void) = _check;
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
    if (_checkAgain && _running) {
        _checkAgain = NO;
        [self requestCheck];
    }
}

@end
