#import <Cocoa/Cocoa.h>

#import "QLMMonitorList.h"

NS_ASSUME_NONNULL_BEGIN

// The window with each monitor's detail: status and power, model, serial,
// firmware, temperature, the approximate meters, and the last reply. The
// adapter is above them. It only reads. On the main queue.
@interface QLMMonitorsWindowController : NSWindowController

- (instancetype)initWithMonitorList:(QLMMonitorList *)monitorList;

// Draws the monitor list's snapshot while the window is open. It draws again
// when it next opens.
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
