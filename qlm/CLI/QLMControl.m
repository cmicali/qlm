#import "QLMControl.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>

#import "QLMAdapter.h"
#include "QLMCommands.h"
#import "QLMFakeBus.h"
#include "QLMReplies.h"

// 10 dB under System's default ceiling, for the first runs on the monitors.
const double QLMCeilingLimit = -30;

// For docs/experiments.md's Part B, whose longest interval is 3.2 s.
const NSTimeInterval QLMAdapterPollLimit = 10;

@interface QLMControlOptions ()
@property (nonatomic, readwrite) BOOL fake;
@property (nonatomic, readwrite, nullable) NSString *replayPath;
@property (nonatomic, readwrite) BOOL dryRun;
@property (nonatomic, readwrite) BOOL on;
@property (nonatomic, readwrite, nullable) NSNumber *volumeDecibels;
@property (nonatomic, readwrite, nullable) NSString *serial;
@property (nonatomic, readwrite) NSArray<NSString *> *mutedSerials;
@property (nonatomic, readwrite) BOOL launch;
@property (nonatomic, readwrite) BOOL unverifiedRate;
@property (nonatomic, readwrite) double ceilingDecibels;
@property (nonatomic, readwrite) NSTimeInterval seconds;
@property (nonatomic, readwrite, nullable) NSNumber *adapterPollSeconds;
@end

// Only the whole text, and only a finite number. Otherwise `problem` says
// the text is not `what`.
static BOOL QLMReadNumber(NSString *text, NSString *what, double *value, NSString **problem) {
    const char *utf8 = text.UTF8String;
    char *end = NULL;
    double parsed = strtod(utf8, &end);
    if (end == utf8 || *end != '\0' || !isfinite(parsed)) {
        *problem = [NSString stringWithFormat:@"'%@' is not %@", text, what];
        return NO;
    }
    *value = parsed;
    return YES;
}

// TRAP: an argument read loosely is a safety hole. A mistyped --dry-run
// would send for real, and --replay without its file would mean USB.
static NSDictionary<NSString *, NSString *> *_Nullable QLMReadArguments(NSArray<NSString *> *arguments, NSSet<NSString *> *flags,
                                                                        NSSet<NSString *> *valued, NSString *_Nullable *_Nullable positional,
                                                                        NSString **problem) {
    *problem = nil;
    NSMutableDictionary<NSString *, NSString *> *given = [NSMutableDictionary dictionary];  // a flag maps to itself
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *argument = arguments[i];
        if (given[argument] != nil) {
            *problem = [NSString stringWithFormat:@"%@ is given twice", argument];
            return nil;
        }
        if ([flags containsObject:argument]) {
            given[argument] = argument;
        } else if ([valued containsObject:argument]) {
            if (i + 1 >= arguments.count) {
                *problem = [NSString stringWithFormat:@"%@ needs a value", argument];
                return nil;
            }
            given[argument] = arguments[++i];
        } else if (positional != NULL && *positional == nil && ![argument hasPrefix:@"--"]) {
            *positional = argument;
        } else {
            *problem = [NSString stringWithFormat:@"unknown argument '%@'", argument];
            return nil;
        }
    }
    if (given[@"--fake"] != nil && given[@"--replay"] != nil) {
        *problem = @"--fake and --replay name different buses";
        return nil;
    }
    double seconds = 0;
    if (given[@"--seconds"] != nil && !QLMReadNumber(given[@"--seconds"], @"a number of seconds", &seconds, problem)) {
        return nil;
    }
    if (seconds < 0) {
        *problem = @"--seconds may not be negative";
        return nil;
    }
    return given;
}

NSDictionary<NSString *, NSString *> *QLMQueryArguments(NSString *command, NSArray<NSString *> *arguments, NSString **problem) {
    NSDictionary<NSString *, NSArray<NSString *> *> *options = @{
        @"info": @[@"--replay"],
        @"discover": @[@"--replay", @"--setup", @"--seconds"],
        @"poll": @[@"--replay", @"--seconds"],
    };
    NSCParameterAssert(options[command] != nil);
    return QLMReadArguments(arguments, [NSSet setWithObject:@"--fake"], [NSSet setWithArray:options[command]], NULL, problem);
}

NSDictionary<NSString *, NSString *> *QLMCompareArguments(NSArray<NSString *> *arguments, NSString **problem) {
    if (arguments.count < 2 || [arguments[0] hasPrefix:@"--"] || [arguments[1] hasPrefix:@"--"]) {
        *problem = @"compare-apply takes a setup file and a capture's reports.txt, then its options";
        return nil;
    }
    NSArray<NSString *> *options = [arguments subarrayWithRange:NSMakeRange(2, arguments.count - 2)];
    NSMutableDictionary<NSString *, NSString *> *given =
        [QLMReadArguments(options, [NSSet set], [NSSet setWithArray:@[@"--group", @"--from", @"--to"]], NULL, problem) mutableCopy];
    double from = 0;
    double to = INFINITY;
    if (given == nil || (given[@"--from"] != nil && !QLMReadNumber(given[@"--from"], @"a number of seconds", &from, problem)) ||
        (given[@"--to"] != nil && !QLMReadNumber(given[@"--to"], @"a number of seconds", &to, problem))) {
        return nil;
    }
    if (given[@"--group"] == nil) {
        *problem = @"compare-apply needs --group, the group the capture's apply switched to";
        return nil;
    }
    if (from < 0 || from >= to) {
        *problem = @"the window must run forward from 0 s or later";
        return nil;
    }
    given[@"setup"] = arguments[0];
    given[@"reports"] = arguments[1];
    return given;
}

@implementation QLMControlOptions

+ (instancetype)optionsForCommand:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments problem:(NSString **)problem {
    NSMutableSet<NSString *> *flags = [NSMutableSet setWithObjects:@"--fake", @"--dry-run", nil];
    NSMutableSet<NSString *> *valued = [NSMutableSet setWithObjects:@"--replay", @"--seconds", @"--muted", nil];
    BOOL takesPositional = YES;
    switch (command) {
    case QLMControlCommandVolume:
        [flags addObject:@"--allow-high-ceiling"];
        [valued addObjectsFromArray:@[@"--ceiling", @"--adapter-poll"]];
        break;
    case QLMControlCommandDim:
        [flags addObject:@"--allow-high-ceiling"];
        [valued addObjectsFromArray:@[@"--ceiling", @"--volume"]];
        break;
    case QLMControlCommandMute:
        [valued addObject:@"--serial"];
        break;
    case QLMControlCommandSleep:
        takesPositional = NO;
        break;
    case QLMControlCommandWake:
        [flags addObject:@"--allow-high-ceiling"];
        [valued addObjectsFromArray:@[@"--ceiling", @"--volume"]];
        takesPositional = NO;
        break;
    case QLMControlCommandApplyGroup:
        [flags addObjectsFromArray:@[@"--allow-high-ceiling", @"--launch", @"--unverified-rate"]];
        [valued addObjectsFromArray:@[@"--ceiling", @"--volume"]];
        takesPositional = NO;
        break;
    }

    NSString *positional = nil;
    NSDictionary<NSString *, NSString *> *given = QLMReadArguments(arguments, flags, valued, takesPositional ? &positional : NULL, problem);
    if (given == nil) {
        return nil;
    }

    QLMControlOptions *options = [[QLMControlOptions alloc] init];
    options.fake = given[@"--fake"] != nil;
    options.replayPath = given[@"--replay"];
    options.dryRun = given[@"--dry-run"] != nil;
    options.serial = given[@"--serial"];
    options.launch = given[@"--launch"] != nil;
    options.unverifiedRate = given[@"--unverified-rate"] != nil;
    options.mutedSerials = @[];
    NSString *muted = given[@"--muted"];
    if (muted != nil) {
        NSMutableArray<NSString *> *serials = [NSMutableArray array];
        for (NSString *item in [muted componentsSeparatedByString:@","]) {
            NSString *serial = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (serial.length == 0) {
                *problem = @"--muted takes serials separated by commas, with none empty";
                return nil;
            }
            [serials addObject:serial];
        }
        options.mutedSerials = serials;
    }

    if (takesPositional && positional == nil) {
        *problem = command == QLMControlCommandVolume ? @"volume needs a level in dB" : @"give on or off";
        return nil;
    }
    if (command == QLMControlCommandMute || command == QLMControlCommandDim) {
        if (![positional isEqualToString:@"on"] && ![positional isEqualToString:@"off"]) {
            *problem = [NSString stringWithFormat:@"'%@' is not on or off", positional];
            return nil;
        }
        options.on = [positional isEqualToString:@"on"];
    }
    double number = 0;
    NSString *level = command == QLMControlCommandVolume ? positional : given[@"--volume"];
    if (level != nil) {
        if (!QLMReadNumber(level, @"a level in dB", &number, problem)) {
            return nil;
        }
        options.volumeDecibels = @(number);
    }
    options.seconds = given[@"--seconds"].doubleValue;
    NSString *adapterPoll = given[@"--adapter-poll"];
    if (adapterPoll != nil) {
        if (!QLMReadNumber(adapterPoll, @"a number of seconds", &number, problem)) {
            return nil;
        }
        if (number < 0 || number > QLMAdapterPollLimit) {
            *problem = [NSString stringWithFormat:@"--adapter-poll takes 0 to %.0f seconds", QLMAdapterPollLimit];
            return nil;
        }
        options.adapterPollSeconds = @(number);
    }

    options.ceilingDecibels = QLMCeilingLimit;
    NSString *ceiling = given[@"--ceiling"];
    if (ceiling != nil) {
        if (!QLMReadNumber(ceiling, @"a ceiling in dB", &number, problem)) {
            return nil;
        }
        if (number > QLMVolumeDecibelsMax) {
            *problem = @"the ceiling may not be above 0 dB";
            return nil;
        }
        if (number > QLMCeilingLimit && given[@"--allow-high-ceiling"] == nil) {
            *problem = [NSString stringWithFormat:@"a ceiling above %.0f dB takes --allow-high-ceiling", QLMCeilingLimit];
            return nil;
        }
        options.ceilingDecibels = number;
    }

    // apply-group's dry run reads only the setup file.
    BOOL reachesUSB = options.overUSB && !(command == QLMControlCommandApplyGroup && options.dryRun);
    BOOL sendsVolume = command == QLMControlCommandDim || options.volumeDecibels != nil;
    if (reachesUSB && sendsVolume && ceiling == nil) {
        *problem = [NSString stringWithFormat:@"over USB, a command that sends a level needs --ceiling, at most %.0f dB", QLMCeilingLimit];
        return nil;
    }
    if (options.overUSB && command == QLMControlCommandDim && options.volumeDecibels == nil) {
        *problem = @"over USB, dim needs --volume, the level to dim from";
        return nil;
    }
    if (!options.dryRun && command == QLMControlCommandApplyGroup && options.volumeDecibels == nil) {
        *problem = @"apply-group needs --volume, the level to restore";
        return nil;
    }
    if (options.volumeDecibels != nil && options.volumeDecibels.doubleValue > options.ceilingDecibels) {
        *problem = [NSString stringWithFormat:@"%.1f dB is above the ceiling, %.1f dB", options.volumeDecibels.doubleValue,
                                              options.ceilingDecibels];
        return nil;
    }
    return options;
}

- (BOOL)overUSB {
    return !self.fake && self.replayPath == nil;
}

- (QLMSystemSettings *)settings {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.ceilingDecibels = self.ceilingDecibels;
    settings.allowsUnverifiedRates = self.unverifiedRate;
    if (self.adapterPollSeconds != nil) {
        settings.adapterPollInterval = self.adapterPollSeconds.doubleValue;
        settings.adapterPollsPerRound = 1;
    }
    return settings;
}

- (NSString *)adapterPollText {
    NSTimeInterval glm = [[QLMSystemSettings alloc] init].adapterPollInterval;
    if (self.adapterPollSeconds == nil) {
        return [NSString stringWithFormat:@"qlm polls the adapter as GLM does, with a pair of 01 08 every %g s.", glm];
    }
    double seconds = self.adapterPollSeconds.doubleValue;
    NSString *when = seconds > 0 ? [NSString stringWithFormat:@"every %g s", seconds] : @"at start only";
    return [NSString stringWithFormat:@"qlm polls the adapter with one 01 08 %@, in place of GLM's pair every %g s.", when, glm];
}

@end

#pragma mark - Waiting

QLMSnapshot *QLMWaitForSnapshot(QLMSystem *system, NSTimeInterval timeout, QLMCallNumber (^action)(void), QLMSnapshotTest test) {
    QLMCallNumber after = 0;
    if (action != nil) {
        after = action();
        if (after == 0) {
            return nil;
        }
    }
    dispatch_semaphore_t passed = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_queue_create("qlmctl.wait", DISPATCH_QUEUE_SERIAL);
    __block QLMSnapshot *result = nil;
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        if (result == nil && snapshot.lastCall >= after && test(snapshot)) {
            result = snapshot;
            dispatch_semaphore_signal(passed);
        }
    } queue:queue];
    [system.settings.clock wait:passed timeout:timeout];
    [system setSnapshotHandler:nil queue:queue];
    __block QLMSnapshot *found = nil;
    dispatch_sync(queue, ^{
        found = result;
    });
    return found;
}

#pragma mark - The dry run

// The fake answers at once. A change in telemetry shows by the next cycle.
static const NSTimeInterval QLMMirrorTimeout = 5;

// The mirror's monitors go in the order of their sessions, so the fake bus
// answers the probe in that order and the leases come out alike.
static QLMFakeBus *QLMMirrorBus(QLMSnapshot *discovered) {
    NSArray<QLMMonitorState *> *found =
        [discovered.monitors sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"session" ascending:YES]]];
    NSMutableArray<QLMFakeMonitor *> *monitors = [NSMutableArray arrayWithCapacity:found.count];
    for (QLMMonitorState *monitor in found) {
        uint8_t deviceClass = monitor.deviceClass == QLMMonitorClassSubwoofer ? QLMTelemetryClassSubwoofer : QLMTelemetryClassTwoWay;
        QLMFakeMonitor *mirror = [[QLMFakeMonitor alloc] initWithHardwareID:monitor.hardwareID
                                                               serialNumber:monitor.serialNumber ?: @""
                                                                 systemInfo:monitor.systemInfo ?: @""
                                                                deviceClass:deviceClass];
        mirror.on = monitor.status != QLMMonitorStatusStandby;
        [monitors addObject:mirror];
    }
    QLMFakeBus *bus = [[QLMFakeBus alloc] initWithMonitors:monitors];
    NSNumber *knob = discovered.adapter.knobTenths;
    [bus perform:^{
        bus.knobTenths = knob;
    }];
    return bus;
}

static BOOL QLMRecordIs(NSData *record, QLMMessage message) {
    return [record isEqualToData:QLMAdapterRecord(&message)];
}

// What discover sends too, to a monitor or to the adapter.
static BOOL QLMIsDiscovery(NSData *record) {
    const uint8_t *bytes = record.bytes;
    uint8_t address = bytes[0];
    if (QLMRecordIs(record, QLMCommandProbe()) || QLMRecordIs(record, QLMCommandPoll(address)) ||
        QLMRecordIs(record, QLMCommandSerialNumber(address)) || QLMRecordIs(record, QLMCommandSystemInfo(address))) {
        return YES;
    }
    // A lease: the address, then 02, the hardware ID, and the session.
    return record.length == 6 && QLMRecordIs(record, QLMCommandAssignSession(bytes + 2, bytes[5]));
}

NSSet<NSData *> *QLMHardwareIDsForSerials(NSArray<NSString *> *serials, QLMSnapshot *discovered, NSString **problem) {
    *problem = nil;
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    for (NSString *serial in serials) {
        NSMutableArray<QLMMonitorState *> *matches = [NSMutableArray array];
        for (QLMMonitorState *monitor in discovered.monitors) {
            if ([monitor.serialNumber containsString:serial]) {
                [matches addObject:monitor];
            }
        }
        if (matches.count != 1) {
            *problem = [NSString stringWithFormat:@"%lu monitors match '%@'", (unsigned long)matches.count, serial];
            return nil;
        }
        [hardwareIDs addObject:matches[0].hardwareID];
    }
    return hardwareIDs;
}

QLMSnapshot *QLMWaitForEffect(QLMSystem *system, QLMSnapshot *discovered, NSArray<NSString *> *mutedSerials, QLMControlAction action,
                               QLMSnapshotTest effect, NSTimeInterval timeout, int *status) {
    *status = 0;
    NSString *problem = nil;
    NSSet<NSData *> *hardwareIDs = QLMHardwareIDsForSerials(mutedSerials, discovered, &problem);
    if (hardwareIDs == nil) {
        fprintf(stderr, "qlmctl: --muted: %s\n", problem.UTF8String);
        *status = EX_DATAERR;
        return nil;
    }
    return QLMWaitForSnapshot(system, timeout, ^QLMCallNumber {
        [system recordMutedHardwareIDs:hardwareIDs];
        return action(system, discovered, status);
    }, effect);
}

NSString *QLMHandBackText(QLMHandBack *handBack) {
    switch (handBack.kind) {
    case QLMHandBackKnobLevel:
        return [NSString stringWithFormat:@"qlm sent the knob's level, %.1f dB, as it stopped, so the adapter's take-over "
                                          @"about 2.6 s later changes nothing.",
                                          handBack.knobDecibels.doubleValue];
    case QLMHandBackLouder:
        return [NSString stringWithFormat:@"about 2.6 s after qlm stops, the adapter takes over at the knob's %.1f dB, "
                                          @"louder than qlm's %.1f dB. Turn the knob down.",
                                          handBack.knobDecibels.doubleValue, handBack.volumeDecibels.doubleValue];
    case QLMHandBackUnknown:
        break;
    }
    NSString *why = handBack.knobDecibels == nil ? @"no knob is in" : @"no volume was set";
    return [NSString stringWithFormat:@"about 2.6 s after qlm stops, the adapter takes over with its own level, unknown "
                                      @"here because %@.",
                                      why];
}

QLMControlAction QLMVolumeAction(double decibels, BOOL fewerAdapterPolls) {
    return ^QLMCallNumber(QLMSystem *system, QLMSnapshot *discovered, int *status) {
        NSNumber *knob = discovered.adapter.knobTenths;
        if (fewerAdapterPolls && knob == nil) {
            fputs("qlmctl: --adapter-poll needs the knob in. With fewer polls, the adapter may take over during the run, "
                  "at a level qlm can't know.\n",
                  stderr);
            *status = EX_DATAERR;
            return 0;
        }
        if (fewerAdapterPolls) {
            // System's hand-back rule: the knob's word against the word that goes out.
            QLMMessage level = QLMCommandVolume(decibels, system.settings.ceilingDecibels);
            uint32_t word = 0;
            QLMVolumeFrameWord(&level, &word);
            double knobDecibels = knob.doubleValue / 10.0;
            if (QLMVolumeWordForDecibels(knobDecibels) > word) {
                fprintf(stderr, "qlmctl: --adapter-poll needs the knob at or below %.1f dB, and it reads %.1f dB. With fewer "
                                "polls, the adapter may take over during the run, at the knob's level. Turn the knob down first.\n",
                        QLMVolumeDecibelsForWord(word), knobDecibels);
                *status = EX_DATAERR;
                return 0;
            }
        }
        return [system setVolumeDecibels:decibels];
    };
}

QLMControlAction QLMDimAction(BOOL on, NSNumber *volumeDecibels) {
    return ^QLMCallNumber(QLMSystem *system, QLMSnapshot *discovered, int *status) {
        [system setDimmed:!on];
        if (volumeDecibels != nil) {
            [system setVolumeDecibels:volumeDecibels.doubleValue];
        }
        return [system setDimmed:on];
    };
}

QLMControlAction QLMWakeAction(NSNumber *volumeDecibels) {
    return ^QLMCallNumber(QLMSystem *system, QLMSnapshot *discovered, int *status) {
        if (volumeDecibels != nil) {
            [system setVolumeDecibels:volumeDecibels.doubleValue];
        }
        return [system wake];
    };
}

NSArray<NSData *> *QLMDryRunRecords(QLMSnapshot *discovered, QLMSystemSettings *settings, NSArray<NSString *> *mutedSerials,
                                    QLMControlAction action, QLMSnapshotTest effect, int *status) {
    QLMFakeBus *bus = QLMMirrorBus(discovered);
    QLMSystemSettings *mirrorSettings = [settings copy];
    mirrorSettings.adapterPollInterval = 0;
    QLMSystem *mirror = [[QLMSystem alloc] initWithAdapter:bus settings:mirrorSettings];
    NSUInteger count = discovered.monitors.count;
    QLMSnapshot *found = QLMWaitForSnapshot(mirror, QLMMirrorTimeout, ^QLMCallNumber {
        return [mirror start];
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allIdentified && snapshot.monitors.count == count;
    });
    if (found == nil) {
        [mirror stop];
        *status = EX_SOFTWARE;
        return nil;
    }
    uint8_t addresses[256];
    for (unsigned i = 0; i < 256; i++) {
        addresses[i] = (uint8_t)i;
    }
    for (QLMMonitorState *monitor in found.monitors) {
        for (QLMMonitorState *original in discovered.monitors) {
            if ([original.hardwareID isEqualToData:monitor.hardwareID]) {
                addresses[monitor.session] = original.session;
            }
        }
    }

    NSUInteger start = bus.sentMessages.count;
    QLMSnapshot *effected = QLMWaitForEffect(mirror, found, mutedSerials, action, effect, QLMMirrorTimeout, status);
    if (*status != 0) {
        [mirror stop];
        return nil;
    }
    if (effected == nil) {
        *status = EX_TEMPFAIL;
    }
    // Read before the stop, which may land while a send is still on the queue.
    NSArray<NSData *> *sent = bus.sentMessages;
    [mirror stop];

    NSMutableArray<NSData *> *records = [NSMutableArray array];
    for (NSUInteger i = start; i < sent.count; i++) {
        if (QLMIsDiscovery(sent[i])) {
            continue;
        }
        NSMutableData *record = [sent[i] mutableCopy];
        uint8_t *bytes = record.mutableBytes;
        bytes[0] = addresses[bytes[0]];
        [records addObject:record];
    }
    return records;
}

BOOL QLMVolumeFrameWord(const QLMMessage *message, uint32_t *word) {
    if (message->length != 4) {
        return NO;
    }
    uint32_t candidate = (uint32_t)message->payload[1] << 16 | (uint32_t)message->payload[2] << 8 | message->payload[3];
    QLMMessage volume = QLMCommandVolumeWord(candidate, QLMVolumeWordMax);
    if (volume.address != message->address || volume.length != message->length ||
        memcmp(volume.payload, message->payload, volume.length) != 0) {
        return NO;
    }
    *word = candidate;
    return YES;
}
