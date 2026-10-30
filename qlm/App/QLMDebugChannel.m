#import "QLMDebugChannel.h"

#if DEBUG

#include <math.h>
#include <notify.h>
#include <unistd.h>

#import "DebugChannel.h"
#import "DebugCommandDispatch.h"
#import "DebugWireFormat.h"
#import "QLMFormat.h"

// A verb's wait when its spec gives none. Every verb replies at once.
static const NSTimeInterval QLMDebugDefaultWait = 5;

// The client answers it itself, with the command list.
static NSString *const QLMDebugHelpUsage = @"help";

typedef NSDictionary *_Nonnull (^QLMDebugVerb)(NSArray<NSString *> *tokens, id<QLMDebugApp> app);

static __weak id<QLMDebugApp> QLMDebugInstalledApp;

static NSString *QLMDebugTimeText(NSDate *date) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        formatter.timeZone = NSTimeZone.localTimeZone;
    });
    return [formatter stringFromDate:date];
}

// The time goes in before the verb runs, so it marks the action, not the
// reply.
static NSDictionary *QLMDebugCommand(NSString *usage, QLMDebugVerb verb) {
    return VibeDebugCmd(usage, 0, ^NSString *(NSArray<NSString *> *tokens, NSString *commandId, id<QLMDebugApp> app) {
        NSString *at = QLMDebugTimeText(NSDate.date);
        NSMutableDictionary *reply = [verb(tokens, app) mutableCopy];
        reply[@"at"] = at;
        return VibeJSONString(reply);
    });
}

static NSDictionary *QLMDebugError(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSDictionary *QLMDebugError(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return @{@"error": message};
}

static NSDictionary *QLMDebugUsageError(NSArray<NSString *> *tokens) {
    return QLMDebugError(@"usage: %@", VibeDebugSpecForVerb(QLMDebugCommands(), tokens.firstObject)[@"usage"]);
}

// One decimal, as the app shows it. A double of a knob in tenths would print
// as a binary fraction.
static NSDecimalNumber *QLMDecibelsNumber(double decibels) {
    return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.1f", decibels]
                                             locale:@{NSLocaleDecimalSeparator: @"."}];
}

static id QLMOrNull(id _Nullable value) {
    return value ?: NSNull.null;
}

static id QLMDecibelsOrNull(NSNumber *_Nullable decibels) {
    return decibels == nil ? NSNull.null : QLMDecibelsNumber(decibels.doubleValue);
}

// "12 2F AB", as protocol.md writes a hardware ID.
static NSString *QLMHexText(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:data.length];
    for (NSUInteger i = 0; i < data.length; i++) {
        [pairs addObject:[NSString stringWithFormat:@"%02X", bytes[i]]];
    }
    return [pairs componentsJoinedByString:@" "];
}

static NSString *QLMStatusName(QLMMonitorStatus status) {
    switch (status) {
    case QLMMonitorStatusOn: return @"on";
    case QLMMonitorStatusStandby: return @"standby";
    case QLMMonitorStatusUnknown: break;
    }
    return @"unknown";
}

static NSString *QLMBusProblemName(QLMBusProblem problem) {
    switch (problem) {
    case QLMBusProblemNoAdapter: return @"no-adapter";
    case QLMBusProblemGLM: return @"glm";
    case QLMBusProblemOtherHost: return @"other-host";
    case QLMBusProblemNone: break;
    }
    return @"none";
}

static NSString *QLMHandBackName(QLMHandBackKind kind) {
    switch (kind) {
    case QLMHandBackKnobLevel: return @"knob-level";
    case QLMHandBackLouder: return @"louder";
    case QLMHandBackUnknown: break;
    }
    return @"unknown";
}

static NSDictionary *QLMMonitorJSON(QLMMonitorState *monitor) {
    return @{
        @"serial": QLMOrNull(monitor.serialNumber),
        @"model": QLMOrNull(monitor.model),
        @"firmware": QLMOrNull(monitor.firmwareVersion),
        @"hardwareID": QLMHexText(monitor.hardwareID),
        @"session": @(monitor.session),
        @"status": QLMStatusName(monitor.status),
        @"identified": @(monitor.identified),
        @"muted": @(monitor.muted),
        @"offline": @(monitor.offline),
        @"missedPolls": @(monitor.missedPolls),
        @"temperature": monitor.temperature == QLMMonitorValueAbsent ? NSNull.null : @(monitor.temperature),
    };
}

static NSDictionary *QLMHandBackJSON(QLMSnapshot *snapshot, id<QLMDebugApp> app) {
    QLMHandBack *handBack = snapshot.handBack;
    return @{
        @"kind": QLMHandBackName(handBack.kind),
        @"knob": QLMDecibelsOrNull(handBack.knobDecibels),
        @"volume": QLMDecibelsOrNull(handBack.volumeDecibels),
        @"line": QLMOrNull(QLMHandBackLine(snapshot)),
        @"quitAsksFirst": @(app.quitAsksFirst),
    };
}

// What the popover shows, and the state behind it.
static NSDictionary *QLMStateJSON(QLMSnapshot *snapshot, id<QLMDebugApp> app) {
    QLMPreferences *preferences = app.preferences;
    QLMAdapterState *adapter = snapshot.adapter;
    NSString *bannerTitle = QLMBusProblemTitle(snapshot.busProblem);
    id banner = NSNull.null;
    if (bannerTitle != nil) {
        banner = @{@"title": bannerTitle, @"detail": QLMBusProblemDetail(snapshot), @"button": QLMOrNull(app.quitGLMTitle)};
    }
    // As the popover reads it: with a volume set, the ceiling System caps at.
    double ceiling = snapshot.volumeDecibels != nil ? snapshot.ceilingDecibels : preferences.ceilingDecibels;
    NSMutableArray<NSDictionary *> *monitors = [NSMutableArray array];
    for (QLMMonitorState *monitor in snapshot.monitors) {
        [monitors addObject:QLMMonitorJSON(monitor)];
    }
    BOOL haveMonitors = snapshot.running && snapshot.monitors.count > 0;
    return @{
        @"running": @(snapshot.running),
        @"idle": @(snapshot.idle),
        @"applying": @(snapshot.applying),
        @"activeGroup": QLMOrNull(snapshot.activeGroupName),
        @"usesAdapter": @(preferences.usesAdapter),
        @"busProblem": QLMBusProblemName(snapshot.busProblem),
        @"banner": banner,
        @"adapter": @{
            @"device": QLMOrNull(adapter.device),
            @"model": QLMOrNull(adapter.model),
            @"firmware": QLMOrNull(adapter.firmwareVersion),
            @"serial": QLMOrNull(adapter.serialNumber),
            @"hasStatus": @(adapter.hasStatus),
            @"missedPolls": @(adapter.missedPolls),
        },
        @"knob": @{
            @"present": @(adapter.knobPresent),
            @"decibels": adapter.knobTenths == nil ? NSNull.null : QLMDecibelsNumber(adapter.knobTenths.doubleValue / 10),
        },
        @"level": @{
            @"volume": QLMDecibelsOrNull(snapshot.volumeDecibels),
            @"sent": QLMDecibelsOrNull(snapshot.handBack.volumeDecibels),
            @"lowest": QLMDecibelsNumber(preferences.lowestDecibels),
            @"ceiling": QLMDecibelsNumber(ceiling),
            @"dimmed": @(snapshot.dimmed),
            @"allMuted": @(snapshot.allMuted),
            @"mutingAll": @(snapshot.mutingAll),
        },
        @"power": @{
            @"anyOn": @(snapshot.anyOn),
            @"button": snapshot.anyOn ? @"Standby" : @"Wake",
            @"enabled": @(haveMonitors),
        },
        @"handBack": QLMHandBackJSON(snapshot, app),
        @"monitors": monitors,
    };
}

// The popover's controls take no click while disabled, and the verbs refuse
// the same.
static NSDictionary *_Nullable QLMRefusal(QLMSnapshot *_Nullable snapshot, BOOL needsMonitors) {
    if (!snapshot.running) {
        return QLMDebugError(@"System is not running");
    }
    if (needsMonitors && snapshot.monitors.count == 0) {
        return QLMDebugError(@"no monitors yet");
    }
    return nil;
}

static BOOL QLMParseSwitch(NSArray<NSString *> *tokens, BOOL *on) {
    return tokens.count == 2 && VibeParseOnOff(tokens, on);
}

NSArray<NSDictionary *> *QLMDebugCommands(void) {
    static NSArray<NSDictionary *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @[
            QLMDebugCommand(@"state", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                QLMSnapshot *snapshot = app.shownSnapshot;
                if (snapshot == nil) {
                    return QLMDebugError(@"qlm has drawn no snapshot yet");
                }
                return QLMStateJSON(snapshot, app);
            }),
            // The slider: GLM's 0.5 dB steps, from the range's bottom to the
            // ceiling. A level outside it is refused, not moved into it.
            QLMDebugCommand(@"volume <dB>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                NSDictionary *refusal = QLMRefusal(app.shownSnapshot, NO);
                if (refusal != nil) {
                    return refusal;
                }
                double decibels = 0;
                if (tokens.count != 2 || !VibeParseDouble(tokens[1], &decibels) || !isfinite(decibels)) {
                    return QLMDebugUsageError(tokens);
                }
                double lowest = app.preferences.lowestDecibels;
                double ceiling = app.preferences.ceilingDecibels;
                if (decibels < lowest || decibels > ceiling) {
                    return QLMDebugError(@"%.1f dB is outside the slider's range, %.1f to %.1f dB", decibels, lowest, ceiling);
                }
                double stepped = QLMNearestStepDecibels(decibels);
                [app.system setVolumeDecibels:stepped];
                return @{@"volume": QLMDecibelsNumber(stepped)};
            }),
            QLMDebugCommand(@"ceiling <dB>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                double decibels = 0;
                if (tokens.count != 2 || !VibeParseDouble(tokens[1], &decibels) || !isfinite(decibels)) {
                    return QLMDebugUsageError(tokens);
                }
                [app changeCeilingDecibels:decibels];
                return @{@"ceiling": QLMDecibelsNumber(app.preferences.ceilingDecibels)};
            }),
            QLMDebugCommand(@"adapter <on|off>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                BOOL on = NO;
                if (!QLMParseSwitch(tokens, &on)) {
                    return QLMDebugUsageError(tokens);
                }
                BOOL changed = on != app.preferences.usesAdapter;
                if (changed) {
                    [app changeUsesAdapter:on];
                }
                return @{@"usesAdapter": @(app.preferences.usesAdapter), @"restarted": @(changed)};
            }),
            // A monitor's row takes a click while System tracks the monitor.
            QLMDebugCommand(@"mute <serial> <on|off>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                BOOL on = NO;
                if (tokens.count != 3 || !VibeParseOnOff(@[tokens[0], tokens[2]], &on)) {
                    return QLMDebugUsageError(tokens);
                }
                QLMSnapshot *snapshot = app.shownSnapshot;
                NSMutableArray<NSString *> *serials = [NSMutableArray array];
                for (QLMMonitorState *monitor in snapshot.monitors) {
                    if (monitor.serialNumber == nil) {
                        continue;
                    }
                    if ([monitor.serialNumber caseInsensitiveCompare:tokens[1]] == NSOrderedSame) {
                        [app.system setMuted:on forMonitorWithHardwareID:monitor.hardwareID];
                        return @{@"serial": monitor.serialNumber, @"muted": @(on)};
                    }
                    [serials addObject:monitor.serialNumber];
                }
                return QLMDebugError(@"System tracks no monitor %@. It tracks: %@", tokens[1],
                                     serials.count > 0 ? [serials componentsJoinedByString:@", "] : @"none");
            }),
            QLMDebugCommand(@"mute-all <on|off>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                BOOL on = NO;
                if (!QLMParseSwitch(tokens, &on)) {
                    return QLMDebugUsageError(tokens);
                }
                NSDictionary *refusal = QLMRefusal(app.shownSnapshot, YES);
                if (refusal != nil) {
                    return refusal;
                }
                [app.system setAllMuted:on];
                return @{@"allMuted": @(on)};
            }),
            QLMDebugCommand(@"dim <on|off>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                BOOL on = NO;
                if (!QLMParseSwitch(tokens, &on)) {
                    return QLMDebugUsageError(tokens);
                }
                NSDictionary *refusal = QLMRefusal(app.shownSnapshot, NO);
                if (refusal != nil) {
                    return refusal;
                }
                [app.system setDimmed:on];
                return @{@"dimmed": @(on)};
            }),
            // The power button reads Standby while a monitor is on, and Wake
            // while none is.
            QLMDebugCommand(@"standby", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                QLMSnapshot *snapshot = app.shownSnapshot;
                NSDictionary *refusal = QLMRefusal(snapshot, YES);
                if (refusal != nil) {
                    return refusal;
                }
                if (!snapshot.anyOn) {
                    return QLMDebugError(@"no monitor is on, so the power button reads Wake");
                }
                [app.system sleep];
                return @{@"power": @"standby"};
            }),
            QLMDebugCommand(@"wake", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                QLMSnapshot *snapshot = app.shownSnapshot;
                NSDictionary *refusal = QLMRefusal(snapshot, YES);
                if (refusal != nil) {
                    return refusal;
                }
                if (snapshot.anyOn) {
                    return QLMDebugError(@"a monitor is on, so the power button reads Standby");
                }
                [app.system wake];
                return @{@"power": @"wake"};
            }),
            QLMDebugCommand(@"quit-glm", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                NSString *title = app.quitGLMTitle;
                if (title == nil) {
                    return QLMDebugError(@"the banner offers no Quit GLM");
                }
                if (![app quitGLM]) {
                    return QLMDebugError(@"GLM was not asked to quit. The button reads %@", title);
                }
                return @{@"askedGLMToQuit": @YES};
            }),
            // The answer stands in for the hand-back alert's, when the app
            // asks. A cancelled quit runs here. A quit goes out after the
            // reply, from the run loop: a quit waits for System's stop on the
            // main queue, and this runs inside a block on it.
            QLMDebugCommand(@"quit <cancel|anyway>", ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app) {
                NSString *answer = tokens.count == 2 ? tokens[1].lowercaseString : @"";
                BOOL anyway = [answer isEqualToString:@"anyway"];
                if (!anyway && ![answer isEqualToString:@"cancel"]) {
                    return QLMDebugUsageError(tokens);
                }
                QLMSnapshot *snapshot = app.shownSnapshot;
                NSDictionary *handBack = snapshot == nil ? @{} : QLMHandBackJSON(snapshot, app);
                BOOL asks = app.quitAsksFirst;
                if (asks && !anyway) {
                    [app quitAnswering:NO];
                    return @{@"quitting": @NO, @"asksFirst": @YES, @"handBack": handBack};
                }
                __weak id<QLMDebugApp> weakApp = app;
                CFRunLoopRef main = CFRunLoopGetMain();
                CFRunLoopPerformBlock(main, kCFRunLoopCommonModes, ^{
                    [weakApp quitAnswering:anyway];
                });
                CFRunLoopWakeUp(main);
                return @{@"quitting": @YES, @"asksFirst": @(asks), @"handBack": handBack};
            }),
        ];
    });
    return table;
}

NSString *QLMDebugChannelName(void) {
    return NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName;
}

NSString *QLMDebugRun(NSArray<NSString *> *args, NSString *commandId, id<QLMDebugApp> app) {
    NSArray<NSDictionary *> *table = QLMDebugCommands();
    NSString *verb = args.firstObject ?: @"";
    NSDictionary *spec = VibeDebugSpecForVerb(table, verb);
    if (spec == nil) {
        return VibeDebugUnknownCommandReply(verb, @[table], @[QLMDebugHelpUsage]);
    }
    if (app == nil) {
        return VibeErrorJSON(@"qlm has not finished launching");
    }
    return ((VibeDebugCommandHandler)spec[@"handler"])(args, commandId, app);
}

void QLMInstallDebugChannel(id<QLMDebugApp> app) {
    QLMDebugInstalledApp = app;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        VibeInstallDebugCommandChannel(QLMDebugChannelName(), ^NSString *(NSArray<NSString *> *args, NSString *commandId) {
            return QLMDebugRun(args, commandId, QLMDebugInstalledApp);
        });
    });
}

NSString *QLMDebugSend(NSArray<NSString *> *args) {
    NSString *channel = QLMDebugChannelName();
    NSTimeInterval wait = [VibeDebugSpecForVerb(QLMDebugCommands(), args.firstObject ?: @"")[@"clientTimeout"] doubleValue];
    if (wait <= 0) {
        wait = QLMDebugDefaultWait;
    }
    NSString *commandId = NSUUID.UUID.UUIDString;
    NSString *commandPath = VibeDebugCommandPath(channel, commandId);
    NSData *payload = [NSJSONSerialization dataWithJSONObject:@{@"id": commandId, @"args": args} options:0 error:NULL];
    // Atomically: the drain deletes a file it reads half written, unrun.
    if (payload == nil || ![payload writeToFile:commandPath atomically:YES]) {
        return nil;
    }
    notify_post(VibeDebugCommandNotificationName(channel).UTF8String);

    NSFileManager *files = NSFileManager.defaultManager;
    NSString *responsePath = VibeDebugResponsePath(channel, commandId);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:wait];
    while (![files fileExistsAtPath:responsePath]) {
        if (deadline.timeIntervalSinceNow <= 0) {
            // TRAP: a command left behind still runs when the app next
            // drains, long after the script gave up on it.
            [files removeItemAtPath:commandPath error:NULL];
            return nil;
        }
        // With no source to wait on, the run loop returns at once.
        if (![NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]) {
            usleep(10000);
        }
    }
    NSString *reply = [NSString stringWithContentsOfFile:responsePath encoding:NSUTF8StringEncoding error:NULL];
    [files removeItemAtPath:responsePath error:NULL];
    return reply;
}

int QLMDebugClientMain(NSArray<NSString *> *args) {
    if (args.count == 0 || [args.firstObject isEqualToString:QLMDebugHelpUsage]) {
        printf("usage: qlm debug <verb> [argument …]\n");
        for (NSDictionary *spec in QLMDebugCommands()) {
            printf("  %s\n", [spec[@"usage"] UTF8String]);
        }
        return 0;
    }
    NSString *reply = QLMDebugSend(args);
    if (reply == nil) {
        fprintf(stderr, "qlm debug: no reply on %s. Is a Debug build of qlm running?\n", QLMDebugChannelName().UTF8String);
        return 2;
    }
    printf("%s\n", reply.UTF8String);
    NSData *data = [reply dataUsingEncoding:NSUTF8StringEncoding];
    id json = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [json isKindOfClass:[NSDictionary class]] && json[@"error"] != nil ? 1 : 0;
}

#endif
