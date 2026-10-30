#import <Cocoa/Cocoa.h>

#import "QLMMonitorList.h"
#import "QLMPreferences.h"
#import "QLMSetup.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMPopoverController;

@protocol QLMPopoverControllerDelegate <NSObject>
- (void)popoverControllerShowMonitors:(QLMPopoverController *)controller;
- (void)popoverControllerShowSettings:(QLMPopoverController *)controller;
- (void)popoverControllerShowFakeBus:(QLMPopoverController *)controller;
@end

// The popover under the status item: the adapter's error, volume, mute, dim,
// power, the group picker, and one line per monitor with its status dot and
// mute toggle. It reads snapshots and drives System. On the main queue.
@interface QLMPopoverController : NSViewController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList;

@property (nonatomic, weak, nullable) id<QLMPopoverControllerDelegate> delegate;
// The System it drives. A new one replaces it when the ceiling changes.
@property (nonatomic, nullable) QLMSystem *system;
// Nil disables the group picker.
@property (nonatomic, nullable) QLMSetup *setup;

// Draws the monitor list's snapshot while the popover is open. It draws
// again when it next opens.
- (void)refresh;

// Reads the volume range and the ceiling from the preferences again.
- (void)reloadVolumeRange;

@end

NS_ASSUME_NONNULL_END
