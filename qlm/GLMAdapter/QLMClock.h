#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol QLMTimer <NSObject>
// Once cancelled, the timer's block never runs again.
- (void)cancel;
@end

// Time, timers, the hops between queues, and waits, for System, the
// adapters, and qlmctl. The real clock is the system's uptime and GCD. A
// test's virtual clock moves only when the test advances it or a caller
// waits on it, and knows when the work a timer starts is done, so no test
// waits on the host's speed.
@protocol QLMClock <NSObject>

// Seconds, never going back.
@property (nonatomic, readonly) NSTimeInterval now;

// Runs the block on the queue, as dispatch_async does.
- (void)async:(dispatch_queue_t)queue run:(dispatch_block_t)block;
// Runs the block on the queue once, `seconds` from now.
- (void)after:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block;
// Runs the block on the queue every `seconds`, the first `seconds` from now.
- (id<QLMTimer>)every:(NSTimeInterval)seconds queue:(dispatch_queue_t)queue run:(dispatch_block_t)block;
// Waits for the semaphore, at most `seconds`. NO when the time ran out.
- (BOOL)wait:(dispatch_semaphore_t)semaphore timeout:(NSTimeInterval)seconds;

@end

// The system's uptime, dispatch_after, and a GCD timer source with a tenth
// of its interval as leeway.
@interface QLMRealClock : NSObject <QLMClock>
@property (class, nonatomic, readonly) QLMRealClock *shared;
@end

NS_ASSUME_NONNULL_END
