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

@interface QLMControlOptions ()
@property (nonatomic, readwrite) BOOL fake;
@property (nonatomic, readwrite, nullable) NSString *replayPath;
@property (nonatomic, readwrite) BOOL dryRun;
@property (nonatomic, readwrite) BOOL on;
@property (nonatomic, readwrite, nullable) NSNumber *volumeDecibels;
@property (nonatomic, readwrite, nullable) NSString *serial;
@property (nonatomic, readwrite) double ceilingDecibels;
@property (nonatomic, readwrite) NSTimeInterval seconds;
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

@implementation QLMControlOptions

+ (instancetype)optionsForCommand:(QLMControlCommand)command arguments:(NSArray<NSString *> *)arguments problem:(NSString **)problem {
    *problem = nil;
    NSMutableSet<NSString *> *flags = [NSMutableSet setWithObjects:@"--fake", @"--dry-run", nil];
    NSMutableSet<NSString *> *valued = [NSMutableSet setWithObjects:@"--replay", @"--seconds", nil];
    BOOL takesPositional = YES;
    switch (command) {
    case QLMControlCommandVolume:
        [flags addObject:@"--allow-high-ceiling"];
        [valued addObject:@"--ceiling"];
        break;
    case QLMControlCommandDim:
        [flags addObject:@"--allow-high-ceiling"];
        [valued addObjectsFromArray:@[@"--ceiling", @"--volume"]];
        break;
    case QLMControlCommandMute:
        [valued addObject:@"--serial"];
        break;
    case QLMControlCommandSleep:
    case QLMControlCommandWake:
        takesPositional = NO;
        break;
    }

    // TRAP: an argument read loosely is a safety hole. A mistyped --dry-run
    // would send for real, and --replay without its file would mean USB.
    NSString *positional = nil;
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
        } else if (takesPositional && positional == nil && ![argument hasPrefix:@"--"]) {
            positional = argument;
        } else {
            *problem = [NSString stringWithFormat:@"unknown argument '%@'", argument];
            return nil;
        }
    }

    QLMControlOptions *options = [[QLMControlOptions alloc] init];
    options.fake = given[@"--fake"] != nil;
    options.replayPath = given[@"--replay"];
    options.dryRun = given[@"--dry-run"] != nil;
    options.serial = given[@"--serial"];
    if (options.fake && options.replayPath != nil) {
        *problem = @"--fake and --replay name different buses";
        return nil;
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
    NSString *seconds = given[@"--seconds"];
    if (seconds != nil) {
        if (!QLMReadNumber(seconds, @"a number of seconds", &number, problem)) {
            return nil;
        }
        if (number < 0) {
            *problem = @"--seconds may not be negative";
            return nil;
        }
        options.seconds = number;
    }

    options.ceilingDecibels = QLMCeilingLimit;
    NSString *ceiling = given[@"--ceiling"];
    if (ceiling != nil) {
        if (!QLMReadNumber(ceiling, @"a ceiling in dB", &number, problem)) {
            return nil;
        }
        if (number > 0) {
            *problem = @"the ceiling may not be above 0 dB";
            return nil;
        }
        if (number > QLMCeilingLimit && given[@"--allow-high-ceiling"] == nil) {
            *problem = [NSString stringWithFormat:@"a ceiling above %.0f dB takes --allow-high-ceiling", QLMCeilingLimit];
            return nil;
        }
        options.ceilingDecibels = number;
    }

    BOOL sendsVolume = command == QLMControlCommandVolume || command == QLMControlCommandDim;
    if (options.overUSB && sendsVolume && ceiling == nil) {
        *problem = [NSString stringWithFormat:@"over USB, %@ needs --ceiling, at most %.0f dB", command == QLMControlCommandVolume ? @"volume" : @"dim",
                                              QLMCeilingLimit];
        return nil;
    }
    if (options.overUSB && command == QLMControlCommandDim && options.volumeDecibels == nil) {
        *problem = @"over USB, dim needs --volume, the level to dim from";
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
    return settings;
}

@end

#pragma mark - Waiting

QLMSnapshot *QLMWaitForSnapshot(QLMSystem *system, NSTimeInterval timeout, QLMSnapshotTest test) {
    dispatch_semaphore_t passed = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_queue_create("qlmctl.wait", DISPATCH_QUEUE_SERIAL);
    __block QLMSnapshot *result = nil;
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        if (result == nil && test(snapshot)) {
            result = snapshot;
            dispatch_semaphore_signal(passed);
        }
    } queue:queue];
    dispatch_semaphore_wait(passed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * (double)NSEC_PER_SEC)));
    [system setSnapshotHandler:nil queue:queue];
    __block QLMSnapshot *found = nil;
    dispatch_sync(queue, ^{
        found = result;
    });
    return found;
}

QLMSnapshotTest QLMAfterReplay(QLMSnapshotTest test) {
    __block BOOL replayed = NO;
    return ^BOOL(QLMSnapshot *snapshot) {
        if (!replayed) {
            replayed = YES;
            return NO;
        }
        return test(snapshot);
    };
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

NSArray<NSData *> *QLMDryRunRecords(QLMSnapshot *discovered, QLMSystemSettings *settings, QLMControlAction action, QLMSnapshotTest effect,
                                    int *status) {
    QLMFakeBus *bus = QLMMirrorBus(discovered);
    QLMSystemSettings *mirrorSettings = [settings copy];
    mirrorSettings.adapterPollInterval = 0;
    QLMSystem *mirror = [[QLMSystem alloc] initWithAdapter:bus settings:mirrorSettings];
    [mirror start];
    NSUInteger count = discovered.monitors.count;
    QLMSnapshot *found = QLMWaitForSnapshot(mirror, QLMMirrorTimeout, ^BOOL(QLMSnapshot *snapshot) {
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
    *status = action(mirror, found);
    if (*status != 0) {
        [mirror stop];
        return nil;
    }
    if (QLMWaitForSnapshot(mirror, QLMMirrorTimeout, effect) == nil) {
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
