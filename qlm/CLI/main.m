#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sysexits.h>

#import "QLMApplySequence.h"
#import "QLMCapture.h"
#include "QLMCommands.h"
#import "QLMCompareApply.h"
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
            "  volume <dB> [BUS] [CONTROL] [--ceiling dB [--allow-high-ceiling]] [--adapter-poll SECONDS]\n"
            "                                 set the volume, at or below the ceiling. --adapter-poll sends one\n"
            "                                 01 08 every SECONDS, 0 to %.0f, in place of GLM's pair every %g s, and\n"
            "                                 0 polls only at start. It needs the knob at or below the volume.\n"
            "  mute <on|off> [BUS] [CONTROL] [--serial TEXT]\n"
            "                                 mute every monitor, or the one whose serial contains TEXT\n"
            "  dim <on|off> [BUS] [CONTROL] [--volume dB] [--ceiling dB [--allow-high-ceiling]]\n"
            "                                 dim the volume by %.0f dB, or restore it\n"
            "  sleep [BUS] [CONTROL]          put every monitor in standby\n"
            "  wake [BUS] [CONTROL] [--volume dB] [--ceiling dB [--allow-high-ceiling]]\n"
            "                                 wake every monitor, and end with a level, as GLM's wake does\n"
            "  setup <file.sam> [--bands]     print a GLM 5 setup file\n"
            "  apply-group <file.sam> <group> [--launch] --dry-run [--volume dB] [--ceiling dB]\n"
            "  apply-group <file.sam> <group> [--launch] [BUS] [CONTROL] --volume dB --ceiling dB\n"
            "              [--allow-high-ceiling] [--unverified-rate]\n"
            "                                 print, or send, every frame of a switch to the group, or with\n"
            "                                 --launch, of the apply at launch and wake. --volume is the level\n"
            "                                 the apply restores.\n"
            "  compare-apply <file.sam> <reports.txt> [--group NAME] [--from S] [--to S]\n"
            "                                 compare GLM's DSP passes in a capture with qlm's blocks from the\n"
            "                                 setup file. It reads the two files and opens no bus.\n"
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
            "CONTROL, for volume, mute, dim, sleep, wake, and apply-group:\n"
            "  --dry-run                      discover as discover does, then print every frame the command would\n"
            "                                 send. Nothing more is sent. apply-group's dry run opens no bus, and\n"
            "                                 reads only the setup file.\n"
            "  --seconds N                    stay the host for N seconds after the change shows. The volume goes\n"
            "                                 out again every cycle.\n"
            "  --muted TEXT[,TEXT...]         the monitors already muted, as in GLM, each named by text its serial\n"
            "                                 contains. qlm cannot read a mute, so without this, its rounds of mute\n"
            "                                 state restate them as unmuted.\n"
            "\n"
            "The controls over USB:\n"
            "  - volume, dim, wake --volume, and apply-group need --ceiling. GLMProtocol caps every volume frame\n"
            "    at it. It may be at most %.0f dB, its default, or 0 dB with --allow-high-ceiling. The volume may\n"
            "    not be above it.\n"
            "  - dim needs --volume, the level to dim from. qlm cannot read the level.\n"
            "  - Every wake ends with a level: --volume when given, else the knob's position under the ceiling,\n"
            "    else the bottom level, 00 00 08.\n"
            "  - One monitor first. mute --serial changes one monitor. As GLM does, it also restates every other\n"
            "    monitor, and so do dim and a turn of the knob: as unmuted, unless --muted names it. A monitor\n"
            "    muted in GLM and left out of --muted plays again.\n"
            "    volume, dim, sleep, and wake are broadcasts, and every monitor obeys them.\n"
            "    To try one on a single monitor, put the others in standby in GLM, then quit GLM. wake wakes\n"
            "    them all, so try it last.\n"
            "  - About 2.6 s after qlmctl exits, the adapter takes over at the knob's position, and the ceiling\n"
            "    no longer holds. When the knob is at or below qlm's level, qlmctl sends the knob's level as it\n"
            "    exits, and nothing changes. When the knob is higher, the level rises then, so turn the knob down\n"
            "    first. At exit, qlmctl says what its stop did, and warns, naming both levels, when it rises.\n"
            "  - Monitors keep a host's leases for a while after it goes quiet, and a monitor that holds one\n"
            "    ignores the probe. So after GLM quits or qlmctl exits, wait 1 minute with every monitor on, and\n"
            "    4 minutes with any in standby.\n"
            "\n"
            "apply-group over USB is a supervised test. Run it at a low level, with one monitor first, as\n"
            "docs/measurement.md does. On any bus, a group with a model whose filter design rate is unverified,\n"
            "the 8351B, also needs --unverified-rate. Without it, qlmctl refuses before it opens the bus.\n"
            "\n"
            "compare-apply takes each DSP pass in the capture, from 17 01 through the 40 frames after 3D, and\n"
            "only those from --from to --to seconds into the capture when given. It matches each pass to the\n"
            "node, in any group or the one --group names, whose block differs from it in the fewest settings,\n"
            "then in order. Only nodes of the model the session's 39 reply names count. When the setup holds\n"
            "the hardware ID the session's lease names, as a raw setup file does and a redacted one doesn't,\n"
            "only that node counts. It prints each pass's node, then every setting whose frame differs, as\n"
            "GLM's then qlm's, every frame only GLM sent, every frame only qlm would send, and what qlm leaves\n"
            "out: the generator stop, 05 04, and the 8351B's 43 00 02 and 4B 00 00 00 01. A left-out frame\n"
            "with other bytes is a frame only GLM sent. It exits 0 when every pass matches but for what qlm\n"
            "leaves out, %d when one doesn't, %d for an argument it doesn't know, and %d for a file it can't\n"
            "read, a group the setup lacks, or no pass to compare.\n",
            QLMAdapterPollLimit, [[QLMSystemSettings alloc] init].adapterPollInterval, QLMDimDecibels, QLMCeilingLimit,
            QLMCompareApplyDiffers, EX_USAGE, EX_DATAERR);
}

static BOOL QLMHasFlag(int argc, const char *argv[], const char *flag) {
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], flag) == 0) {
            return YES;
        }
    }
    return NO;
}

// The arguments from `first` on, or nil when one is not UTF-8.
static NSArray<NSString *> *_Nullable QLMArgumentsFrom(int first, int argc, const char *argv[], NSString **problem) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (int i = first; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if (argument == nil) {
            *problem = @"an argument is not UTF-8";
            return nil;
        }
        [arguments addObject:argument];
    }
    return arguments;
}

static void QLMPrintRefusal(NSString *problem) {
    fprintf(stderr, "qlmctl: %s\nqlmctl: nothing was sent. qlmctl help lists the options.\n", problem.UTF8String);
}

// info's, discover's, or poll's arguments, or nil once it has said why not.
static NSDictionary<NSString *, NSString *> *_Nullable QLMReadQuery(int argc, const char *argv[]) {
    NSString *problem = nil;
    NSArray<NSString *> *arguments = QLMArgumentsFrom(2, argc, argv, &problem);
    NSDictionary<NSString *, NSString *> *given = arguments == nil ? nil : QLMQueryArguments(@(argv[1]), arguments, &problem);
    if (given == nil) {
        QLMPrintRefusal(problem);
    }
    return given;
}

static double QLMSecondsGiven(NSDictionary<NSString *, NSString *> *given, double fallback) {
    NSString *seconds = given[@"--seconds"];
    return seconds != nil ? seconds.doubleValue : fallback;
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

static QLMSystem *_Nullable QLMMakeSystem(NSDictionary<NSString *, NSString *> *given, QLMSystemSettings *settings) {
    return QLMMakeSystemOn(given[@"--fake"] != nil, given[@"--replay"], settings);
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
    NSDictionary<NSString *, NSString *> *given = QLMReadQuery(argc, argv);
    if (given == nil) {
        return EX_USAGE;
    }
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.discoversMonitors = NO;
    QLMSystem *system = QLMMakeSystem(given, settings);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    QLMSnapshot *result = QLMWaitForSnapshot(system, QLMInfoTimeout, ^BOOL {
        [system start];
        return YES;
    }, ^BOOL(QLMSnapshot *snapshot) {
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
    NSDictionary<NSString *, NSString *> *given = QLMReadQuery(argc, argv);
    if (given == nil) {
        return EX_USAGE;
    }
    QLMSetup *setup = nil;
    NSString *setupPath = given[@"--setup"];
    if (setupPath != nil) {
        NSError *error = nil;
        setup = [QLMSetupReader readFileAtPath:setupPath error:&error];
        if (setup == nil) {
            fprintf(stderr, "qlmctl: %s: %s\n", setupPath.UTF8String, error.localizedDescription.UTF8String);
            return EX_DATAERR;
        }
    }
    QLMSystem *system = QLMMakeSystem(given, [[QLMSystemSettings alloc] init]);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    double seconds = QLMSecondsGiven(given, 0);
    BOOL (^start)(void) = ^BOOL {
        [system start];
        return YES;
    };
    QLMSnapshot *result = nil;
    if (seconds > 0) {
        result = QLMWaitForSnapshot(system, seconds, start, ^BOOL(QLMSnapshot *snapshot) {
            return snapshot.adapterError != nil;
        }) ?: system.snapshot;
    } else {
        result = QLMWaitForSnapshot(system, QLMDiscoveryTimeout, start, ^BOOL(QLMSnapshot *snapshot) {
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
    NSDictionary<NSString *, NSString *> *given = QLMReadQuery(argc, argv);
    if (given == nil) {
        return EX_USAGE;
    }
    QLMSystem *system = QLMMakeSystem(given, [[QLMSystemSettings alloc] init]);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    double seconds = QLMSecondsGiven(given, 5);
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
    BOOL early = [system.settings.clock wait:failed timeout:seconds];
    [system stop];
    dispatch_sync(printing, ^{});
    return early ? EX_UNAVAILABLE : 0;
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
    NSArray<NSData *> *records = QLMDryRunRecords(discovered, options.settings, options.mutedSerials, action, effect, &status);
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

// Runs the action on the bus the options name, once every monitor is
// identified, and stops as poll does. A dry run stops the bus after
// discovery.
static int QLMRunControl(QLMControlOptions *options, QLMControlAction action, QLMSnapshotTest effect) {
    QLMSystem *system = QLMMakeSystemOn(options.fake, options.replayPath, options.settings);
    if (system == nil) {
        return EX_UNAVAILABLE;
    }
    QLMSnapshot *discovered = QLMWaitForSnapshot(system, QLMDiscoveryTimeout, ^BOOL {
        [system start];
        return YES;
    }, ^BOOL(QLMSnapshot *snapshot) {
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

    int status = 0;
    QLMSnapshot *result = QLMWaitForEffect(system, discovered, options.mutedSerials, action, effect, QLMEffectTimeout, &status);
    BOOL sent = status == 0;
    if (sent) {
        if (result == nil) {
            fputs("qlmctl: timed out waiting for the change to show\n", stderr);
            status = EX_TEMPFAIL;
        }
        QLMPrintControl(result ?: system.snapshot);
        if (options.seconds > 0) {
            QLMWaitForSnapshot(system, options.seconds, nil, ^BOOL(QLMSnapshot *snapshot) {
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
    QLMSnapshot *stopped = QLMWaitForSnapshot(system, QLMEffectTimeout, ^BOOL {
        [system stop];
        return YES;
    }, ^BOOL(QLMSnapshot *snapshot) {
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
    NSString *problem = nil;
    NSArray<NSString *> *arguments = QLMArgumentsFrom(first, argc, argv, &problem);
    QLMControlOptions *options = arguments == nil ? nil : [QLMControlOptions optionsForCommand:command arguments:arguments problem:&problem];
    if (options == nil) {
        QLMPrintRefusal(problem);
    }
    return options;
}

static QLMControlOptions *_Nullable QLMReadControlOptions(QLMControlCommand command, int argc, const char *argv[]) {
    return QLMReadOptionsFrom(2, command, argc, argv);
}

static int QLMVolume(int argc, const char *argv[]) {
    QLMControlOptions *options = QLMReadControlOptions(QLMControlCommandVolume, argc, argv);
    if (options == nil) {
        return EX_USAGE;
    }
    printf("%s\n", options.adapterPollText.UTF8String);
    QLMControlAction volume = QLMVolumeAction(options.volumeDecibels.doubleValue, options.adapterPollSeconds != nil);
    return QLMRunControl(options, volume, ^BOOL(QLMSnapshot *snapshot) {
        return snapshot.idle && [snapshot.volumeDecibels isEqualToNumber:options.volumeDecibels];
    });
}

static int QLMMute(int argc, const char *argv[]) {
    QLMControlOptions *options = QLMReadControlOptions(QLMControlCommandMute, argc, argv);
    if (options == nil) {
        return EX_USAGE;
    }
    __block NSData *target = nil;  // nil for every monitor
    return QLMRunControl(options, ^int(QLMSystem *system, QLMSnapshot *discovered) {
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
    return QLMRunControl(options, QLMDimAction(options.on, volume), ^BOOL(QLMSnapshot *snapshot) {
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
    return QLMRunControl(options, ^int(QLMSystem *system, QLMSnapshot *discovered) {
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
    QLMSetupGroup *group = [setup groupNamed:@(argv[3])];
    if (group == nil) {
        fprintf(stderr, "qlmctl: no group named '%s'\n", argv[3]);
        return EX_DATAERR;
    }
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = [QLMDSPBlock blocksByHardwareIDForGroup:group error:&error];
    if (blocks == nil) {
        fprintf(stderr, "qlmctl: %s\n", error.localizedDescription.UTF8String);
        return EX_DATAERR;
    }
    BOOL allowed = YES;
    for (QLMDSPBlock *block in blocks.allValues) {
        allowed = allowed && block.rateVerified;
    }
    if (!options.dryRun) {
        if (!allowed && !options.unverifiedRate) {
            fputs("qlmctl: the group has a model whose filter design rate is unverified, the 8351B. Its supervised test "
                  "takes --unverified-rate.\nqlmctl: nothing was sent.\n",
                  stderr);
            return EX_UNAVAILABLE;
        }
        NSString *name = group.name;
        return QLMRunControl(options, QLMApplyGroupAction(group, options.launch, options.volumeDecibels),
                                    ^BOOL(QLMSnapshot *snapshot) {
                                        return snapshot.idle && [snapshot.activeGroupName isEqualToString:name];
                                    });
    }

    double volume = options.volumeDecibels != nil ? options.volumeDecibels.doubleValue : setup.volume;
    double ceiling = options.ceilingDecibels;
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

#pragma mark - The comparison

static int QLMCompareApplyCommand(int argc, const char *argv[]) {
    NSString *problem = nil;
    NSArray<NSString *> *arguments = QLMArgumentsFrom(2, argc, argv, &problem);
    if (arguments == nil) {
        QLMPrintRefusal(problem);
        return EX_USAGE;
    }
    return QLMCompareApply(arguments, stdout, stderr);
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
    {"compare-apply", QLMCompareApplyCommand},
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
