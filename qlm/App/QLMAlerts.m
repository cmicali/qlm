#import "QLMAlerts.h"

#include <time.h>

#import <UserNotifications/UserNotifications.h>

#import "QLMFormat.h"

// At or above it, a monitor runs hot. In standby the user's monitors read
// 29 to 47 °C (qlm-standby-discover).
static const NSInteger QLMHotTemperature = 70;
// A hot monitor may alert again only once it cools this far below.
static const NSInteger QLMHotHysteresis = 5;
// Between two alerts of one kind for one monitor, at least this long.
static const NSTimeInterval QLMAlertInterval = 10 * 60;
// Between two alerts of a sleep while dimmed, at least this long.
static const NSTimeInterval QLMDimmedSleepInterval = 24 * 60 * 60;

// Stable across leases, for the notification's identifier.
static NSString *QLMMonitorKey(QLMMonitorState *monitor) {
    NSMutableString *key = [NSMutableString string];
    const uint8_t *bytes = monitor.hardwareID.bytes;
    for (NSUInteger i = 0; i < monitor.hardwareID.length; i++) {
        [key appendFormat:@"%02x", bytes[i]];
    }
    return key;
}

NSTimeInterval QLMSecondsCountingSleep(void) {
    return (NSTimeInterval)clock_gettime_nsec_np(CLOCK_MONOTONIC) / NSEC_PER_SEC;
}

@implementation QLMMonitorAlerts {
    id<QLMAlertPosting> _poster;
    NSTimeInterval (^_now)(void);
    // System ran with the adapter at the last update. A drop counts only
    // between two such updates.
    BOOL _wasHealthy;
    QLMAdapterProblem _adapterProblem;  // at the last update
    NSMutableSet<NSData *> *_hot;
    NSMutableSet<NSData *> *_dropped;  // alerted, and not back and on since
    NSMutableDictionary<NSString *, NSNumber *> *_lastAlerts;  // now, by key
}

- (instancetype)initWithPoster:(id<QLMAlertPosting>)poster now:(NSTimeInterval (^)(void))now {
    self = [super init];
    if (self) {
        _poster = poster;
        _now = [now copy];
        _hot = [NSMutableSet set];
        _dropped = [NSMutableSet set];
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

// Records the alert unless one with the same key went out within
// `interval`.
- (BOOL)mayAlert:(NSString *)key within:(NSTimeInterval)interval {
    NSNumber *last = _lastAlerts[key];
    NSTimeInterval now = _now();
    if (last != nil && now - last.doubleValue < interval) {
        return NO;
    }
    _lastAlerts[key] = @(now);
    return YES;
}

- (BOOL)mayAlert:(NSString *)kind monitor:(QLMMonitorState *)monitor {
    return [self mayAlert:[NSString stringWithFormat:@"%@-%@", kind, QLMMonitorKey(monitor)] within:QLMAlertInterval];
}

- (void)updateWithMonitorList:(QLMMonitorList *)list {
    QLMSnapshot *snapshot = list.snapshot;
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if (monitor.status == QLMMonitorStatusOn && !monitor.offline) {
            [_dropped removeObject:monitor.hardwareID];
        }
    }
    BOOL healthy = snapshot.running && snapshot.busProblem == QLMBusProblemNone;
    if (healthy && _wasHealthy) {
        [self alertDrops:list.dropped];
    }
    _wasHealthy = healthy;
    [self alertHeat:snapshot.monitors];
    [self alertAdapterProblem:snapshot];
}

- (void)alertSleepWithSnapshot:(QLMSnapshot *)snapshot {
    if (snapshot.dimmed && ![self mayAlert:@"dimmed-sleep" within:QLMDimmedSleepInterval]) {
        return;
    }
    [_poster postIdentifier:@"hand-back" title:@"The level may have risen as the Mac slept" body:QLMTakeOverText(snapshot)];
}

// The adapter takes over about 2.6 s after the last report it took, with
// no stop of qlm's, and the popover may be closed. Only the HID adapter
// reports a problem, so this is the real monitors'.
- (void)alertAdapterProblem:(QLMSnapshot *)snapshot {
    QLMAdapterProblem problem = snapshot.adapterProblem;
    if (problem != _adapterProblem && problem != QLMAdapterProblemNone && QLMStopMayRaiseLevel(snapshot)) {
        [_poster postIdentifier:@"adapter" title:QLMBusProblemTitle(snapshot) body:QLMBusProblemDetail(snapshot)];
    }
    _adapterProblem = problem;
}

- (void)alertDrops:(NSArray<QLMMonitorState *> *)monitors {
    NSMutableArray<QLMMonitorState *> *dropped = [NSMutableArray array];
    for (QLMMonitorState *monitor in monitors) {
        if (![_dropped containsObject:monitor.hardwareID] && [self mayAlert:@"drop" monitor:monitor]) {
            [_dropped addObject:monitor.hardwareID];
            [dropped addObject:monitor];
        }
    }
    if (dropped.count == 1) {
        QLMMonitorState *monitor = dropped.firstObject;
        [_poster postIdentifier:[@"drop-" stringByAppendingString:QLMMonitorKey(monitor)]
                          title:[NSString stringWithFormat:@"%@ dropped off the bus", monitor.model ?: @"A monitor"]
                           body:[NSString stringWithFormat:@"%@ stopped answering. qlm finds it again when it answers.", [self nameOf:monitor]]];
    } else if (dropped.count > 1) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (QLMMonitorState *monitor in dropped) {
            [names addObject:[self nameOf:monitor]];
        }
        [_poster postIdentifier:@"drops"
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
                [_poster postIdentifier:[@"hot-" stringByAppendingString:QLMMonitorKey(monitor)]
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
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
    // macOS asks the user once. After that, this answers at once.
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
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
    completionHandler(UNNotificationPresentationOptionBanner);
}

@end
