#import <Cocoa/Cocoa.h>

#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

// The popover under the status item: volume, mute, dim, and one line per
// monitor with its status dot. It reads snapshots and drives System.
@interface QLMPopoverController : NSViewController

- (instancetype)initWithSystem:(QLMSystem *)system;

// On the main queue.
- (void)showSnapshot:(QLMSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END
