#import <Cocoa/Cocoa.h>

#import "QLMMonitorList.h"

NS_ASSUME_NONNULL_BEGIN

// The window with each monitor's detail: status and power, model, serial,
// firmware, temperature, the approximate meters, and the last reply. The
// adapter is above them. It only reads. On the main queue.
@interface QLMMonitorsWindowController : NSWindowController

- (instancetype)initWithMonitorList:(QLMMonitorList *)monitorList;

// Draws the monitor list's snapshot while any of the window is on screen.
// It draws again when it next comes into view.
- (void)refresh;
// Draws the latest snapshot while the window is open, seen or not, for a
// debug verb that reads what the window shows.
- (void)drawWhileOpen;

@end

NS_ASSUME_NONNULL_END
