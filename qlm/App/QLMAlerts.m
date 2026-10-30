#import "QLMAlerts.h"

#import <UserNotifications/UserNotifications.h>

const NSInteger QLMHotTemperature = 70;
const NSInteger QLMHotHysteresis = 5;
const NSTimeInterval QLMAlertInterval = 10 * 60;

// The monitor as a person names it: its model and serial.
static NSString *QLMMonitorName(QLMMonitorState *monitor) {
    NSString *model = monitor.model ?: @"Monitor";
    return monitor.serialNumber != nil ? [NSString stringWithFormat:@"%@ %@", model, monitor.serialNumber] : model;
}

// Stable across leases, for the notification's identifier.
static NSString *QLMMonitorKey(QLMMonitorState *monitor) {
    NSMutableString *key = [NSMutableString string];
    const uint8_t *bytes = monitor.hardwareID.bytes;
    for (NSUInteger i = 0; i < monitor.hardwareID.length; i++) {
        [key appendFormat:@"%02x", bytes[i]];
    }
    return key;
}

@implementation QLMMonitorAlerts {
    QLMAlertPoster _poster;
    // The last snapshot's monitors, by hardware ID, while System ran with
    // the adapter. Nil otherwise, so a drop then says nothing.
    NSDictionary<NSData *, QLMMonitorState *> *_tracked;
    NSMutableSet<NSData *> *_hot;
    NSMutableDictionary<NSString *, NSDate *> *_lastAlerts;  // by kind and monitor
}

- (instancetype)initWithPoster:(QLMAlertPoster)poster {
    self = [super init];
    if (self) {
        _poster = [poster copy];
        _hot = [NSMutableSet set];
        _lastAlerts = [NSMutableDictionary dictionary];
    }
    return self;
}

// Records the alert unless one of its kind went out for the monitor within
// QLMAlertInterval.
- (BOOL)mayAlert:(NSString *)kind monitor:(QLMMonitorState *)monitor {
    NSString *key = [NSString stringWithFormat:@"%@-%@", kind, QLMMonitorKey(monitor)];
    NSDate *last = _lastAlerts[key];
    if (last != nil && -last.timeIntervalSinceNow < QLMAlertInterval) {
        return NO;
    }
    _lastAlerts[key] = [NSDate date];
    return YES;
}

- (void)updateWithSnapshot:(QLMSnapshot *)snapshot {
    NSMutableDictionary<NSData *, QLMMonitorState *> *tracked = [NSMutableDictionary dictionary];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        tracked[monitor.hardwareID] = monitor;
    }
    BOOL healthy = snapshot.running && snapshot.adapterError == nil;
    if (healthy) {
        [self alertDropsFrom:_tracked to:tracked];
    }
    _tracked = healthy ? tracked : nil;
    [self alertHeat:snapshot.monitors];
}

- (void)alertDropsFrom:(nullable NSDictionary<NSData *, QLMMonitorState *> *)before
                    to:(NSDictionary<NSData *, QLMMonitorState *> *)now {
    NSMutableArray<QLMMonitorState *> *dropped = [NSMutableArray array];
    for (NSData *hardwareID in before) {
        if (now[hardwareID] == nil && [self mayAlert:@"drop" monitor:before[hardwareID]]) {
            [dropped addObject:before[hardwareID]];
        }
    }
    if (dropped.count == 1) {
        QLMMonitorState *monitor = dropped.firstObject;
        _poster([@"drop-" stringByAppendingString:QLMMonitorKey(monitor)],
                [NSString stringWithFormat:@"%@ dropped off the bus", monitor.model ?: @"A monitor"],
                [NSString stringWithFormat:@"%@ stopped answering. qlm finds it again when it answers.", QLMMonitorName(monitor)]);
    } else if (dropped.count > 1) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (QLMMonitorState *monitor in dropped) {
            [names addObject:QLMMonitorName(monitor)];
        }
        _poster(@"drops", [NSString stringWithFormat:@"%lu monitors dropped off the bus", (unsigned long)dropped.count],
                [NSString stringWithFormat:@"%@ stopped answering. qlm finds them again when they answer.",
                                           [names componentsJoinedByString:@", "]]);
    }
}

- (void)alertHeat:(NSArray<QLMMonitorState *> *)monitors {
    for (QLMMonitorState *monitor in monitors) {
        NSInteger temperature = monitor.temperature;
        if (temperature == QLMMonitorValueAbsent) {
            continue;
        }
        if (temperature <= QLMHotTemperature - QLMHotHysteresis) {
            [_hot removeObject:monitor.hardwareID];
        } else if (temperature >= QLMHotTemperature && ![_hot containsObject:monitor.hardwareID]) {
            [_hot addObject:monitor.hardwareID];
            if ([self mayAlert:@"hot" monitor:monitor]) {
                _poster([@"hot-" stringByAppendingString:QLMMonitorKey(monitor)],
                        [NSString stringWithFormat:@"%@ runs hot", monitor.model ?: @"A monitor"],
                        [NSString stringWithFormat:@"%@ reads %ld °C. qlm alerts at %ld °C.", QLMMonitorName(monitor),
                                                   (long)temperature, (long)QLMHotTemperature]);
            }
        }
    }
}

@end

@interface QLMNotifier () <UNUserNotificationCenterDelegate>
@end

@implementation QLMNotifier {
    UNUserNotificationCenter *_center;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // TRAP: UNUserNotificationCenter throws in a process with no bundle.
        if (NSBundle.mainBundle.bundleIdentifier != nil) {
            _center = UNUserNotificationCenter.currentNotificationCenter;
            _center.delegate = self;
        }
    }
    return self;
}

- (void)postIdentifier:(NSString *)identifier title:(NSString *)title body:(NSString *)body {
    UNUserNotificationCenter *center = _center;
    if (center == nil) {
        NSLog(@"qlm alert %@: %@. %@", identifier, title, body);
        return;
    }
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = body;
    content.sound = UNNotificationSound.defaultSound;
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
    // macOS asks the user once. After that, this answers at once.
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
                          completionHandler:^(BOOL granted, NSError *error) {
                              if (granted) {
                                  [center addNotificationRequest:request withCompletionHandler:nil];
                              }
                          }];
}

// Shows the alert even while qlm is the active app.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

@end
