#import "QLMScheduler.h"

QLMScheduler QLMMainQueueScheduler(void) {
    return ^(NSTimeInterval delay, dispatch_block_t block) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
    };
}
