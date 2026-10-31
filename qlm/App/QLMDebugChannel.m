#import "QLMDebugChannel.h"

#if DEBUG

#import "DebugChannel.h"
#import "DebugClient.h"
#import "DebugCommandDispatch.h"
#import "DebugStandardVerbs.h"
#import "DebugSyntheticInput.h"
#import "DebugWireFormat.h"
#import "QLMSnapshot.h"

#define QLM_HANDLER ^NSString *(NSArray<NSString *> *tokens, NSString *commandId, id<QLMDebugApp> app)

static NSString *QLMDebugName(NSInteger value, NSArray<NSString *> *names) {
    return value >= 0 && (NSUInteger)value < names.count ? names[(NSUInteger)value] : @"unknown";
}

static NSString *QLMDebugHex(NSData *data) {
    NSMutableString *hex = [NSMutableString string];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

static NSDictionary *QLMDebugMonitor(QLMMonitorState *monitor, QLMSnapshot *snapshot) {
    return @{
        @"hardwareID": QLMDebugHex(monitor.hardwareID),
        @"session": @(monitor.session),
        @"serialNumber": monitor.serialNumber ?: NSNull.null,
        @"model": monitor.model ?: NSNull.null,
        @"status": QLMDebugName(monitor.status, @[@"unknown", @"on", @"standby"]),
        @"class": QLMDebugName(monitor.deviceClass, @[@"unknown", @"subwoofer", @"twoWay"]),
        @"temperature": monitor.temperature == QLMMonitorValueAbsent ? NSNull.null : @(monitor.temperature),
        @"missedPolls": @(monitor.missedPolls),
        @"offline": @(monitor.offline),
        @"muted": @(monitor.muted),
        @"lifted": @([snapshot.liftedHardwareIDs containsObject:monitor.hardwareID]),
    };
}

static NSDictionary *QLMDebugSnapshot(QLMSnapshot *snapshot) {
    NSMutableArray *monitors = [NSMutableArray array];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        [monitors addObject:QLMDebugMonitor(monitor, snapshot)];
    }
    QLMAdapterState *adapter = snapshot.adapter;
    return @{
        @"running": @(snapshot.running),
        @"idle": @(snapshot.idle),
        @"busProblem": QLMDebugName(snapshot.busProblem, @[@"none", @"noAdapter", @"glm", @"otherHost"]),
        @"adapterProblem": QLMDebugName(snapshot.adapterProblem, @[@"none", @"unresponsive", @"lostTrack"]),
        @"adapterError": snapshot.adapterError.localizedDescription ?: NSNull.null,
        @"adapter": @{
            @"device": adapter.device ?: NSNull.null,
            @"model": adapter.model ?: NSNull.null,
            @"serialNumber": adapter.serialNumber ?: NSNull.null,
            @"hasStatus": @(adapter.hasStatus),
            @"knobPresent": @(adapter.knobPresent),
            @"knobTenths": adapter.knobTenths ?: NSNull.null,
            @"missedPolls": @(adapter.missedPolls),
        },
        @"monitors": monitors,
        @"volumeDecibels": snapshot.volumeDecibels ?: NSNull.null,
        @"ceilingDecibels": @(snapshot.ceilingDecibels),
        @"dimmed": @(snapshot.dimmed),
        @"applying": @(snapshot.applying),
        @"activeGroupName": snapshot.activeGroupName ?: NSNull.null,
        @"mutingAll": @(snapshot.mutingAll),
    };
}

// Which of the app's windows show, so a reply says what a verb opened.
static NSDictionary *QLMDebugWindows(id<QLMDebugApp> app) {
    NSMutableArray<NSString *> *visible = [NSMutableArray array];
    for (NSWindow *window in NSApp.windows) {
        if (window.isVisible && window.title.length > 0) {
            [visible addObject:window.title];
        }
    }
    return @{@"ok": @YES, @"popoverShown": @(app.debugPopover.isShown), @"windows": visible};
}

static NSArray<NSDictionary *> *QLMDebugOwnVerbs(void) {
    return @[
        VibeDebugCmd(@"dump_state", 0, QLM_HANDLER {
            QLMSnapshot *snapshot = app.debugSnapshot;
            NSMutableDictionary *reply = [QLMDebugWindows(app) mutableCopy];
            reply[@"snapshot"] = snapshot ? QLMDebugSnapshot(snapshot) : NSNull.null;
            return VibeJSONString(reply);
        }),
        VibeDebugCmd(@"popover <show|close>", 0, QLM_HANDLER {
            NSString *action = tokens.count == 2 ? tokens[1] : @"";
            if ([action isEqualToString:@"show"]) {
                [app debugShowPopover];
            }
            else if ([action isEqualToString:@"close"]) {
                [app.debugPopover close];
            }
            else {
                return VibeErrorJSON(@"usage: popover <show|close>");
            }
            return VibeJSONString(QLMDebugWindows(app));
        }),
        VibeDebugCmd(@"show_monitors", 0, QLM_HANDLER {
            [app debugShowMonitors];
            return VibeJSONString(QLMDebugWindows(app));
        }),
        VibeDebugCmd(@"show_settings", 0, QLM_HANDLER {
            [app debugShowSettings];
            return VibeJSONString(QLMDebugWindows(app));
        }),
        // The read lands on a utility queue, so the reply only acknowledges it.
        VibeDebugCmd(@"read_setup", 0, QLM_HANDLER {
            [app debugReadSetup];
            return VibeJSONString(@{@"ok": @YES, @"reading": @YES});
        }),
    ];
}

// qlm's own verbs, then vibe-libs' standard verbs, then its input verbs. A
// verb in two of them would run from the first, silently.
static NSArray<NSArray<NSDictionary *> *> *QLMDebugTables(void) {
    static NSArray<NSArray<NSDictionary *> *> *tables;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        VibeDebugStandardOptions *options = [VibeDebugStandardOptions new];
        // The popover's window while it shows, since it is the app's one
        // surface. Otherwise the key window.
        options.targetWindow = ^NSWindow *(id<QLMDebugApp> app) {
            NSPopover *popover = app.debugPopover;
            return popover.isShown ? popover.contentViewController.view.window : NSApp.keyWindow;
        };
        tables = @[QLMDebugOwnVerbs(), VibeDebugStandardVerbs(options), VibeDebugInputVerbs(options)];
    });
    return tables;
}

NSDictionary *QLMDebugSpecForVerb(NSString *verb) {
    for (NSArray<NSDictionary *> *table in QLMDebugTables()) {
        NSDictionary *spec = VibeDebugSpecForVerb(table, verb);
        if (spec != nil) {
            return spec;
        }
    }
    return nil;
}

void QLMDebugInstallChannel(id<QLMDebugApp> app) {
    NSArray<NSString *> *duplicates = VibeDebugDuplicateVerbs(QLMDebugTables());
    NSCAssert(duplicates.count == 0, @"verbs in two debug tables, which run from the first: %@", duplicates);
    __weak id<QLMDebugApp> weakApp = app;
    VibeInstallDebugCommandChannel(NSBundle.mainBundle.bundleIdentifier, ^NSString *(NSArray<NSString *> *args,
                                                                                     NSString *commandId) {
        NSString *verb = args.firstObject ?: @"";
        NSDictionary *spec = QLMDebugSpecForVerb(verb);
        if (spec == nil) {
            return VibeDebugUnknownCommandReply(verb, QLMDebugTables(), nil);
        }
        id<QLMDebugApp> strongApp = weakApp;
        if (strongApp == nil) {
            return VibeErrorJSON(@"the app isn't running");
        }
        return ((VibeDebugCommandHandler)spec[@"handler"])(args, commandId, strongApp);
    });
}

int QLMDebugClientMain(int argc, const char *argv[]) {
    VibeDebugClientOptions *options = [VibeDebugClientOptions new];
    options.channel = NSBundle.mainBundle.bundleIdentifier ?: @"";
    options.displayName = @"qlm";
    options.messagePrefix = @"qlm";
    options.timeoutEnvironmentKey = @"QLM_DEBUG_TIMEOUT";
    options.waitForVerb = ^NSTimeInterval(NSString *verb) {
        return [QLMDebugSpecForVerb(verb)[@"clientTimeout"] doubleValue];
    };
    options.fileVerbs = @[@"dump_screenshot"];
    return VibeDebugClientMain(argc, argv, options);
}

#endif
