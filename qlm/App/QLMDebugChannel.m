#import "QLMDebugChannel.h"

#if DEBUG

#include <math.h>

#import "DebugChannel.h"
#import "DebugClient.h"
#import "DebugCommandDispatch.h"
#import "DebugStandardVerbs.h"
#import "DebugSyntheticInput.h"
#import "DebugWireFormat.h"
#import "QLMFormat.h"
#import "QLMPreferences.h"
#import "QLMSnapshot.h"
#import "QLMSystem.h"

typedef NSDictionary *_Nonnull (^QLMDebugHandler)(NSArray<NSString *> *tokens, id<QLMDebugApp> app);

#define QLM_HANDLER ^NSDictionary *(NSArray<NSString *> *tokens, id<QLMDebugApp> app)

// "2026-10-31T14:06:11.123-04:00": the Mac's local time, to the
// millisecond, for a run's notes.md.
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

// Every reply of qlm's own verbs carries "at", taken before the verb runs,
// so it marks the action, not the reply.
static NSDictionary *QLMDebugVerb(NSString *usage, QLMDebugHandler handler) {
    return VibeDebugCmd(usage, 0, ^NSString *(NSArray<NSString *> *tokens, NSString *commandId, id<QLMDebugApp> app) {
        NSString *at = QLMDebugTimeText(NSDate.date);
        NSMutableDictionary *reply = [handler(tokens, app) mutableCopy];
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
    return QLMDebugError(@"usage: %@", QLMDebugSpecForVerb(tokens[0])[@"usage"]);
}

static BOOL QLMDebugSwitch(NSArray<NSString *> *tokens, BOOL *on) {
    return tokens.count == 2 && VibeParseOnOff(tokens, on);
}

static BOOL QLMDebugDecibelsArgument(NSArray<NSString *> *tokens, double *decibels) {
    return tokens.count == 2 && VibeParseDouble(tokens[1], decibels) && isfinite(*decibels);
}

// One decimal, as the app shows it. A knob's tenths over ten would print as
// a binary fraction.
static id QLMDebugDecibels(NSNumber *_Nullable decibels) {
    if (decibels == nil) {
        return NSNull.null;
    }
    return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.1f", decibels.doubleValue]
                                             locale:@{NSLocaleDecimalSeparator: @"."}];
}

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

static NSDictionary *QLMDebugHandBack(QLMSnapshot *snapshot) {
    QLMHandBack *handBack = snapshot.handBack;
    return @{
        @"kind": QLMDebugName(handBack.kind, @[@"unknown", @"knobLevel", @"louder"]),
        @"knobDecibels": QLMDebugDecibels(handBack.knobDecibels),
        @"volumeDecibels": QLMDebugDecibels(handBack.volumeDecibels),
        @"line": QLMHandBackLine(snapshot) ?: NSNull.null,
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
        @"allMuted": @(snapshot.allMuted),
        @"anyOn": @(snapshot.anyOn),
        @"handBack": QLMDebugHandBack(snapshot),
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

// The popover's controls take no click while disabled, and the verbs refuse
// the same: the slider and Dim while System is stopped, and Mute and the
// power button while it tracks no monitor too.
static NSDictionary *_Nullable QLMDebugRefusal(id<QLMDebugApp> app, BOOL needsMonitors) {
    QLMSnapshot *snapshot = app.debugSnapshot;
    if (!snapshot.running) {
        return QLMDebugError(@"System is not running");
    }
    if (needsMonitors && snapshot.monitors.count == 0) {
        return QLMDebugError(@"System tracks no monitor yet");
    }
    return nil;
}

static NSArray<NSDictionary *> *QLMDebugOwnVerbs(void) {
    return @[
        QLMDebugVerb(@"dump_state", QLM_HANDLER {
            QLMSnapshot *snapshot = app.debugSnapshot;
            QLMPreferences *preferences = app.debugPreferences;
            NSMutableDictionary *reply = [QLMDebugWindows(app) mutableCopy];
            reply[@"snapshot"] = snapshot ? QLMDebugSnapshot(snapshot) : NSNull.null;
            reply[@"usesAdapter"] = @(preferences.usesAdapter);
            reply[@"sliderRange"] = @{
                @"lowestDecibels": @(preferences.lowestDecibels),
                @"ceilingDecibels": @(preferences.ceilingDecibels),
            };
            reply[@"quitGLMButton"] = app.debugQuitGLMTitle ?: NSNull.null;
            reply[@"quitAsksFirst"] = @(app.debugQuitAsksFirst);
            return reply;
        }),
        QLMDebugVerb(@"popover <show|close>", QLM_HANDLER {
            NSString *action = tokens.count == 2 ? tokens[1] : @"";
            if ([action isEqualToString:@"show"]) {
                [app debugShowPopover];
            }
            else if ([action isEqualToString:@"close"]) {
                [app.debugPopover close];
            }
            else {
                return QLMDebugUsageError(tokens);
            }
            return QLMDebugWindows(app);
        }),
        QLMDebugVerb(@"show_monitors", QLM_HANDLER {
            [app debugShowMonitors];
            return QLMDebugWindows(app);
        }),
        QLMDebugVerb(@"show_settings", QLM_HANDLER {
            [app debugShowSettings];
            return QLMDebugWindows(app);
        }),
        // The read lands on a utility queue, so the reply only acknowledges it.
        QLMDebugVerb(@"read_setup", QLM_HANDLER {
            [app debugReadSetup];
            return @{@"ok": @YES, @"reading": @YES};
        }),
        // The slider: GLM's 0.5 dB steps, from the range's bottom to the
        // ceiling. A level outside it is refused, not moved into it.
        QLMDebugVerb(@"volume <dB>", QLM_HANDLER {
            double decibels = 0;
            if (!QLMDebugDecibelsArgument(tokens, &decibels)) {
                return QLMDebugUsageError(tokens);
            }
            NSDictionary *refusal = QLMDebugRefusal(app, NO);
            if (refusal != nil) {
                return refusal;
            }
            double lowest = app.debugPreferences.lowestDecibels;
            double ceiling = app.debugPreferences.ceilingDecibels;
            if (decibels < lowest || decibels > ceiling) {
                return QLMDebugError(@"%.1f dB is outside the slider's range, %.1f to %.1f dB", decibels, lowest, ceiling);
            }
            double stepped = QLMNearestStepDecibels(decibels);
            [app.debugSystem setVolumeDecibels:stepped];
            return @{@"ok": @YES, @"volumeDecibels": @(stepped)};
        }),
        // Settings' ceiling. The preferences bound it, as they do a typed one.
        QLMDebugVerb(@"ceiling <dB>", QLM_HANDLER {
            double decibels = 0;
            if (!QLMDebugDecibelsArgument(tokens, &decibels)) {
                return QLMDebugUsageError(tokens);
            }
            app.debugPreferences.ceilingDecibels = decibels;
            [app debugVolumeRangeDidChange];
            return @{@"ok": @YES, @"ceilingDecibels": @(app.debugPreferences.ceilingDecibels)};
        }),
        // Settings' checkbox, "Drive the real monitors through the GLM
        // adapter". A change starts a new System.
        QLMDebugVerb(@"adapter <on|off>", QLM_HANDLER {
            BOOL on = NO;
            if (!QLMDebugSwitch(tokens, &on)) {
                return QLMDebugUsageError(tokens);
            }
            BOOL changed = on != app.debugPreferences.usesAdapter;
            if (changed) {
                app.debugPreferences.usesAdapter = on;
                [app debugAdapterDidChange];
            }
            return @{@"ok": @YES, @"usesAdapter": @(on), @"restarted": @(changed)};
        }),
        // A monitor's mute button takes a click while System tracks it.
        QLMDebugVerb(@"mute <serial> <on|off>", QLM_HANDLER {
            BOOL on = NO;
            if (tokens.count != 3 || !VibeParseOnOff(@[tokens[0], tokens[2]], &on)) {
                return QLMDebugUsageError(tokens);
            }
            NSMutableArray<NSString *> *serials = [NSMutableArray array];
            for (QLMMonitorState *monitor in app.debugSnapshot.monitors) {
                if (monitor.serialNumber == nil) {
                    continue;
                }
                if ([monitor.serialNumber caseInsensitiveCompare:tokens[1]] == NSOrderedSame) {
                    [app.debugSystem setMuted:on forMonitorWithHardwareID:monitor.hardwareID];
                    return @{@"ok": @YES, @"serialNumber": monitor.serialNumber, @"muted": @(on)};
                }
                [serials addObject:monitor.serialNumber];
            }
            return QLMDebugError(@"System tracks no monitor %@. It tracks: %@", tokens[1],
                                 serials.count > 0 ? [serials componentsJoinedByString:@", "] : @"none");
        }),
        QLMDebugVerb(@"mute_all <on|off>", QLM_HANDLER {
            BOOL on = NO;
            if (!QLMDebugSwitch(tokens, &on)) {
                return QLMDebugUsageError(tokens);
            }
            NSDictionary *refusal = QLMDebugRefusal(app, YES);
            if (refusal != nil) {
                return refusal;
            }
            [app.debugSystem setAllMuted:on];
            return @{@"ok": @YES, @"allMuted": @(on)};
        }),
        QLMDebugVerb(@"dim <on|off>", QLM_HANDLER {
            BOOL on = NO;
            if (!QLMDebugSwitch(tokens, &on)) {
                return QLMDebugUsageError(tokens);
            }
            NSDictionary *refusal = QLMDebugRefusal(app, NO);
            if (refusal != nil) {
                return refusal;
            }
            [app.debugSystem setDimmed:on];
            return @{@"ok": @YES, @"dimmed": @(on)};
        }),
        // The power button reads Standby while a monitor is on, and Wake
        // while none is. Each verb takes only its own reading.
        QLMDebugVerb(@"standby", QLM_HANDLER {
            if (tokens.count != 1) {
                return QLMDebugUsageError(tokens);
            }
            NSDictionary *refusal = QLMDebugRefusal(app, YES);
            if (refusal != nil) {
                return refusal;
            }
            if (!app.debugSnapshot.anyOn) {
                return QLMDebugError(@"no monitor is on, so the power button reads Wake");
            }
            [app.debugSystem sleep];
            return @{@"ok": @YES};
        }),
        QLMDebugVerb(@"wake", QLM_HANDLER {
            if (tokens.count != 1) {
                return QLMDebugUsageError(tokens);
            }
            NSDictionary *refusal = QLMDebugRefusal(app, YES);
            if (refusal != nil) {
                return refusal;
            }
            if (app.debugSnapshot.anyOn) {
                return QLMDebugError(@"a monitor is on, so the power button reads Standby");
            }
            [app.debugSystem wake];
            return @{@"ok": @YES};
        }),
        // GLM may ask to save first. It is never forced.
        QLMDebugVerb(@"quit_glm", QLM_HANDLER {
            if (tokens.count != 1) {
                return QLMDebugUsageError(tokens);
            }
            NSString *title = app.debugQuitGLMTitle;
            if (title == nil) {
                return QLMDebugError(@"the banner offers no Quit GLM");
            }
            if (![app debugQuitGLM]) {
                return QLMDebugError(@"GLM was not asked to quit. The button reads %@", title);
            }
            return @{@"ok": @YES, @"askedGLMToQuit": @YES};
        }),
        // Not vibe-libs' quit, whose terminate runs inside a main-queue block.
        // TRAP: there the quit's wait for System's stop can only time out,
        // since the stop's completion waits for that block. So this quit runs
        // from the run loop, after the reply. A cancelled one stops nothing,
        // so it runs here.
        QLMDebugVerb(@"quit_answering <cancel|anyway>", QLM_HANDLER {
            NSString *answer = tokens.count == 2 ? tokens[1].lowercaseString : @"";
            BOOL anyway = [answer isEqualToString:@"anyway"];
            if (!anyway && ![answer isEqualToString:@"cancel"]) {
                return QLMDebugUsageError(tokens);
            }
            BOOL asks = app.debugQuitAsksFirst;
            BOOL quitting = !asks || anyway;
            QLMSnapshot *snapshot = app.debugSnapshot;
            NSDictionary *reply = @{
                @"ok": @YES,
                @"asksFirst": @(asks),
                @"quitting": @(quitting),
                @"handBack": snapshot ? QLMDebugHandBack(snapshot) : NSNull.null,
            };
            if (!quitting) {
                [app debugQuitAnswering:NO];
                return reply;
            }
            __weak id<QLMDebugApp> weakApp = app;
            CFRunLoopRef main = CFRunLoopGetMain();
            CFRunLoopPerformBlock(main, kCFRunLoopCommonModes, ^{
                [weakApp debugQuitAnswering:anyway];
            });
            CFRunLoopWakeUp(main);
            return reply;
        }),
    ];
}

NSArray<NSArray<NSDictionary *> *> *QLMDebugTables(void) {
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

NSString *QLMDebugRun(NSArray<NSString *> *args, NSString *commandId, id<QLMDebugApp> app) {
    NSString *verb = args.firstObject ?: @"";
    NSDictionary *spec = QLMDebugSpecForVerb(verb);
    if (spec == nil) {
        return VibeDebugUnknownCommandReply(verb, QLMDebugTables(), nil);
    }
    if (app == nil) {
        return VibeErrorJSON(@"the app isn't running");
    }
    return ((VibeDebugCommandHandler)spec[@"handler"])(args, commandId, app);
}

void QLMDebugInstallChannel(id<QLMDebugApp> app) {
    NSArray<NSString *> *duplicates = VibeDebugDuplicateVerbs(QLMDebugTables());
    NSCAssert(duplicates.count == 0, @"verbs in two debug tables, which run from the first: %@", duplicates);
    __weak id<QLMDebugApp> weakApp = app;
    VibeInstallDebugCommandChannel(NSBundle.mainBundle.bundleIdentifier, ^NSString *(NSArray<NSString *> *args,
                                                                                     NSString *commandId) {
        return QLMDebugRun(args, commandId, weakApp);
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
