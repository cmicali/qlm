#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol QLMTimer <NSObject>
// Once cancelled, the timer's block never runs again.
- (void)cancel;
@end

// Time, timers, and the hops between queues, for System and the adapters.
// The real clock is the system's uptime and GCD. A test's virtual clock
// moves only when the test advances it, and knows when the work a timer
// starts is done, so no test waits on the host's speed.
@protocol QLMClock <NSObject>

// Seconds, never going back.
@property (nonatomic, readonly) NSTimeInterval now;

// Runs the block on the queue, as dispatch_async does.
- (void)async:(dispatch_queue_t)queue run:(dispatch_block_t)block;
// Runs the block on the queue once, `seconds` from now.
- (id<QLMTimer>)after:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block;
// Runs the block on the queue every `seconds`, the first `seconds` from now.
- (id<QLMTimer>)every:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block;

@end

// The system's uptime, dispatch_after, and a GCD timer source with a tenth
// of its interval as leeway.
@interface QLMRealClock : NSObject <QLMClock>
@property (class, nonatomic, readonly) QLMRealClock *shared;
@end

NS_ASSUME_NONNULL_END
