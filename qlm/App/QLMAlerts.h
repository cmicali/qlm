#import <Foundation/Foundation.h>

#import "QLMClock.h"
#import "QLMMonitorList.h"

@class QLMSetup;

NS_ASSUME_NONNULL_BEGIN

// Where an alert goes. QLMNotifier posts it, and a test records it.
@protocol QLMAlertPosting <NSObject>
// A newer notification with the same identifier replaces it.
- (void)postIdentifier:(NSString *)identifier title:(NSString *)title body:(NSString *)body;
@end

// Posts through UNUserNotificationCenter, with no sound: the Mac's sound
// likely plays through the monitors. The first alert asks the user for
// permission. A process with no bundle, such as a harness, has no center,
// so it logs. On the main queue.
@interface QLMNotifier : NSObject <QLMAlertPosting>
@end

// The real clock, with a now that counts the time the Mac sleeps, so a day
// between two alerts is a day.
@interface QLMSleepCountingClock : QLMRealClock
@end

// Turns the monitor list's updates into alerts: a monitor System drops, one
// that runs hot at 70 °C, an adapter that stops answering while its
// take-over may make the monitors louder, and a sleep whose take-over may
// do the same. Each alert fires once until its cause clears. A dropped
// monitor must be back and on, since one in standby may drop and come back
// all night. A hot one must cool 5 °C. Each monitor also gets at most one
// alert of each kind every 10 minutes. While System is stopped or the
// adapter is refused, a drop says nothing: the banner covers it. On the
// main queue.
@interface QLMMonitorAlerts : NSObject

- (instancetype)initWithPoster:(id<QLMAlertPosting>)poster clock:(id<QLMClock>)clock;

// Names each monitor in an alert, as the popover does.
@property (nonatomic, nullable) QLMSetup *setup;

// Call after each of the list's updates.
- (void)updateWithMonitorList:(QLMMonitorList *)list;

// Call once as the Mac sleeps, when System's stop may make the monitors
// louder. No one can answer a prompt then. While dimmed, every sleep would
// alert, so a dimmed one alerts at most once a day.
- (void)alertSleepWithSnapshot:(QLMSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END
