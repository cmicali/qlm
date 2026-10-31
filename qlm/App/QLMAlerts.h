#import <Foundation/Foundation.h>

#import "QLMMonitorList.h"

NS_ASSUME_NONNULL_BEGIN

// Posts through UNUserNotificationCenter. The first alert asks the user
// for permission. A process with no bundle, such as a harness, has no
// center, so it logs. On the main queue.
@interface QLMNotifier : NSObject

// A newer notification with the same identifier replaces it.
- (void)postIdentifier:(NSString *)identifier title:(NSString *)title body:(NSString *)body;

@end

// Turns the monitor list's updates into alerts: a monitor System drops, one
// that runs hot at 70 °C, and an adapter that stops answering while its
// take-over may make the monitors louder. Each monitor gets at most one
// alert of each kind every 10 minutes. While System is stopped or the
// adapter is refused, a drop says nothing: the banner covers it. On the
// main queue.
@interface QLMMonitorAlerts : NSObject

- (instancetype)initWithNotifier:(QLMNotifier *)notifier;

// Call after each of the list's updates.
- (void)updateWithMonitorList:(QLMMonitorList *)list;

@end

NS_ASSUME_NONNULL_END
