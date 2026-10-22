#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sysexits.h>

#import "QLMDSPBlock.h"
#import "QLMFakeBus.h"
#include "QLMReplies.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"

static void QLMPrintUsage(FILE *stream) {
    fputs("usage: qlmctl <command> [options]\n"
          "\n"
          "  discover [--fake] [--seconds N]  list every monitor on the bus after N seconds\n"
          "  poll [--fake] [--seconds N]    print each monitor's telemetry as it arrives, for N seconds\n"
          "  setup <file.sam> [--bands]     print a GLM 5 setup file\n"
          "  apply-group <file.sam> <group> --dry-run\n"
          "                                 print the frames a group apply would send\n"
          "\n"
          "The adapter over HID is not written yet, so discover and poll need --fake,\n"
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

#pragma mark - The bus

static id<QLMAdapter> QLMMakeAdapter(int argc, const char *argv[]) {
    if (!QLMHasFlag(argc, argv, "--fake")) {
        fputs("qlmctl: the adapter over HID is not written yet. Use --fake.\n", stderr);
        return nil;
    }
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    QLMFakeMonitor *left = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:leftID length:3]
                                                        serialNumber:@"8330apm21001234" systemInfo:@"c-1;model-8330A"
                                                         deviceClass:QLMTelemetryClassTwoWay];
    QLMFakeMonitor *right = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:rightID length:3]
                                                         serialNumber:@"8330apm21005678" systemInfo:@"c-1;model-8330A"
                                                          deviceClass:QLMTelemetryClassTwoWay];
    right.temperature = 41;
    return [[QLMFakeBus alloc] initWithMonitors:@[left, right]];
}

static const char *QLMStatusName(QLMMonitorStatus status) {
    switch (status) {
    case QLMMonitorStatusOn: return "on";
    case QLMMonitorStatusStandby: return "standby";
    case QLMMonitorStatusUnknown: break;
    }
    return "?";
}

static const char *QLMClassName(NSInteger deviceClass) {
    switch (deviceClass) {
    case QLMTelemetryClassSubwoofer: return "subwoofer";
    case QLMTelemetryClassTwoWay: return "two-way";
    case QLMTelemetryClassStandby: return "standby";
    default: return "?";
    }
}

static void QLMPrintMonitors(QLMSnapshot *snapshot) {
    printf("session  class      status   temp  serial            info\n");
    for (QLMMonitorState *monitor in snapshot.monitors) {
        printf("%02X       %-10s %-8s %3ld C %-17s %s\n", monitor.session, QLMClassName(monitor.deviceClass),
               QLMStatusName(monitor.status), (long)monitor.temperature, monitor.serialNumber.UTF8String ?: "?",
               monitor.systemInfo.UTF8String ?: "?");
    }
}

// Discovery has no end: a probe goes out every cycle. So run for a while and
// print what System holds then. GLM finds two monitors in about 1.6 s.
static int QLMDiscover(int argc, const char *argv[]) {
    id<QLMAdapter> adapter = QLMMakeAdapter(argc, argv);
    if (adapter == nil) {
        return EX_UNAVAILABLE;
    }
    const char *secondsOption = QLMOptionValue(argc, argv, "--seconds");
    double seconds = secondsOption != NULL ? atof(secondsOption) : 3;
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:adapter settings:settings];
    [system start];
    [NSThread sleepForTimeInterval:seconds];
    QLMSnapshot *result = system.snapshot;
    [system stop];
    if (result.monitors.count == 0) {
        fputs("qlmctl: no monitor answered\n", stderr);
        return EX_UNAVAILABLE;
    }
    QLMPrintMonitors(result);
    return 0;
}

static int QLMPoll(int argc, const char *argv[]) {
    id<QLMAdapter> adapter = QLMMakeAdapter(argc, argv);
    if (adapter == nil) {
        return EX_UNAVAILABLE;
    }
    const char *secondsOption = QLMOptionValue(argc, argv, "--seconds");
    double seconds = secondsOption != NULL ? atof(secondsOption) : 5;
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:adapter settings:settings];
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

// The dry run prints every frame, encoded, with a stand-in session per
// node. Applying for real waits for the adapter, and is refused for any
// node whose design rate is unverified.
static int QLMApplyGroup(int argc, const char *argv[]) {
    if (argc < 4) {
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
    if (!QLMHasFlag(argc, argv, "--dry-run")) {
        fputs("qlmctl: apply-group only runs with --dry-run until the adapter exists\n", stderr);
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
            QLMMessage message;
            memset(&message, 0, sizeof message);
            message.address = session;
            message.length = payload.length;
            memcpy(message.payload, payload.bytes, payload.length);
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

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || strcmp(argv[1], "help") == 0 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
            QLMPrintUsage(stdout);
            return 0;
        }
        if (strcmp(argv[1], "discover") == 0) {
            return QLMDiscover(argc, argv);
        }
        if (strcmp(argv[1], "poll") == 0) {
            return QLMPoll(argc, argv);
        }
        if (strcmp(argv[1], "setup") == 0) {
            return QLMPrintSetup(argc, argv);
        }
        if (strcmp(argv[1], "apply-group") == 0) {
            return QLMApplyGroup(argc, argv);
        }
        fprintf(stderr, "qlmctl: unknown command '%s'\n", argv[1]);
        QLMPrintUsage(stderr);
        return EX_USAGE;
    }
}
