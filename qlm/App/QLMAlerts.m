#import "QLMAlerts.h"

#import <UserNotifications/UserNotifications.h>

#import "QLMFormat.h"

// At or above it, a monitor runs hot. In standby the user's monitors read
// 29 to 47 °C (qlm-standby-discover).
static const NSInteger QLMHotTemperature = 70;
// A hot monitor may alert again only once it cools this far below.
static const NSInteger QLMHotHysteresis = 5;
// Between two alerts of one kind for one monitor, at least this long.
static const NSTimeInterval QLMAlertInterval = 10 * 60;

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
    QLMNotifier *_notifier;
    // System ran with the adapter at the last update. A drop counts only
    // between two such updates.
    BOOL _wasHealthy;
    QLMAdapterProblem _adapterProblem;  // at the last update
    NSMutableSet<NSData *> *_hot;
    NSMutableDictionary<NSString *, NSDate *> *_lastAlerts;  // by kind and monitor
}

- (instancetype)initWithNotifier:(QLMNotifier *)notifier {
    self = [super init];
    if (self) {
        _notifier = notifier;
        _hot = [NSMutableSet set];
        _lastAlerts = [NSMutableDictionary dictionary];
    }
    return self;
}

// Its model and its name, as the setup gives it, else its serial.
- (NSString *)nameOf:(QLMMonitorState *)monitor {
    NSString *model = monitor.model ?: @"Monitor";
    NSString *label = QLMMonitorLabel(monitor, self.setup);
    return label != nil ? [NSString stringWithFormat:@"%@ %@", model, label] : model;
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

- (void)updateWithMonitorList:(QLMMonitorList *)list {
    QLMSnapshot *snapshot = list.snapshot;
    BOOL healthy = snapshot.running && snapshot.busProblem == QLMBusProblemNone;
    if (healthy && _wasHealthy) {
        [self alertDrops:list.dropped];
    }
    _wasHealthy = healthy;
    [self alertHeat:snapshot.monitors];
    [self alertAdapterProblem:snapshot];
}

// The adapter takes over about 2.6 s after the last report it took, with
// no stop of qlm's, and the popover may be closed. Only the HID adapter
// reports a problem, so this is the real monitors'.
- (void)alertAdapterProblem:(QLMSnapshot *)snapshot {
    QLMAdapterProblem problem = snapshot.adapterProblem;
    if (problem != _adapterProblem && problem != QLMAdapterProblemNone && QLMStopMayRaiseLevel(snapshot)) {
        [_notifier postIdentifier:@"adapter" title:QLMBusProblemTitle(snapshot) body:QLMBusProblemDetail(snapshot)];
    }
    _adapterProblem = problem;
}

- (void)alertDrops:(NSArray<QLMMonitorState *> *)monitors {
    NSMutableArray<QLMMonitorState *> *dropped = [NSMutableArray array];
    for (QLMMonitorState *monitor in monitors) {
        if ([self mayAlert:@"drop" monitor:monitor]) {
            [dropped addObject:monitor];
        }
    }
    if (dropped.count == 1) {
        QLMMonitorState *monitor = dropped.firstObject;
        [_notifier postIdentifier:[@"drop-" stringByAppendingString:QLMMonitorKey(monitor)]
                            title:[NSString stringWithFormat:@"%@ dropped off the bus", monitor.model ?: @"A monitor"]
                             body:[NSString stringWithFormat:@"%@ stopped answering. qlm finds it again when it answers.", [self nameOf:monitor]]];
    } else if (dropped.count > 1) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (QLMMonitorState *monitor in dropped) {
            [names addObject:[self nameOf:monitor]];
        }
        [_notifier postIdentifier:@"drops"
                            title:[NSString stringWithFormat:@"%lu monitors dropped off the bus", (unsigned long)dropped.count]
                             body:[NSString stringWithFormat:@"%@ stopped answering. qlm finds them again when they answer.",
                                                             [names componentsJoinedByString:@", "]]];
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
                [_notifier postIdentifier:[@"hot-" stringByAppendingString:QLMMonitorKey(monitor)]
                                    title:[NSString stringWithFormat:@"%@ runs hot", monitor.model ?: @"A monitor"]
                                     body:[NSString stringWithFormat:@"%@ reads %@. qlm alerts at %@.", [self nameOf:monitor],
                                                                     QLMTemperatureText(temperature), QLMTemperatureText(QLMHotTemperature)]];
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
