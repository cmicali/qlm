#import "QLMDebugChannel.h"

#if DEBUG

#include <math.h>

#import "DebugChannel.h"
#import "DebugClient.h"
#import "DebugCommandDispatch.h"
#import "DebugStandardVerbs.h"
#import "DebugSyntheticInput.h"
#import "DebugWireFormat.h"
#include "QLMCommands.h"
#import "QLMFakeBus.h"
#import "QLMFormat.h"
#import "QLMPreferences.h"
#import "QLMSkinChoice.h"
#import "QLMSkinLayers.h"
#import "QLMSnapshot.h"
#import "QLMSystem.h"

// Nil for a bad argument: the reply is then the verb's usage.
typedef NSDictionary *_Nullable (^QLMDebugHandler)(NSArray<NSString *> *tokens, id<QLMDebugApp> app);

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
// so it marks the action, not the reply. The usage gives the arguments, one
// per <placeholder>, so the handler runs only with that many.
static NSDictionary *QLMDebugVerb(NSString *usage, QLMDebugHandler handler) {
    NSUInteger arguments = [usage componentsSeparatedByString:@"<"].count - 1;
    return VibeDebugCmd(usage, 0, ^NSString *(NSArray<NSString *> *tokens, NSString *commandId, id<QLMDebugApp> app) {
        NSString *at = QLMDebugTimeText(NSDate.date);
        NSDictionary *reply = tokens.count == 1 + arguments ? handler(tokens, app) : nil;
        NSMutableDictionary *json = [reply ?: @{@"error": [@"usage: " stringByAppendingString:usage]} mutableCopy];
        json[@"at"] = at;
        return VibeJSONString(json);
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

// A verb's own refusal becomes its error. Call it once the verb has run.
static NSDictionary *QLMDebugResult(NSString *_Nullable refusal, NSDictionary *ok) {
    return refusal != nil ? QLMDebugError(@"%@", refusal) : ok;
}

// One of a verb's two words, as <show|close>, in any case. YES for the
// first.
static BOOL QLMDebugParseWord(NSString *token, NSString *first, NSString *second, BOOL *isFirst) {
    NSString *word = token.lowercaseString;
    *isFirst = [word isEqualToString:first];
    return *isFirst || [word isEqualToString:second];
}

// One of the popover's controls, which takes no click while disabled: the
// slider and Dim while System is stopped, and Mute and the power button
// while it tracks no monitor too.
static NSDictionary *QLMDebugControl(NSString *usage, BOOL needsMonitors, QLMDebugHandler handler) {
    return QLMDebugVerb(usage, QLM_HANDLER {
        QLMSnapshot *snapshot = app.debugSnapshot;
        if (!snapshot.running) {
            return QLMDebugError(@"System is not running");
        }
        if (needsMonitors && !QLMSnapshotTracksMonitors(snapshot)) {
            return QLMDebugError(@"System tracks no monitor yet");
        }
        return handler(tokens, app);
    });
}

static BOOL QLMDebugParseFinite(NSString *token, double *value) {
    return VibeParseDouble(token, value) && isfinite(*value);
}

// A control over the volume range. A level outside it is refused, not moved
// into it. `move` takes the level on GLM's steps, sets where it went, and
// returns its control's refusal.
static NSDictionary *QLMDebugLevel(NSString *usage, NSString *control,
                                   NSString *_Nullable (^move)(id<QLMDebugApp> app, double stepped, double *level)) {
    return QLMDebugControl(usage, NO, QLM_HANDLER {
        double decibels = 0;
        if (!QLMDebugParseFinite(tokens[1], &decibels)) {
            return nil;
        }
        double lowest = app.debugPreferences.lowestDecibels;
        double ceiling = app.debugPreferences.ceilingDecibels;
        if (decibels < lowest || decibels > ceiling) {
            return QLMDebugError(@"%.1f dB is outside the %@'s range, %.1f to %.1f dB", decibels, control, lowest, ceiling);
        }
        double level = 0;
        NSString *refusal = move(app, QLMNearestStepDecibels(decibels), &level);
        return QLMDebugResult(refusal, @{@"ok": @YES, @"volumeDecibels": @(level)});
    });
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
        @"adapterProblem": QLMDebugName(snapshot.adapterProblem, @[@"none", @"unresponsive", @"lostTrack", @"notTaking"]),
        @"reconnects": @(snapshot.reconnects),
        @"adapterError": snapshot.adapterError.localizedDescription ?: NSNull.null,
        @"adapter": @{
            @"device": adapter.device ?: NSNull.null,
            @"model": adapter.model ?: NSNull.null,
            @"serialNumber": adapter.serialNumber ?: NSNull.null,
            @"hasStatus": @(adapter.hasStatus),
            @"knobPresent": @(adapter.knobPresent),
            @"knobTenths": adapter.knobTenths ?: NSNull.null,
            @"micPresent": @(adapter.micPresent),
            @"micDE": adapter.micDE ?: NSNull.null,
            @"micDD": adapter.micDD ?: NSNull.null,
            @"missedPolls": @(adapter.missedPolls),
        },
        @"monitors": monitors,
        @"volumeDecibels": snapshot.volumeDecibels ?: NSNull.null,
        @"volumeFromKnob": @(snapshot.volumeFromKnob),
        @"startLoweredFromDecibels": snapshot.startLoweredFromDecibels ?: NSNull.null,
        @"ceilingDecibels": @(snapshot.ceilingDecibels),
        @"dimmed": @(snapshot.dimmed),
        @"applying": @(snapshot.applying),
        @"applyingGroupName": snapshot.applyingGroupName ?: NSNull.null,
        @"activeGroupName": snapshot.activeGroupName ?: NSNull.null,
        @"wokeWithoutGroup": @(snapshot.wokeWithoutGroup),
        @"mutingAll": @(snapshot.mutingAll),
        @"muteAllFromStop": @(snapshot.muteAllFromStop),
        @"levelAwaitsKnob": @(snapshot.levelAwaitsKnob),
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
            reply[@"windowShowing"] = @(app.debugWindow.showing);
            reply[@"windowApplyError"] = app.debugWindow.applyError ?: NSNull.null;
            reply[@"skinName"] = preferences.skinName;
            reply[@"windowSkin"] = app.debugSkinChoice.skin.name;
            reply[@"skinRefusal"] = app.debugSkinChoice.refusal ?: NSNull.null;
            reply[@"opensWindowAtLaunch"] = @(preferences.opensWindowAtLaunch);
            reply[@"osd"] = @{
                @"showsOSD": @(preferences.showsOSD),
                @"placement": QLMOSDPlacementName(preferences.osdPlacement),
                @"seconds": @(preferences.osdSeconds),
                @"showing": @(app.debugOSD.showing),
            };
            return reply;
        }),
        QLMDebugVerb(@"popover <show|close>", QLM_HANDLER {
            BOOL show = NO;
            if (!QLMDebugParseWord(tokens[1], @"show", @"close", &show)) {
                return nil;
            }
            if (show) {
                [app debugShowPopover];
            } else {
                [app.debugPopover close];
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
        // A look at a skin, with the mockups' sample text, for
        // dump_screenshot, without choosing it. It drives nothing.
        QLMDebugVerb(@"skin_preview <name> <window|disabled|osd>", QLM_HANDLER {
            NSUInteger look = [@[@"window", @"disabled", @"osd"] indexOfObject:tokens[2].lowercaseString];
            if (look == NSNotFound) {
                return nil;
            }
            return [app debugShowSkinPreview:tokens[1] osd:look == 2 disabled:look == 1];
        }),
        QLMDebugVerb(@"window <show|close>", QLM_HANDLER {
            BOOL show = NO;
            if (!QLMDebugParseWord(tokens[1], @"show", @"close", &show)) {
                return nil;
            }
            if (show) {
                [app debugShowWindow];
            } else {
                [app.debugWindow close];
            }
            NSMutableDictionary *reply = [QLMDebugWindows(app) mutableCopy];
            reply[@"windowShowing"] = @(app.debugWindow.showing);
            return reply;
        }),
        // The window's content size in points, as a drag of its corner sets
        // it, for dump_screenshot past the skin's size.
        QLMDebugVerb(@"window_size <width> <height>", QLM_HANDLER {
            double width = 0;
            double height = 0;
            if (!QLMDebugParseFinite(tokens[1], &width) || !QLMDebugParseFinite(tokens[2], &height)) {
                return nil;
            }
            NSString *refusal = [app.debugWindow resizeTo:NSMakeSize(width, height)];
            NSSize size = app.debugWindow.contentSize;
            return QLMDebugResult(refusal, @{@"ok": @YES, @"width": @(size.width), @"height": @(size.height)});
        }),
        // The window's group button. The apply's own refusal comes later, in
        // dump_state's windowApplyError.
        QLMDebugVerb(@"group <name>", QLM_HANDLER {
            NSString *refusal = [app.debugWindow clickGroupNamed:tokens[1]];
            return QLMDebugResult(refusal, @{@"ok": @YES, @"group": tokens[1]});
        }),
        // The skin Settings' picker chooses, kept in the preferences. The
        // skin that shows loads again.
        QLMDebugVerb(@"skin <name>", QLM_HANDLER {
            NSString *refusal = [app debugChooseSkin:tokens[1]];
            return QLMDebugResult(refusal, @{@"ok": @YES, @"skinName": app.debugPreferences.skinName});
        }),
        // The OSD as a turn of the knob shows it, for dump_screenshot.
        QLMDebugVerb(@"osd <show|hide>", QLM_HANDLER {
            BOOL show = NO;
            if (!QLMDebugParseWord(tokens[1], @"show", @"hide", &show)) {
                return nil;
            }
            NSString *refusal = nil;
            if (show) {
                refusal = [app.debugOSD showSnapshot:app.debugSnapshot];
            } else {
                [app.debugOSD hide];
            }
            return QLMDebugResult(refusal, @{@"ok": @YES, @"showing": @(app.debugOSD.showing)});
        }),
        // The fake bus's knob, as its window's slider turns it, in tenths of
        // a dB.
        QLMDebugVerb(@"fake_knob <tenths>", QLM_HANDLER {
            NSInteger tenths = 0;
            NSScanner *scanner = [NSScanner scannerWithString:tokens[1]];
            if (![scanner scanInteger:&tenths] || !scanner.atEnd) {
                return nil;
            }
            QLMFakeBus *bus = app.debugFakeBus;
            NSString *refusal = nil;
            if (bus == nil) {
                refusal = @"qlm drives the GLM adapter, not the fake bus";
            } else if (![bus turnKnobToTenths:tenths]) {
                refusal = [NSString stringWithFormat:@"%ld is outside the knob's travel, %ld to 0", (long)tenths,
                                                     (long)QLMFakeKnobBottomTenths];
            }
            return QLMDebugResult(refusal, @{@"ok": @YES, @"knobTenths": @(tenths)});
        }),
        // The read lands on a utility queue, so the reply only acknowledges it.
        QLMDebugVerb(@"read_setup", QLM_HANDLER {
            [app debugReadSetup];
            return @{@"ok": @YES, @"reading": @YES};
        }),
        // The popover's slider and the window's knob: GLM's 0.5 dB steps, from
        // the range's bottom to the ceiling.
        QLMDebugLevel(@"volume <dB>", @"slider", ^NSString *(id<QLMDebugApp> app, double stepped, double *level) {
            [app.debugSystem setVolumeDecibels:stepped];
            *level = stepped;
            return nil;
        }),
        // The knob turns only while the window shows.
        QLMDebugLevel(@"knob <dB>", @"knob", ^NSString *(id<QLMDebugApp> app, double stepped, double *level) {
            return [app.debugWindow turnKnobTo:stepped level:level];
        }),
        // Settings' ceiling. It refuses what the field refuses, and the
        // preferences bound the rest, as they do a typed one.
        QLMDebugVerb(@"ceiling <dB>", QLM_HANDLER {
            double decibels = 0;
            if (!QLMDebugParseFinite(tokens[1], &decibels)) {
                return nil;
            }
            NSString *refusal = QLMTypedLevelRefusal(decibels);
            if (refusal != nil) {
                return QLMDebugError(@"%@", refusal);
            }
            if (![app.debugPreferences saveCeilingDecibels:decibels]) {
                return QLMDebugError(@"The preferences refused %g dB", decibels);
            }
            [app debugVolumeRangeDidChange];
            return @{@"ok": @YES, @"ceilingDecibels": @(app.debugPreferences.ceilingDecibels)};
        }),
        // Settings' checkbox, "Drive the real monitors through the GLM
        // adapter". A change starts a new System. Turning it off stops the
        // real monitors, so where the louder alert would show, it refuses.
        QLMDebugVerb(@"adapter <on|off>", QLM_HANDLER {
            BOOL on = NO;
            if (!VibeParseOnOff(tokens, &on)) {
                return nil;
            }
            BOOL changed = on != app.debugPreferences.usesAdapter;
            if (changed && !on && app.debugQuitAsksFirst) {
                return QLMDebugError(@"turning the adapter off may make the monitors louder. Answer with adapter_off_answering");
            }
            if (changed) {
                app.debugPreferences.usesAdapter = on;
                [app debugAdapterDidChange];
            }
            return @{@"ok": @YES, @"usesAdapter": @(on), @"restarted": @(changed)};
        }),
        // The argument answers the louder alert, as quit_answering's does.
        QLMDebugVerb(@"adapter_off_answering <cancel|anyway>", QLM_HANDLER {
            BOOL cancel = NO;
            if (!QLMDebugParseWord(tokens[1], @"cancel", @"anyway", &cancel)) {
                return nil;
            }
            BOOL anyway = !cancel;
            BOOL asks = app.debugQuitAsksFirst;
            BOOL turningOff = app.debugPreferences.usesAdapter && (!asks || anyway);
            if (turningOff) {
                app.debugPreferences.usesAdapter = NO;
                [app debugAdapterDidChange];
            }
            QLMSnapshot *snapshot = app.debugSnapshot;
            return @{
                @"ok": @YES,
                @"asksFirst": @(asks),
                @"restarted": @(turningOff),
                @"handBack": snapshot ? QLMDebugHandBack(snapshot) : NSNull.null,
            };
        }),
        // A monitor's mute button takes a click while System tracks it.
        QLMDebugVerb(@"mute <serial> <on|off>", QLM_HANDLER {
            BOOL on = NO;
            if (!VibeParseOnOff(@[tokens[0], tokens[2]], &on)) {
                return nil;
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
        QLMDebugControl(@"mute_all <on|off>", YES, QLM_HANDLER {
            BOOL on = NO;
            if (!VibeParseOnOff(tokens, &on)) {
                return nil;
            }
            [app.debugSystem setAllMuted:on];
            return @{@"ok": @YES, @"allMuted": @(on)};
        }),
        QLMDebugControl(@"dim <on|off>", NO, QLM_HANDLER {
            BOOL on = NO;
            if (!VibeParseOnOff(tokens, &on)) {
                return nil;
            }
            [app.debugSystem setDimmed:on];
            return @{@"ok": @YES, @"dimmed": @(on)};
        }),
        // The power button reads Standby while a monitor is on, and Wake
        // while none is. Each verb takes only its own reading.
        QLMDebugControl(@"standby", YES, QLM_HANDLER {
            if (!app.debugSnapshot.anyOn) {
                return QLMDebugError(@"no monitor is on, so the power button reads Wake");
            }
            [app.debugSystem sleep];
            return @{@"ok": @YES};
        }),
        QLMDebugControl(@"wake", YES, QLM_HANDLER {
            if (app.debugSnapshot.anyOn) {
                return QLMDebugError(@"a monitor is on, so the power button reads Standby");
            }
            [app.debugSystem wake];
            return @{@"ok": @YES};
        }),
        // GLM may ask to save first. It is never forced.
        QLMDebugVerb(@"quit_glm", QLM_HANDLER {
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
        // from the run loop, after the reply. Where the alert would show, a
        // cancel does nothing.
        QLMDebugVerb(@"quit_answering <cancel|anyway>", QLM_HANDLER {
            BOOL cancel = NO;
            if (!QLMDebugParseWord(tokens[1], @"cancel", @"anyway", &cancel)) {
                return nil;
            }
            BOOL anyway = !cancel;
            BOOL asks = app.debugQuitAsksFirst;
            BOOL quitting = !asks || anyway;
            if (quitting) {
                __weak id<QLMDebugApp> weakApp = app;
                CFRunLoopRef main = CFRunLoopGetMain();
                CFRunLoopPerformBlock(main, kCFRunLoopCommonModes, ^{
                    [weakApp debugQuitAnswering:anyway];
                });
                CFRunLoopWakeUp(main);
            }
            QLMSnapshot *snapshot = app.debugSnapshot;
            return @{
                @"ok": @YES,
                @"asksFirst": @(asks),
                @"quitting": @(quitting),
                @"handBack": snapshot ? QLMDebugHandBack(snapshot) : NSNull.null,
            };
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
    // TRAP: a window behind the Terminal, as in a hardware run, draws no
    // snapshot, so these would read stale content.
    if ([@[@"dump_screenshot", @"dump_view_tree"] containsObject:verb]) {
        [app debugDrawWindows];
    }
    // TRAP: a screenshot renders the presentation tree, so within an ease
    // of a level change it would catch the pointer or the bar on the way.
    if ([verb isEqualToString:@"dump_screenshot"]) {
        QLMSkinFinishEases();
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
