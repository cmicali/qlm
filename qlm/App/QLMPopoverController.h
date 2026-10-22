#import <Cocoa/Cocoa.h>

#import "QLMSetup.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

// The popover under the status item: volume, mute, dim, power, the group
// picker, and one line per monitor with its status dot and mute toggle. It
// reads snapshots and drives System.
@interface QLMPopoverController : NSViewController

// A nil setup disables the group picker.
- (instancetype)initWithSystem:(QLMSystem *)system setup:(nullable QLMSetup *)setup;

// On the main queue.
- (void)showSnapshot:(QLMSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END
