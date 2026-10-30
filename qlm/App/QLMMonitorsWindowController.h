#import <Cocoa/Cocoa.h>

#import "QLMMonitorList.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The window with each monitor's detail: status and power, model, serial,
// firmware, temperature, the approximate meters, and the last reply. The
// adapter is above them. It only reads. On the main queue.
@interface QLMMonitorsWindowController : NSWindowController

- (instancetype)init;

// Stored, and shown while the window is open or when it next opens.
- (void)showSnapshot:(QLMSnapshot *)snapshot monitors:(NSArray<QLMMonitorEntry *> *)monitors;

@end

NS_ASSUME_NONNULL_END
