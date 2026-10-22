#import <Cocoa/Cocoa.h>

#import "QLMSetup.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

// The popover under the status item: volume, mute, dim, power, the group
// picker, and one line per monitor with its status dot and mute toggle. It
// reads snapshots and drives System. On the main queue.
@interface QLMPopoverController : NSViewController

- (instancetype)initWithSystem:(QLMSystem *)system;

// Nil disables the group picker.
@property (nonatomic, nullable) QLMSetup *setup;

// Stored, and shown while the popover is open or when it next opens.
- (void)showSnapshot:(QLMSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END
