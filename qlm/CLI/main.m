#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sysexits.h>

#import "QLMApplySequence.h"
#import "QLMCapture.h"
#include "QLMCommands.h"
#import "QLMControl.h"
#import "QLMDSPBlock.h"
#import "QLMFakeBus.h"
#include "QLMFrame.h"
#import "QLMHIDAdapter.h"
#import "QLMReplayAdapter.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"

static void QLMPrintUsage(FILE *stream) {
    fprintf(stream,
            "usage: qlmctl <command> [options]\n"
            "\n"
            "  info [BUS]                     print the adapter's identity and its knob\n"
            "  discover [BUS] [--setup FILE.sam] [--seconds N]\n"
            "                                 list every monitor once all are identified, or after N seconds,\n"
            "                                 named from the setup file by hardware ID\n"
            "  poll [BUS] [--seconds N]       print each monitor's telemetry as it arrives, for N seconds\n"
            "  volume <dB> [BUS] [CONTROL] [--ceiling dB [--allow-high-ceiling]]\n"
            "                                 set the volume, at or below the ceiling\n"
            "  mute <on|off> [BUS] [CONTROL] [--serial TEXT]\n"
            "                                 mute every monitor, or the one whose serial contains TEXT\n"
            "  dim <on|off> [BUS] [CONTROL] [--volume dB] [--ceiling dB [--allow-high-ceiling]]\n"
            "                                 dim the volume by %.0f dB, or restore it\n"
            "  sleep [BUS] [CONTROL]          put every monitor in standby\n"
            "  wake [BUS] [CONTROL] [--volume dB --ceiling dB [--allow-high-ceiling]]\n"
            "                                 wake every monitor, then send the volume if one is given\n"
            "  setup <file.sam> [--bands]     print a GLM 5 setup file\n"
            "  apply-group <file.sam> <group> [--launch] --dry-run [--volume dB] [--ceiling dB]\n"
            "  apply-group <file.sam> <group> [--launch] [BUS] [CONTROL] --volume dB --ceiling dB\n"
            "              [--allow-high-ceiling] [--unverified-rate]\n"
            "                                 print, or send, every frame of a switch to the group, or with\n"
            "                                 --launch, of the apply at launch and wake. The dry run reads only\n"
            "                                 the setup file. --volume is the level the apply restores.\n"
            "\n"
            "BUS picks what a command drives:\n"
            "  (none)                         the GLM adapter over USB, opened only seized. Refused, with exit 69,\n"
            "                                 while GLM runs, while another process holds the adapter, or when qlm\n"
            "                                 cannot seize it. info, discover, and poll send only the adapter's\n"
            "                                 status poll and identity queries, and, but for info, the probe, the\n"
            "                                 leases, and the monitors' identity queries and polls.\n"
            "  --fake                         a simulated bus of two monitors\n"
            "  --replay FILE                  a capture's reports.txt, answering as the adapter did\n"
            "\n"
            "CONTROL, for volume, mute, dim, sleep, and wake:\n"
            "  --dry-run                      discover as discover does, then print every frame the command would\n"
            "                                 send. Nothing more is sent.\n"
            "  --seconds N                    stay the host for N seconds after the change shows. The volume goes\n"
            "                                 out again every cycle.\n"
            "  --muted TEXT[,TEXT...]         the monitors already muted, as in GLM, each named by text its serial\n"
            "                                 contains. qlm cannot read a mute, so without this, its rounds of mute\n"
            "                                 state restate them as unmuted.\n"
            "\n"
            "The controls over USB:\n"
            "  - volume, dim, and wake --volume need --ceiling. GLMProtocol caps every volume frame at it. It may\n"
            "    be at most %.0f dB, or 0 dB with --allow-high-ceiling. The volume may not be above it.\n"
            "  - dim needs --volume, the level to dim from. qlm cannot read the level.\n"
            "  - wake without --volume sends no level, so each monitor comes back at the level it kept.\n"
            "  - One monitor first. mute --serial changes one monitor. As GLM does, it also restates every other\n"
            "    monitor, and so do dim and a turn of the knob: as unmuted, unless --muted names it. A monitor\n"
            "    muted in GLM and left out of --muted plays again.\n"
            "    volume, dim, sleep, and wake are broadcasts, and every monitor obeys them.\n"
            "    To try one on a single monitor, put the others in standby in GLM, then quit GLM. wake wakes\n"
            "    them all, so try it last.\n"
            "  - About 2.6 s after qlmctl exits, the adapter takes over at the knob's position. qlmctl sends that\n"
            "    level as it exits when it is at or below its own. When the knob is higher, the level rises then,\n"
            "    so turn the knob down first.\n"
            "\n"
            "apply-group over USB is a supervised test. Run it at a low level, with one monitor first. A group\n"
            "with a model whose filter design rate is unverified, the 8351B, also needs --unverified-rate.\n",
            QLMDimDecibels, QLMCeilingLimit);
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

static const NSTimeInterval QLMInfoTimeout = 2;
// A poll often gets a bare 09, so a monitor's power state may take a few
// cycles to show.
static const NSTimeInterval QLMDiscoveryTimeout = 5;
// Long enough for the power state to come back in the next poll.
static const NSTimeInterval QLMEffectTimeout = 5;

// The bus a command names, handed to System: the GLM adapter over USB unless
// --fake or --replay.
static QLMSystem *_Nullable QLMMakeSystemOn(BOOL fake, NSString *_Nullable replay, QLMSystemSettings *settings) {
    id<QLMAdapter> adapter = nil;
    if (fake) {
        adapter = [QLMFakeBus demoBusWithSubwoofer:NO];
    } else if (replay != nil) {
        NSError *error = nil;
        QLMCapture *capture = [QLMCapture captureWithContentsOfFile:replay error:&error];
        if (capture == nil) {
            fprintf(stderr, "qlmctl: %s: %s\n", replay.UTF8String, error.localizedDescription.UTF8String);
            return nil;
        }
        adapter = [[QLMReplayAdapter alloc] initWithCapture:capture];
    } else {
        adapter = [[QLMHIDAdapter alloc] init];
    }
    return [[QLMSystem alloc] initWithAdapter:adapter settings:settings];
}

static QLMSystem *_Nullable QLMMakeSystem(int argc, const char *argv[], QLMSystemSettings *settings) {
    const char *replay = QLMOptionValue(argc, argv, "--replay");
    return QLMMakeSystemOn(QLMHasFlag(argc, argv, "--fake"), replay != NULL ? @(replay) : nil, settings);
}

// Prints why nothing reached the bus, if so. A busy adapter sent nothing.
static BOOL QLMReportAdapterError(QLMSnapshot *snapshot) {
    NSError *error = snapshot.adapterError;
    if (error == nil) {
        return NO;
    }
    fprintf(stderr, "qlmctl: %s\n", error.localizedDescription.UTF8String);
    if ([error.domain isEqualToString:QLMAdapterErrorDomain] && error.code == QLMAdapterErrorBusy) {
        fputs("qlmctl: nothing was sent\n", stderr);
    }
    return YES;
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

// As a setup file's Serial gives it: the three bytes, big-endian, in decimal.
static unsigned long QLMHardwareIDNumber(NSData *hardwareID) {
    const uint8_t *bytes = hardwareID.bytes;
    return hardwareID.length == 3 ? (unsigned long)bytes[0] << 16 | (unsigned long)bytes[1] << 8 | bytes[2] : 0;
}

static void QLMPrintKnob(QLMAdapterState *adapter) {
    if (!adapter.hasStatus) {
        printf("knob      ?\n");
    } else if (adapter.knobTenths == nil) {
        printf("knob      none\n");
    } else {
        printf("knob      in, at %.1f dB\n", adapter.knobTenths.doubleValue / 10.0);
    }
}

static int QLMInfo(int argc, const char *argv[]) {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.discoversMonitors = NO;
    QLMSystem *system = QLMMakeSystem(argc, argv, settings);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    [system start];
    QLMSnapshot *result = QLMWaitForSnapshot(system, QLMInfoTimeout, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil || snapshot.adapter.identified;
    }) ?: system.snapshot;
    [system stop];
    if (QLMReportAdapterError(result)) {
        return EX_UNAVAILABLE;
    }
    QLMAdapterState *adapter = result.adapter;
    printf("device    %s\n", adapter.device.UTF8String);
    printf("model     %s\n", adapter.model.UTF8String ?: "?");
    printf("firmware  %s\n", adapter.firmwareVersion.UTF8String ?: "?");
    printf("serial    %s\n", adapter.serialNumber.UTF8String ?: "?");
    NSString *systemInfo = [adapter.systemInfo stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    printf("system    %s\n", systemInfo.UTF8String ?: "?");
    QLMPrintKnob(adapter);
    printf("mic       %s\n", !adapter.hasStatus ? "?" : (adapter.micPresent ? "in" : "none"));
    if (!adapter.identified) {
        fputs("qlmctl: the adapter did not answer every query\n", stderr);
        return EX_UNAVAILABLE;
    }
    return 0;
}

// The adapter, then every monitor, named from the setup file by hardware ID.
static void QLMPrintDiscovered(QLMSnapshot *snapshot, QLMSetup *_Nullable setup) {
    QLMAdapterState *adapter = snapshot.adapter;
    printf("adapter  %s %s, serial %s, through %s\n", adapter.model.UTF8String ?: "?", adapter.firmwareVersion.UTF8String ?: "?",
           adapter.serialNumber.UTF8String ?: "?", adapter.device.UTF8String);
    printf("session  id        model    serial           firmware      class      status   temp  name\n");
    for (QLMMonitorState *monitor in snapshot.monitors) {
        QLMSetupDevice *device = [setup deviceWithHardwareID:monitor.hardwareID];
        printf("%02X       %-9lu %-8s %-16s %-13s %-10s %-8s %3ld C  %s\n", monitor.session, QLMHardwareIDNumber(monitor.hardwareID),
               monitor.model.UTF8String ?: "?", monitor.serialNumber.UTF8String ?: "?", monitor.firmwareVersion.UTF8String ?: "?",
               QLMClassName(monitor.deviceClass), QLMStatusName(monitor.status), (long)monitor.temperature,
               device != nil ? device.name.UTF8String : (setup != nil ? "(not in the setup)" : ""));
    }
}

// Without --seconds, prints once every monitor found is identified. A probe
// goes out every cycle, so --seconds N runs for N seconds to catch late ones.
static int QLMDiscover(int argc, const char *argv[]) {
    QLMSetup *setup = nil;
    const char *setupPath = QLMOptionValue(argc, argv, "--setup");
    if (setupPath != NULL) {
        NSError *error = nil;
        setup = [QLMSetupReader readFileAtPath:@(setupPath) error:&error];
        if (setup == nil) {
            fprintf(stderr, "qlmctl: %s: %s\n", setupPath, error.localizedDescription.UTF8String);
            return EX_DATAERR;
        }
    }
    QLMSystem *system = QLMMakeSystem(argc, argv, [[QLMSystemSettings alloc] init]);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    double seconds = QLMSecondsOption(argc, argv, 0);
    [system start];
    QLMSnapshot *result = nil;
    if (seconds > 0) {
        result = QLMWaitForSnapshot(system, seconds, ^BOOL(QLMSnapshot *snapshot) {
            return snapshot.adapterError != nil;
        }) ?: system.snapshot;
    } else {
        result = QLMWaitForSnapshot(system, QLMDiscoveryTimeout, ^BOOL(QLMSnapshot *snapshot) {
            return snapshot.adapterError != nil || snapshot.allIdentified;
        }) ?: system.snapshot;
    }
    [system stop];
    if (QLMReportAdapterError(result)) {
        return EX_UNAVAILABLE;
    }
    if (result.monitors.count == 0) {
        fputs("qlmctl: no monitor answered\n", stderr);
        return EX_UNAVAILABLE;
    }
    QLMPrintDiscovered(result, setup);
    return result.allIdentified ? 0 : EX_TEMPFAIL;
}

static int QLMPoll(int argc, const char *argv[]) {
    QLMSystem *system = QLMMakeSystem(argc, argv, [[QLMSystemSettings alloc] init]);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    double seconds = QLMSecondsOption(argc, argv, 5);
    dispatch_queue_t printing = dispatch_queue_create("qlmctl.poll", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t failed = dispatch_semaphore_create(0);
    NSDate *start = [NSDate date];
    __block NSNumber *lastKnob = nil;
    __block BOOL knobShown = NO;
    __block BOOL reported = NO;
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        if (reported) {
            return;
        }
        if (QLMReportAdapterError(snapshot)) {
            reported = YES;
            dispatch_semaphore_signal(failed);
            return;
        }
        double elapsed = [[NSDate date] timeIntervalSinceDate:start];
        NSNumber *knob = snapshot.adapter.knobTenths;
        BOOL sameKnob = knob == lastKnob || (knob != nil && [knob isEqual:lastKnob]);
        if (snapshot.adapter.hasStatus && (!knobShown || !sameKnob)) {
            if (knob != nil) {
                printf("%7.2f s  knob at %.1f dB\n", elapsed, knob.doubleValue / 10.0);
            } else {
                printf("%7.2f s  no knob\n", elapsed);
            }
            lastKnob = knob;
            knobShown = YES;
        }
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if (monitor.status == QLMMonitorStatusUnknown) {
                continue;
            }
            printf("%7.2f s  %02X %-7lu %-8s %-8s %3ld C  in %3ld  hf %3ld  lf %3ld  sub %3ld  missed %lu\n", elapsed, monitor.session,
                   QLMHardwareIDNumber(monitor.hardwareID), monitor.model.UTF8String ?: "?", QLMStatusName(monitor.status),
                   (long)monitor.temperature, (long)monitor.inputMeter, (long)monitor.hfMeter, (long)monitor.lfMeter,
                   (long)monitor.subMeter, (unsigned long)monitor.missedPolls);
        }
        fflush(stdout);
    } queue:printing];
    [system start];
    long early = dispatch_semaphore_wait(failed, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * (double)NSEC_PER_SEC)));
    [system stop];
    dispatch_sync(printing, ^{});
    return early == 0 ? EX_UNAVAILABLE : 0;
}

#pragma mark - The controls

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

// One message as it goes on the bus, after an optional label and before an
// optional note. A message the allowlist refuses prints unencoded.
static void QLMPrintFrame(const QLMMessage *message, const char *_Nullable label, const char *_Nullable note) {
    uint8_t frame[QLMFrameMax];
    size_t length = 0;
    printf("  ");
    if (label != NULL) {
        printf("%-17s ", label);
    }
    if (QLMFrameEncode(message, frame, sizeof frame, &length) != QLMFrameOK) {
        printf("REFUSED by the allowlist: %02X", message->address);
        for (size_t i = 0; i < message->length; i++) {
            printf(" %02X", message->payload[i]);
        }
    } else {
        for (size_t i = 0; i < length; i++) {
            printf("%s%02X", i == 0 ? "" : " ", frame[i]);
        }
    }
    printf("%s\n", note ?: "");
}

// The dry run's note: what the stop would do, by the knob's reading now.
static NSString *QLMDryRunHandBackText(QLMAdapterState *adapter) {
    if (adapter.knobTenths == nil) {
        return @"About 2.6 s after qlm stops, the adapter takes over with its own level. No knob is in, so that level is "
               @"unknown.";
    }
    return [NSString stringWithFormat:@"About 2.6 s after qlm stops, the adapter takes over at the knob's %.1f dB. If that "
                                      @"is at or below qlm's level, qlm sends it as it stops, and nothing changes. If it "
                                      @"is above, the level rises then.",
                                      adapter.knobTenths.doubleValue / 10.0];
}

static void QLMPrintDryRun(QLMControlOptions *options, QLMSnapshot *discovered, NSArray<NSData *> *records) {
    printf("\n%s\n", records.count == 0 ? "would send nothing" : "would send, in order:");
    for (NSData *record in records) {
        const uint8_t *bytes = record.bytes;
        QLMMessage message = QLMMessageMake(bytes[0], bytes + 1, record.length - 1);
        NSString *label = nil;
        if (message.address == QLMAddressBroadcast) {
            label = @"every monitor";
        } else if (message.address == QLMAddressAdapter) {
            label = @"the adapter";
        }
        for (QLMMonitorState *monitor in discovered.monitors) {
            if (label == nil && monitor.session == message.address) {
                label = monitor.serialNumber;
            }
        }
        label = label ?: [NSString stringWithFormat:@"session %02X", message.address];
        char note[48] = "";
        uint32_t word = 0;
        if (QLMVolumeFrameWord(&message, &word)) {
            snprintf(note, sizeof note, "  volume %.1f dB", QLMVolumeDecibelsForWord(word));
        }
        QLMPrintFrame(&message, label.UTF8String, note);
    }
    printf("\n");
    if (options.volumeDecibels != nil) {
        printf("The cycle sends the volume again every %.2f s while qlmctl runs.\n", options.settings.cycleInterval);
    }
    if (options.overUSB) {
        printf("%s\n", QLMDryRunHandBackText(discovered.adapter).UTF8String);
    }
    printf("Nothing was sent beyond discovery.\n");
}

// Discovery is done and its bus is stopped. The action runs on a mirror.
static int QLMDryRunControl(QLMControlOptions *options, QLMSnapshot *discovered, QLMControlAction action, QLMSnapshotTest effect) {
    QLMPrintDiscovered(discovered, nil);
    int status = 0;
    NSArray<NSData *> *records = QLMDryRunRecords(discovered, options.settings, action, effect, &status);
    if (records == nil) {
        if (status == EX_SOFTWARE) {
            fputs("qlmctl: the dry run's fake bus did not find every monitor\n", stderr);
        }
        return status;
    }
    if (status == EX_TEMPFAIL) {
        fputs("qlmctl: the change did not show on the dry run's fake bus, so this list may be short\n", stderr);
    }
    QLMPrintDryRun(options, discovered, records);
    return status;
}

// Runs the action once every monitor is identified, and stops as poll does.
// A dry run stops the bus after discovery. Nil options, for apply-group's
// fake bus, mean no dry run, no hold, and no USB.
static int QLMRunControl(QLMSystem *system, QLMControlOptions *_Nullable options, QLMControlAction action, QLMSnapshotTest effect) {
    [system start];
    QLMSnapshot *discovered = QLMWaitForSnapshot(system, QLMDiscoveryTimeout, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.adapterError != nil || snapshot.allIdentified;
    });
    if (discovered == nil || discovered.adapterError != nil) {
        NSUInteger found = system.snapshot.monitors.count;
        [system stop];
        if (QLMReportAdapterError(discovered)) {
            return EX_UNAVAILABLE;
        }
        if (found == 0) {
            fputs("qlmctl: no monitor answered\n", stderr);
            return EX_UNAVAILABLE;
        }
        fprintf(stderr, "qlmctl: %lu monitors answered, but not every one was identified in %.0f s\n", (unsigned long)found,
                QLMDiscoveryTimeout);
        fputs("qlmctl: the command was not sent\n", stderr);
        return EX_TEMPFAIL;
    }
    if (options.dryRun) {
        [system stop];
        return QLMDryRunControl(options, discovered, action, effect);
    }

    int status = action(system, discovered);
    BOOL sent = status == 0;
    if (sent) {
        QLMSnapshot *result = QLMWaitForSnapshot(system, QLMEffectTimeout, effect);
        if (result == nil) {
            fputs("qlmctl: timed out waiting for the change to show\n", stderr);
            status = EX_TEMPFAIL;
        }
        QLMPrintControl(result ?: system.snapshot);
        if (options.seconds > 0) {
            QLMWaitForSnapshot(system, options.seconds, ^BOOL(QLMSnapshot *snapshot) {
                return snapshot.adapterError != nil;
            });
        }
        NSError *lost = system.snapshot.adapterError;
        if (lost != nil) {
            fprintf(stderr, "qlmctl: %s\n", lost.localizedDescription.UTF8String);
            status = EX_UNAVAILABLE;
        }
    }
    // The stop may send the knob's level first, so wait for it.
    [system stop];
    QLMSnapshot *stopped = QLMWaitForSnapshot(system, QLMEffectTimeout, ^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.running;
    });
    if (sent && options.overUSB) {
        QLMHandBack *handBack = (stopped ?: system.snapshot).handBack;
        BOOL warning = handBack.kind != QLMHandBackKnobLevel;
        fprintf(stderr, "qlmctl: %s%s\n", warning ? "warning: " : "", QLMHandBackText(handBack).UTF8String);
    }
    return status;
}

// The options after the command's name, or nil once it has said why not.
static QLMControlOptions *_Nullable QLMReadOptionsFrom(int first, QLMControlCommand command, int argc, const char *argv[]) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    NSString *problem = nil;
    for (int i = first; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if (argument == nil) {
            problem = @"an argument is not UTF-8";
            break;
        }
        [arguments addObject:argument];
    }
    QLMControlOptions *options = problem != nil ? nil : [QLMControlOptions optionsForCommand:command arguments:arguments problem:&problem];
    if (options == nil) {
        fprintf(stderr, "qlmctl: %s\nqlmctl: nothing was sent. qlmctl help lists the options.\n", problem.UTF8String);
    }
    return options;
}

static QLMControlOptions *_Nullable QLMReadControlOptions(QLMControlCommand command, int argc, const char *argv[]) {
    return QLMReadOptionsFrom(2, command, argc, argv);
}

static int QLMRunControlCommand(QLMControlOptions *options, QLMControlAction action, QLMSnapshotTest effect) {
    QLMSystem *system = QLMMakeSystemOn(options.fake, options.replayPath, options.settings);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    if (options.mutedSerials.count > 0) {
        action = QLMWithMuted(options.mutedSerials, action);
    }
    return QLMRunControl(system, options, action, effect);
}

static int QLMVolume(int argc, const char *argv[]) {
    QLMControlOptions *options = QLMReadControlOptions(QLMControlCommandVolume, argc, argv);
    if (options == nil) {
        return EX_USAGE;
    }
    return QLMRunControlCommand(options, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        [system setVolumeDecibels:options.volumeDecibels.doubleValue];
        return 0;
    }, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.volumeDecibels isEqualToNumber:options.volumeDecibels];
    });
}

static int QLMMute(int argc, const char *argv[]) {
    QLMControlOptions *options = QLMReadControlOptions(QLMControlCommandMute, argc, argv);
    if (options == nil) {
        return EX_USAGE;
    }
    __block NSData *target = nil;  // nil for every monitor
    return QLMRunControlCommand(options, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        if (options.serial == nil) {
            [system setAllMuted:options.on];
            return 0;
        }
        NSString *problem = nil;
        target = QLMHardwareIDsForSerials(@[options.serial], discovered, &problem).anyObject;
        if (target == nil) {
            fprintf(stderr, "qlmctl: %s\n", problem.UTF8String);
            return EX_DATAERR;
        }
        [system setMuted:options.on forMonitorWithHardwareID:target];
        return 0;
    }, QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        if (!snapshot.idle) {
            return NO;
        }
        if (target == nil) {
            return snapshot.allMuted == options.on;
        }
        for (QLMMonitorState *monitor in snapshot.monitors) {
            if ([monitor.hardwareID isEqualToData:target]) {
                return monitor.muted == options.on;
            }
        }
        return NO;
    }));
}

static int QLMDim(int argc, const char *argv[]) {
    QLMControlOptions *options = QLMReadControlOptions(QLMControlCommandDim, argc, argv);
    if (options == nil) {
        return EX_USAGE;
    }
    NSNumber *volume = options.volumeDecibels;
    // Without a volume, dim sends nothing, and the replay may pass.
    return QLMRunControlCommand(options, QLMDimAction(options.on, volume), ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && snapshot.dimmed == options.on && (volume == nil || [snapshot.volumeDecibels isEqualToNumber:volume]);
    });
}

// The power state comes back in telemetry. After a wake the monitors are
// found again under new sessions, so wait for all of them.
static int QLMPower(int argc, const char *argv[], BOOL wake) {
    QLMControlOptions *options = QLMReadControlOptions(wake ? QLMControlCommandWake : QLMControlCommandSleep, argc, argv);
    if (options == nil) {
        return EX_USAGE;
    }
    QLMMonitorStatus wanted = wake ? QLMMonitorStatusOn : QLMMonitorStatusStandby;
    NSNumber *volume = options.volumeDecibels;
    __block NSUInteger count = 0;
    QLMControlAction power = wake ? QLMWakeAction(volume) : ^int(QLMSystem *system, QLMSnapshot *discovered) {
        [system sleep];
        return 0;
    };
    return QLMRunControlCommand(options, ^int(QLMSystem *system, QLMSnapshot *discovered) {
        count = discovered.monitors.count;
        return power(system, discovered);
    }, QLMAfterReplay(^BOOL(QLMSnapshot *snapshot) {
        if (!snapshot.idle || snapshot.monitors.count != count) {
            return NO;
        }
        if (volume != nil && ![snapshot.volumeDecibels isEqualToNumber:volume]) {
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

// The switch, or with `launch` the apply at launch, at `volume`. System
// completes an apply on the main queue, so spin the main run loop.
static QLMControlAction QLMApplyGroupAction(QLMSetupGroup *group, BOOL launch, NSNumber *volume) {
    return ^int(QLMSystem *system, QLMSnapshot *discovered) {
        [system setVolumeDecibels:volume.doubleValue];
        __block BOOL done = NO;
        __block NSError *result = nil;
        void (^completion)(NSError *) = ^(NSError *error) {
            result = error;
            done = YES;
        };
        if (launch) {
            [system applyGroup:group completion:completion];
        } else {
            [system switchToGroup:group completion:completion];
        }
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
    };
}

// A switch to the group, or with --launch the apply at launch and wake.
// The dry run prints every frame System sends, as QLMApplySequence builds
// it. Each node's monitor stands in at a session, from 02 in node order, on
// and unmuted. The restore's volume is --volume, or the setup's, capped at
// --ceiling. Otherwise the apply runs on the bus, as a control does.
// System refuses any node whose design rate is unverified, but in the
// supervised test behind --unverified-rate.
static int QLMApplyGroup(int argc, const char *argv[]) {
    if (argc < 4) {
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
    QLMControlOptions *options = QLMReadOptionsFrom(4, QLMControlCommandApplyGroup, argc, argv);
    if (options == nil) {
        return EX_USAGE;
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
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = [QLMDSPBlock blocksByHardwareIDForGroup:group error:&error];
    if (blocks == nil) {
        fprintf(stderr, "qlmctl: %s\n", error.localizedDescription.UTF8String);
        return EX_DATAERR;
    }
    if (!options.dryRun) {
        BOOL unverified = NO;
        for (QLMDSPBlock *block in blocks.allValues) {
            unverified = unverified || !block.rateVerified;
        }
        if (unverified && !options.unverifiedRate) {
            fputs("qlmctl: the group has a model whose filter design rate is unverified, the 8351B. Its supervised test "
                  "takes --unverified-rate.\nqlmctl: nothing was sent.\n",
                  stderr);
            return EX_UNAVAILABLE;
        }
        NSString *name = group.name;
        return QLMRunControlCommand(options, QLMApplyGroupAction(group, options.launch, options.volumeDecibels),
                                    ^BOOL(QLMSnapshot *snapshot) {
                                        return snapshot.idle && [snapshot.activeGroupName isEqualToString:name];
                                    });
    }

    double volume = options.volumeDecibels != nil ? options.volumeDecibels.doubleValue : setup.volume;
    double ceiling = options.ceilingDecibels;
    BOOL allowed = YES;
    uint8_t session = QLMAddressSessionFirst;
    NSMutableArray<QLMApplyMonitor *> *monitors = [NSMutableArray array];
    for (QLMSetupNode *node in group.nodes) {
        QLMDSPBlock *block = node.hardwareID != nil ? blocks[node.hardwareID] : nil;
        if (block == nil) {
            fprintf(stderr, "qlmctl: node %s has no hardware ID\n", node.serial.UTF8String);
            return EX_DATAERR;
        }
        QLMSetupDevice *device = [setup deviceWithSerial:node.serial];
        printf("%s %s %s as session %02X, %lu block frames at %.0f Hz%s\n", device.model.UTF8String ?: "?",
               node.serial.UTF8String, node.on ? "on" : "off", session, (unsigned long)block.payloads.count, block.designRate,
               block.rateVerified ? "" : ", rate unverified");
        for (NSString *warning in block.warnings) {
            printf("  ! %s\n", warning.UTF8String);
        }
        allowed = allowed && block.rateVerified;
        QLMApplyMonitor *monitor = [[QLMApplyMonitor alloc] initWithHardwareID:node.hardwareID session:session++];
        monitor.on = YES;
        [monitors addObject:monitor];
    }

    QLMApplySequence *sequence = [[QLMApplySequence alloc] initWithGroup:group monitors:monitors adapterMuted:NO];
    NSMutableArray<NSData *> *records;
    if (options.launch) {
        printf("\nthe apply at launch and wake, to every monitor, then each one's state after its next poll\n");
        records = [[sequence enumerationOf:monitors blocks:blocks] mutableCopy];
        for (QLMApplyMonitor *monitor in monitors) {
            [records addObjectsFromArray:[sequence stateOf:monitor firstOfTwo:NO]];
        }
    } else {
        printf("\na switch to %s with every monitor on, restoring %.1f dB under a %.1f dB ceiling\n", group.name.UTF8String,
               volume, ceiling);
        records = [[sequence switchWithBlocks:blocks volume:QLMCommandVolume(volume, ceiling)] mutableCopy];
    }
    for (NSData *record in records) {
        QLMMessage message = QLMApplyMessage(record);
        QLMPrintFrame(&message, NULL, NULL);
    }
    printf("%lu frames. Not sent, though GLM sends them: 05 04 before each block, and the 8351B's 43 00 02 and "
           "4B 00 00 00 01.\n",
           (unsigned long)records.count);
    printf("%s\n", allowed ? "every node's rate is verified: an apply would be allowed"
                            : "REFUSED: a node's design rate is unverified, so an apply runs only as its supervised "
                              "test, with --unverified-rate");
    return 0;
}

typedef int (*QLMCommandHandler)(int argc, const char *argv[]);

static const struct {
    const char *name;
    QLMCommandHandler handler;
} QLMCommands[] = {
    {"info", QLMInfo},
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
