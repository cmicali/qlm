#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// At or above it, a monitor runs hot. In standby the user's monitors read
// 29 to 47 °C (qlm-standby-discover).
extern const NSInteger QLMHotTemperature;      // 70 °C
// A hot monitor may alert again only once it cools this far below.
extern const NSInteger QLMHotHysteresis;       // 5 °C
// Between two alerts of one kind for one monitor, at least this long.
extern const NSTimeInterval QLMAlertInterval;  // 10 min

// One notification. A newer one with the same identifier replaces it.
typedef void (^QLMAlertPoster)(NSString *identifier, NSString *title, NSString *body);

// Turns snapshots into alerts: a monitor System drops, and one that runs
// hot. While System is stopped or the adapter is refused, a drop says
// nothing: the banner covers it. On the main queue.
@interface QLMMonitorAlerts : NSObject

- (instancetype)initWithPoster:(QLMAlertPoster)poster;

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot;

@end

// Posts through UNUserNotificationCenter. The first alert asks the user
// for permission. A process with no bundle, such as a harness, has no
// center, so it logs. On the main queue.
@interface QLMNotifier : NSObject

- (void)postIdentifier:(NSString *)identifier title:(NSString *)title body:(NSString *)body;

@end

NS_ASSUME_NONNULL_END
