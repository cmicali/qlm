#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Runs the block once, after the delay, on the main queue. The tests swap
// one in to run the block themselves.
typedef void (^QLMScheduler)(NSTimeInterval delay, dispatch_block_t block);

// dispatch_after on the main queue.
QLMScheduler QLMMainQueueScheduler(void);

NS_ASSUME_NONNULL_END
