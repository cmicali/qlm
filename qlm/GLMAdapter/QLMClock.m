#import "QLMClock.h"

#include <stdatomic.h>

// A dispatch_after that can be cancelled before it runs.
@interface QLMRealOnce : NSObject <QLMTimer>
@end

@implementation QLMRealOnce {
    atomic_bool _cancelled;
}

- (void)cancel {
    atomic_store(&_cancelled, true);
}

- (BOOL)cancelled {
    return atomic_load(&_cancelled);
}

@end

@interface QLMRealRepeat : NSObject <QLMTimer>
- (instancetype)initWithSource:(dispatch_source_t)source;
@end

@implementation QLMRealRepeat {
    dispatch_source_t _source;
}

- (instancetype)initWithSource:(dispatch_source_t)source {
    self = [super init];
    if (self) {
        _source = source;
    }
    return self;
}

- (void)cancel {
    dispatch_source_cancel(_source);
}

- (void)dealloc {
    dispatch_source_cancel(_source);
}

@end

@implementation QLMRealClock

+ (QLMRealClock *)shared {
    static QLMRealClock *clock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        clock = [[QLMRealClock alloc] init];
    });
    return clock;
}

- (NSTimeInterval)now {
    return NSProcessInfo.processInfo.systemUptime;
}

- (void)async:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    dispatch_async(queue, block);
}

- (id<QLMTimer>)after:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    QLMRealOnce *timer = [[QLMRealOnce alloc] init];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * (double)NSEC_PER_SEC)), queue, ^{
        if (![timer cancelled]) {
            block();
        }
    });
    return timer;
}

- (id<QLMTimer>)every:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block {
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    uint64_t interval = (uint64_t)(seconds * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval), interval, interval / 10);
    dispatch_source_set_event_handler(source, block);
    dispatch_resume(source);
    return [[QLMRealRepeat alloc] initWithSource:source];
}

- (BOOL)wait:(dispatch_semaphore_t)semaphore timeout:(NSTimeInterval)seconds {
    return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * (double)NSEC_PER_SEC))) == 0;
}

@end
