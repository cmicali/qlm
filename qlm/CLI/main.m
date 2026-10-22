#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sysexits.h>

#import "QLMDSPBlock.h"
#import "QLMFakeBus.h"
#include "QLMFrame.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"

static void QLMPrintUsage(FILE *stream) {
    fputs("usage: qlmctl <command> [options]\n"
          "\n"
          "  discover [--fake] [--seconds N]  list every monitor once all are identified, or after N seconds\n"
          "  poll [--fake] [--seconds N]    print each monitor's telemetry as it arrives, for N seconds\n"
          "  volume <dB> [--fake]           set the volume, capped at the ceiling\n"
          "  mute <on|off> [--serial TEXT] [--fake]\n"
          "                                 mute every monitor, or the one whose serial contains TEXT\n"
          "  dim <on|off> [--fake]          dim the volume\n"
          "  sleep [--fake]                 put every monitor in standby\n"
          "  wake [--fake]                  wake every monitor\n"
          "  setup <file.sam> [--bands]     print a GLM 5 setup file\n"
          "  apply-group <file.sam> <group> --dry-run | --fake\n"
          "                                 print each monitor's DSP block frames, or apply the group\n"
          "\n"
          "The adapter over HID is not written yet, so every bus command needs --fake,\n"
          "a simulated bus of two monitors.\n",
          stream);
}

static BOOL QLMHasFlag(int argc, const char *argv[], const char *flag) {
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], flag) == 0) {
            return YES;
        }
    }
    return NO;
}

static const char *QLMOptionValue(int argc, const char *argv[], const char *option) {
    for (int i = 2; i + 1 < argc; i++) {
        if (strcmp(argv[i], option) == 0) {
            return argv[i + 1];
        }
    }
    return NULL;
}

static double QLMSecondsOption(int argc, const char *argv[], double fallback) {
    const char *seconds = QLMOptionValue(argc, argv, "--seconds");
    return seconds != NULL ? atof(seconds) : fallback;
}

#pragma mark - The bus

static const NSTimeInterval QLMDiscoveryTimeout = 3;
// Long enough for the power state to come back in the next poll.
static const NSTimeInterval QLMEffectTimeout = 5;

static QLMSystem *_Nullable QLMMakeSystem(int argc, const char *argv[]) {
    if (!QLMHasFlag(argc, argv, "--fake")) {
        fputs("qlmctl: the adapter over HID is not written yet. Use --fake.\n", stderr);
        return nil;
    }
    return [[QLMSystem alloc] initWithAdapter:[QLMFakeBus demoBusWithSubwoofer:NO] settings:[[QLMSystemSettings alloc] init]];
}

typedef BOOL (^QLMSnapshotTest)(QLMSnapshot *snapshot);

// The first snapshot that passes, or nil after the timeout.
static QLMSnapshot *_Nullable QLMWaitForSnapshot(QLMSystem *system, NSTimeInterval timeout, QLMSnapshotTest test) {
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

// TRAP: the snapshot replayed when a handler is installed may predate an
// action just taken, and a no-op can leave it already passing. This test
// skips it, so only a snapshot published after the action counts.
static QLMSnapshotTest QLMAfterReplay(QLMSnapshotTest test) {
    __block BOOL replayed = NO;
    return ^BOOL(QLMSnapshot *snapshot) {
        if (!replayed) {
            replayed = YES;
            return NO;
        }
        return test(snapshot);
    };
}

static const char *QLMStatusName(QLMMonitorStatus status) {
    switch (status) {
    case QLMMonitorStatusOn: return "on";
    case QLMMonitorStatusStandby: return "standby";
    case QLMMonitorStatusUnknown: break;
    }
    return "?";
}

static const char *QLMClassName(QLMMonitorClass deviceClass) {
    switch (deviceClass) {
    case QLMMonitorClassSubwoofer: return "subwoofer";
    case QLMMonitorClassTwoWay: return "two-way";
    case QLMMonitorClassUnknown: break;
    }
    return "?";
}

static void QLMPrintMonitors(QLMSnapshot *snapshot) {
    printf("session  class      status   temp  serial            model    firmware\n");
    for (QLMMonitorState *monitor in snapshot.monitors) {
        printf("%02X       %-10s %-8s %3ld C %-17s %-8s %s\n", monitor.session, QLMClassName(monitor.deviceClass),
               QLMStatusName(monitor.status), (long)monitor.temperature, monitor.serialNumber.UTF8String ?: "?",
               monitor.model.UTF8String ?: "?", monitor.firmwareVersion.UTF8String ?: "?");
    }
}

// Without --seconds, prints once every monitor found is identified. A probe
// goes out every cycle, so --seconds N runs for N seconds to catch late ones.
static int QLMDiscover(int argc, const char *argv[]) {
    QLMSystem *system = QLMMakeSystem(argc, argv);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    double seconds = QLMSecondsOption(argc, argv, 0);
    [system start];
    QLMSnapshot *result = nil;
    if (seconds > 0) {
        [NSThread sleepForTimeInterval:seconds];
        result = system.snapshot;
    } else {
        result = QLMWaitForSnapshot(system, QLMDiscoveryTimeout, ^BOOL(QLMSnapshot *snapshot) {
            return snapshot.allIdentified;
        }) ?: system.snapshot;
    }
    [system stop];
    if (result.monitors.count == 0) {
        fputs("qlmctl: no monitor answered\n", stderr);
        return EX_UNAVAILABLE;
    }
    QLMPrintMonitors(result);
    return 0;
}

static int QLMPoll(int argc, const char *argv[]) {
    QLMSystem *system = QLMMakeSystem(argc, argv);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    double seconds = QLMSecondsOption(argc, argv, 5);
    dispatch_queue_t printing = dispatch_queue_create("qlmctl.poll", DISPATCH_QUEUE_SERIAL);
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if (monitor.status == QLMMonitorStatusUnknown) {
                continue;
            }
            printf("%02X %-8s %3ld C  in %3ld  hf %3ld  lf %3ld  missed %lu\n", monitor.session, QLMStatusName(monitor.status),
                   (long)monitor.temperature, (long)monitor.inputMeter, (long)monitor.hfMeter, (long)monitor.lfMeter,
                   (unsigned long)monitor.missedPolls);
        }
        fflush(stdout);
    } queue:printing];
    [system start];
    [NSThread sleepForTimeInterval:seconds];
    [system stop];
    dispatch_sync(printing, ^{});
    return 0;
}

static const char *QLMDecibelsText(NSNumber *_Nullable decibels, char *buffer, size_t size) {
    if (decibels == nil) {
        return "unset";
    }
    snprintf(buffer, size, "%.1f dB", decibels.doubleValue);
    return buffer;
}

static void QLMPrintControl(QLMSnapshot *snapshot) {
    char buffer[32];
    printf("volume %s%s\n", QLMDecibelsText(snapshot.volumeDecibels, buffer, sizeof buffer), snapshot.dimmed ? ", dimmed" : "");
    printf("serial            status   muted\n");
    for (QLMMonitorState *monitor in snapshot.monitors) {
        printf("%-17s %-8s %s\n", monitor.serialNumber.UTF8String ?: "?", QLMStatusName(monitor.status), monitor.muted ? "yes" : "no");
    }
}

// Starts System, waits for every monitor to be identified, runs the action,
// waits for its effect to show, prints the result, and stops. The action
// returns an exit code.
static int QLMRunControl(int argc, const char *argv[], int (^action)(QLMSystem *system, QLMSnapshot *discovered),
                         QLMSnapshotTest effect) {
    QLMSystem *system = QLMMakeSystem(argc, argv);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    [system start];
    QLMSnapshot *discovered = QLMWaitForSnapshot(system, QLMDiscoveryTimeout, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allIdentified;
    });
    if (discovered == nil) {
        [system stop];
        fputs("qlmctl: no monitor answered\n", stderr);
        return EX_UNAVAILABLE;
    }
    int status = action(system, discovered);
    if (status == 0) {
        QLMSnapshot *result = QLMWaitForSnapshot(system, QLMEffectTimeout, effect);
        if (result == nil) {
            fputs("qlmctl: timed out waiting for the change to show\n", stderr);
            status = EX_TEMPFAIL;
        }
        QLMPrintControl(result ?: system.snapshot);
    }
    [system stop];
    return status;
}

static int QLMOnOff(const char *text, BOOL *value) {
    if (text != NULL && strcmp(text, "on") == 0) {
        *value = YES;
        return 0;
    }
    if (text != NULL && strcmp(text, "off") == 0) {
        *value = NO;
        return 0;
    }
    QLMPrintUsage(stderr);
    return EX_USAGE;
}

static int QLMVolume(int argc, const char *argv[]) {
    char *end = NULL;
    double decibels = argc >= 3 ? strtod(argv[2], &end) : 0;
    if (argc < 3 || end == argv[2] || *end != '\0') {
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
    return QLMRunControl(argc, argv, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        [system setVolumeDecibels:decibels];
        return 0;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.volumeDecibels isEqualToNumber:@(decibels)];
    });
}

static int QLMMute(int argc, const char *argv[]) {
    BOOL muted = NO;
    int usage = QLMOnOff(argc >= 3 ? argv[2] : NULL, &muted);
    if (usage != 0) {
        return usage;
    }
    const char *serial = QLMOptionValue(argc, argv, "--serial");
    __block NSData *target = nil;  // nil for every monitor
    return QLMRunControl(argc, argv, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        if (serial == NULL) {
            [system setAllMuted:muted];
            return 0;
        }
        NSArray<QLMMonitorState *> *matches = [discovered.monitors filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(QLMMonitorState *monitor, NSDictionary *bindings) {
                return [monitor.serialNumber containsString:@(serial)];
            }]];
        if (matches.count != 1) {
            fprintf(stderr, "qlmctl: %lu monitors match '%s'\n", (unsigned long)matches.count, serial);
            return EX_DATAERR;
        }
        target = matches[0].hardwareID;
        [system setMuted:muted forMonitorWithHardwareID:target];
        return 0;
    }, QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        if (!snapshot.idle) {
            return NO;
        }
        if (target == nil) {
            return snapshot.allMuted == muted;
        }
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if ([monitor.hardwareID isEqualToData:target]) {
                return monitor.muted == muted;
            }
        }
        return NO;
    }));
}

static int QLMDim(int argc, const char *argv[]) {
    BOOL dimmed = NO;
    int usage = QLMOnOff(argc >= 3 ? argv[2] : NULL, &dimmed);
    if (usage != 0) {
        return usage;
    }
    // No volume is set here, so dim sends nothing and the replay may pass.
    return QLMRunControl(argc, argv, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        [system setDimmed:dimmed];
        return 0;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.dimmed == dimmed;
    });
}

// The power state comes back in telemetry. After a wake the monitors are
// found again under new sessions, so wait for all of them.
static int QLMPower(int argc, const char *argv[], BOOL wake) {
    QLMMonitorStatus wanted = wake ? QLMMonitorStatusOn : QLMMonitorStatusStandby;
    __block NSUInteger count = 0;
    return QLMRunControl(argc, argv, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        count = discovered.monitors.count;
        if (wake) {
            [system wake];
        } else {
            [system sleep];
        }
        return 0;
    }, QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        if (!snapshot.idle || snapshot.monitors.count != count) {
            return NO;
        }
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if (monitor.status != wanted) {
                return NO;
            }
        }
        return YES;
    }));
}

static int QLMSleep(int argc, const char *argv[]) {
    return QLMPower(argc, argv, NO);
}

static int QLMWake(int argc, const char *argv[]) {
    return QLMPower(argc, argv, YES);
}

#pragma mark - Setup files

static const char *QLMBandTypeName(QLMSetupBandType type) {
    switch (type) {
    case QLMSetupBandLowShelf: return "low shelf";
    case QLMSetupBandHighShelf: return "high shelf";
    case QLMSetupBandPeak: return "peak";
    }
    return "?";
}

static int QLMPrintSetup(int argc, const char *argv[]) {
    if (argc < 3) {
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readFileAtPath:@(argv[2]) error:&error];
    if (setup == nil) {
        NSNumber *line = error.userInfo[QLMSetupErrorLineKey];
        fprintf(stderr, "qlmctl: %s%s%s\n", error.localizedDescription.UTF8String,
                line != nil ? " at line " : "", line != nil ? line.stringValue.UTF8String : "");
        return EX_DATAERR;
    }
    printf("%s, GLM %s\n", setup.setupName.UTF8String ?: "(unnamed setup)", setup.glmVersion.UTF8String ?: "?");
    printf("volume %.1f dB%s%s, startup %.1f dB%s, active group %ld\n", setup.volume, setup.volumeMute ? ", muted" : "",
           setup.volumeDim ? ", dimmed" : "", setup.startupLevel, setup.startupLevelEnabled ? "" : " (off)",
           (long)setup.activeGroup);
    printf("\ndevices\n");
    for (QLMSetupDevice *device in setup.devices) {
        printf("  %-7s type %ld  serial %-8s  %-18s firmware %s\n", device.model.UTF8String, (long)device.type,
               device.serial.UTF8String ?: "?", device.name.UTF8String, device.microVersion.UTF8String ?: "?");
    }
    for (QLMSetupGroup *group in setup.groups) {
        printf("\ngroup %s, crossover %.0f Hz", group.name.UTF8String, group.crossover);
        if (group.volumePreset1 != nil) {
            printf(", presets %.1f and %.1f dB", group.volumePreset1.doubleValue, group.volumePreset2.doubleValue);
        }
        printf("\n");
        for (QLMSetupNode *node in group.nodes) {
            QLMSetupDevice *device = [setup deviceWithSerial:node.serial];
            NSUInteger active = 0;
            double rate = 0;
            for (QLMSetupBand *band in node.bands) {
                if (band.gain != 0) {
                    active++;
                }
                rate = band.sampleRate;
            }
            printf("  %-7s %-8s %-3s level %6.2f dB  input %ld  crossover %3.0f Hz  %lu of %lu bands at %.0f Hz",
                   device.model.UTF8String ?: "?", node.serial.UTF8String, node.on ? "on" : "off", node.levelSensitivity,
                   (long)node.input, node.crossoverFrequency, (unsigned long)active, (unsigned long)node.bands.count, rate);
            if (node.phaseDegrees != nil) {
                printf("  phase %.0f", node.phaseDegrees.doubleValue);
            }
            printf("\n");
            if (QLMHasFlag(argc, argv, "--bands")) {
                for (QLMSetupBand *band in node.bands) {
                    if (band.gain != 0) {
                        printf("      %-10s %2ld  %8.2f Hz  %6.2f dB  Q %.2f\n", QLMBandTypeName(band.type), (long)band.index,
                               band.frequency, band.gain, band.q);
                    }
                }
            }
        }
    }
    if (setup.unknownKeys.count > 0) {
        printf("\n%lu keys this reader does not know\n", (unsigned long)setup.unknownKeys.count);
        for (NSString *key in setup.unknownKeys) {
            printf("  %s\n", key.UTF8String);
        }
    }
    return 0;
}

// System completes an apply on the main queue, so spin the main run loop.
static int QLMApplyGroupOnBus(int argc, const char *argv[], QLMSetupGroup *group) {
    return QLMRunControl(argc, argv, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        __block BOOL done = NO;
        __block NSError *result = nil;
        [system applyGroup:group completion:^(NSError *error) {
            result = error;
            done = YES;
        }];
        while (!done) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        if (result != nil) {
            fprintf(stderr, "qlmctl: %s (%s %ld)\n", result.localizedDescription.UTF8String, result.domain.UTF8String,
                    (long)result.code);
            return EX_UNAVAILABLE;
        }
        printf("applied %s\n", group.name.UTF8String);
        return 0;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle;
    });
}

// The dry run prints each node's DSP block frames, encoded, with a stand-in
// session per node. The duck, wake, and restore frames are not shown.
// --fake applies over the fake bus. System refuses an apply for any node
// whose design rate is unverified.
static int QLMApplyGroup(int argc, const char *argv[]) {
    if (argc < 4) {
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
    BOOL dryRun = QLMHasFlag(argc, argv, "--dry-run");
    if (!dryRun && !QLMHasFlag(argc, argv, "--fake")) {
        fputs("qlmctl: apply-group only runs with --dry-run or --fake until the adapter exists\n", stderr);
        return EX_UNAVAILABLE;
    }
    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readFileAtPath:@(argv[2]) error:&error];
    if (setup == nil) {
        fprintf(stderr, "qlmctl: %s\n", error.localizedDescription.UTF8String);
        return EX_DATAERR;
    }
    QLMSetupGroup *group = nil;
    for (QLMSetupGroup *candidate in setup.groups) {
        if ([candidate.name isEqualToString:@(argv[3])]) {
            group = candidate;
        }
    }
    if (group == nil) {
        fprintf(stderr, "qlmctl: no group named '%s'\n", argv[3]);
        return EX_DATAERR;
    }
    if (!dryRun) {
        return QLMApplyGroupOnBus(argc, argv, group);
    }
    NSArray<QLMDSPBlock *> *blocks = [QLMDSPBlock blocksForGroup:group error:&error];
    if (blocks == nil) {
        fprintf(stderr, "qlmctl: %s\n", error.localizedDescription.UTF8String);
        return EX_DATAERR;
    }
    BOOL allowed = YES;
    uint8_t session = QLMAddressSessionFirst;
    for (QLMDSPBlock *block in blocks) {
        QLMSetupDevice *device = [setup deviceWithSerial:block.node.serial];
        printf("%s %s as session %02X, %lu frames at %.0f Hz%s\n", device.model.UTF8String ?: "?", block.node.serial.UTF8String,
               session, (unsigned long)block.payloads.count, block.designRate, block.rateVerified ? "" : ", rate unverified");
        for (NSString *warning in block.warnings) {
            printf("  ! %s\n", warning.UTF8String);
        }
        allowed = allowed && block.rateVerified;
        for (NSData *payload in block.payloads) {
            QLMMessage message = QLMMessageMake(session, payload.bytes, payload.length);
            uint8_t frame[QLMFrameMax];
            size_t length = 0;
            if (QLMFrameEncode(&message, frame, sizeof frame, &length) != QLMFrameOK) {
                printf("  REFUSED by the allowlist:");
            } else {
                printf("  ");
            }
            for (size_t i = 0; i < length; i++) {
                printf("%02X%s", frame[i], i + 1 < length ? " " : "\n");
            }
        }
        session++;
    }
    printf("%s\n", allowed ? "every node's rate is verified: an apply would be allowed"
                            : "REFUSED: a node's design rate is unverified, so an apply would not run");
    return 0;
}

typedef int (*QLMCommandHandler)(int argc, const char *argv[]);

static const struct {
    const char *name;
    QLMCommandHandler handler;
} QLMCommands[] = {
    {"discover", QLMDiscover},
    {"poll", QLMPoll},
    {"volume", QLMVolume},
    {"mute", QLMMute},
    {"dim", QLMDim},
    {"sleep", QLMSleep},
    {"wake", QLMWake},
    {"setup", QLMPrintSetup},
    {"apply-group", QLMApplyGroup},
};

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || strcmp(argv[1], "help") == 0 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
            QLMPrintUsage(stdout);
            return 0;
        }
        for (size_t i = 0; i < sizeof QLMCommands / sizeof QLMCommands[0]; i++) {
            if (strcmp(argv[1], QLMCommands[i].name) == 0) {
                return QLMCommands[i].handler(argc, argv);
            }
        }
        fprintf(stderr, "qlmctl: unknown command '%s'\n", argv[1]);
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
}
