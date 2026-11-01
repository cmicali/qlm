#import "QLMFormat.h"

#include <math.h>

#import <CoreServices/CoreServices.h>

#import "QLMPreferences.h"
#import "QLMSetup.h"

NSString *const QLMEmDash = @"—";
static NSString *const QLMNoLevelRefusal = @"Type a level in dB.";

// A no-break space keeps the unit on the number's line.
NSString *QLMDecibelsText(double decibels) {
    NSString *number = [NSString stringWithFormat:@"%.1f", decibels];
    if ([number isEqualToString:@"-0.0"]) {
        number = @"0.0";
    }
    return [[number stringByReplacingOccurrencesOfString:@"-" withString:@"−"] stringByAppendingString:@"\u00A0dB"];
}

NSString *QLMTypedLevelRefusal(double decibels) {
    if (QLMIsSavableLevel(decibels)) {
        return nil;
    }
    if (isnan(decibels)) {
        return QLMNoLevelRefusal;
    }
    return [NSString stringWithFormat:@"%g\u00A0dB is above 0\u00A0dB, the monitors' full level.", decibels];
}

@implementation QLMDecibelsFormatter

- (instancetype)init {
    self = [super init];
    if (self) {
        self.numberStyle = NSNumberFormatterDecimalStyle;
        self.minimumFractionDigits = 1;
        self.maximumFractionDigits = 1;
        self.minusSign = @"−";
        self.lenient = YES;
    }
    return self;
}

- (BOOL)getObjectValue:(out id _Nullable __autoreleasing *)value forString:(NSString *)string
      errorDescription:(out NSString *_Nullable __autoreleasing *)error {
    id number = nil;
    if (![super getObjectValue:&number forString:string errorDescription:error]) {
        return NO;
    }
    NSString *refusal = number == nil ? QLMNoLevelRefusal : QLMTypedLevelRefusal([number doubleValue]);
    if (refusal != nil) {
        if (error != NULL) {
            *error = refusal;
        }
        return NO;
    }
    if (value != NULL) {
        *value = number;
    }
    return YES;
}

@end

NSString *QLMMonitorLabel(QLMMonitorState *monitor, QLMSetup *setup) {
    return [setup deviceWithHardwareID:monitor.hardwareID].name ?: monitor.serialNumber;
}

NSString *QLMTemperatureText(NSInteger temperature) {
    if (temperature == QLMMonitorValueAbsent) {
        return QLMEmDash;
    }
    return [NSString stringWithFormat:@"%ld °C", (long)temperature];
}

NSInteger QLMMeterCounts(NSInteger raw) {
    if (raw == QLMMonitorValueAbsent) {
        return -1;
    }
    return MAX(0, raw - 0x80);
}

NSString *QLMReplyAgeText(NSDate *date) {
    if (date == nil) {
        return QLMEmDash;
    }
    NSTimeInterval age = MAX(0, -date.timeIntervalSinceNow);
    if (age < 60) {
        return [NSString stringWithFormat:@"%.1f s ago", age];
    }
    static NSDateFormatter *formatter;
    if (formatter == nil) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = NSLocale.autoupdatingCurrentLocale;
        formatter.dateStyle = NSDateFormatterNoStyle;
        formatter.timeStyle = NSDateFormatterMediumStyle;
    }
    return [formatter stringFromDate:date];
}

// After `the`, "The" or "Now: the". The knob is read before the level,
// as qlmctl reads them.
static NSString *QLMTakeOverTextAfter(NSString *the, QLMSnapshot *snapshot) {
    QLMHandBack *handBack = snapshot.handBack;
    double knob = handBack.knobDecibels.doubleValue;
    double volume = handBack.volumeDecibels.doubleValue;
    switch (handBack.kind) {
    case QLMHandBackLouder:
        return [NSString stringWithFormat:@"%@ knob reads %@, above qlm's %@. At the take-over, the level would rise %@.", the,
                                          QLMDecibelsText(knob), QLMDecibelsText(volume), QLMDecibelsText(knob - volume)];
    case QLMHandBackKnobLevel:
        return [NSString stringWithFormat:@"%@ knob reads %@, at or below qlm's %@. At the take-over, the level would not rise.", the,
                                          QLMDecibelsText(knob), QLMDecibelsText(volume)];
    case QLMHandBackUnknown:
        break;
    }
    NSString *why = handBack.knobDecibels != nil ? @"qlm has set no level"
                    : snapshot.adapter.hasStatus ? @"no knob is in"
                                                 : @"qlm has not read the knob yet";
    return [NSString stringWithFormat:@"%@ level at the take-over is unknown, since %@.", the, why];
}

NSString *QLMTakeOverText(QLMSnapshot *snapshot) {
    return QLMTakeOverTextAfter(@"The", snapshot);
}

NSString *QLMHandBackLine(QLMSnapshot *snapshot) {
    return snapshot.adapter.hasStatus ? QLMTakeOverTextAfter(@"Now: the", snapshot) : nil;
}

BOOL QLMStopMayRaiseLevel(QLMSnapshot *snapshot) {
    BOOL holds = snapshot.busProblem == QLMBusProblemNone || snapshot.adapterProblem != QLMAdapterProblemNone;
    return snapshot.running && holds && snapshot.handBack.kind != QLMHandBackKnobLevel;
}

BOOL QLMStopCanMute(QLMSnapshot *snapshot) {
    return snapshot != nil && snapshot.busProblem == QLMBusProblemNone;
}

NSString *QLMStopText(QLMSnapshot *stopped) {
    if (stopped.running) {
        return @"qlm had not let go of the adapter in time.";
    }
    if (stopped.handBack.kind == QLMHandBackKnobLevel) {
        return @"qlm sent the knob's level before it let go, so the take-over changes nothing.";
    }
    if (stopped.muteAllFromStop) {
        return @"qlm muted every monitor before it let go. Its next start lifts the mute once its level is out.";
    }
    return @"qlm let go with nothing more sent.";
}

QLMQuitStep QLMQuitStepFor(BOOL stopMayRaiseLevel, OSType reason) {
    if (!stopMayRaiseLevel) {
        return QLMQuitStepStop;
    }
    switch (reason) {
    case kAEQuitAll:
    case kAELogOut:
    case kAEReallyLogOut:
    case kAERestart:
    case kAEShutDown:
        return QLMQuitStepMuteFirst;
    default:
        return QLMQuitStepAsk;
    }
}

NSString *QLMBusProblemTitle(QLMSnapshot *snapshot) {
    switch (snapshot.adapterProblem) {
    case QLMAdapterProblemUnresponsive: return @"The adapter stopped answering";
    case QLMAdapterProblemLostTrack: return @"qlm lost track of the adapter";
    case QLMAdapterProblemNotTaking: return @"The adapter stopped taking reports";
    case QLMAdapterProblemNone: break;
    }
    switch (snapshot.busProblem) {
    case QLMBusProblemNoAdapter: return @"No adapter";
    case QLMBusProblemGLM: return @"GLM has the adapter";
    case QLMBusProblemOtherHost: return @"Another app has the adapter";
    case QLMBusProblemNone: break;
    }
    return nil;
}

// The error's sentence only names the other host. Nothing decides by it.
NSString *QLMBusProblemDetail(QLMSnapshot *snapshot) {
    NSString *action = nil;
    switch (snapshot.adapterProblem) {
    case QLMAdapterProblemUnresponsive:
        action = snapshot.reconnects == 0
                     ? @"qlm tries again for about 7 s. Then it reopens the adapter, and keeps trying until the adapter answers."
                     : [NSString stringWithFormat:@"qlm is reconnecting, attempt %lu. It reopens the adapter at longer waits, up to "
                                                  @"30 s apart, until the adapter answers.",
                                                  (unsigned long)snapshot.reconnects];
        break;
    case QLMAdapterProblemLostTrack:
        action = @"qlm gave up on the adapter, and sends nothing more. Only a replug or a relaunch helps: unplug the adapter and "
                 @"plug it back in, or quit qlm and open it again.";
        break;
    case QLMAdapterProblemNotTaking:
        action = @"qlm stopped reconnecting, since each try would hold it up for seconds. Unplug the adapter, and plug it "
                 @"back in.";
        break;
    case QLMAdapterProblemNone:
        break;
    }
    // System keeps the adapter's last knob reading meanwhile.
    if (action != nil) {
        return [NSString stringWithFormat:@"%@ About 2.6 s after qlm's last report, the adapter takes over at the knob's position. %@",
                                          action, QLMTakeOverText(snapshot)];
    }
    switch (snapshot.busProblem) {
    case QLMBusProblemNoAdapter: return @"Connect the GLM adapter by USB.";
    case QLMBusProblemGLM: return @"qlm drives nothing while GLM runs. Quit GLM to hand the monitors to qlm.";
    case QLMBusProblemOtherHost:
    case QLMBusProblemNone: break;
    }
    return snapshot.adapterError.localizedDescription ?: @"Another process holds the GLM adapter.";
}

BOOL QLMSnapshotTracksMonitors(QLMSnapshot *snapshot) {
    return snapshot.running && snapshot.monitors.count > 0;
}
