#import "QLMFormat.h"

NSString *const QLMEmDash = @"—";

// A no-break space keeps the unit on the number's line.
NSString *QLMDecibelsText(double decibels) {
    NSString *number = [NSString stringWithFormat:@"%.1f", decibels];
    if ([number isEqualToString:@"-0.0"]) {
        number = @"0.0";
    }
    return [[number stringByReplacingOccurrencesOfString:@"-" withString:@"−"] stringByAppendingString:@"\u00A0dB"];
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

// The knob above qlm's level, and the rise, to follow "Now: ".
// "<lead> reads −10.0 dB, above qlm's −50.0 dB.": the knob against the
// level qlm sends.
static NSString *QLMKnobText(NSString *lead, NSString *relation, QLMHandBack *handBack) {
    return [NSString stringWithFormat:@"%@ reads %@, %@ qlm's %@.", lead, QLMDecibelsText(handBack.knobDecibels.doubleValue),
                                      relation, QLMDecibelsText(handBack.volumeDecibels.doubleValue)];
}

static NSString *QLMRiseText(NSString *lead, QLMHandBack *handBack) {
    double rise = handBack.knobDecibels.doubleValue - handBack.volumeDecibels.doubleValue;
    return [NSString stringWithFormat:@"%@ At the take-over, the level would rise %@.", QLMKnobText(lead, @"above", handBack),
                                      QLMDecibelsText(rise)];
}

NSString *QLMHandBackLine(QLMSnapshot *snapshot) {
    QLMHandBack *handBack = snapshot.handBack;
    switch (handBack.kind) {
    case QLMHandBackKnobLevel:
        return [NSString stringWithFormat:@"%@ qlm sends the knob's level as it stops, so the take-over changes nothing.",
                                          QLMKnobText(@"Now: the knob", @"at or below", handBack)];
    case QLMHandBackLouder:
        return QLMRiseText(@"Now: the knob", handBack);
    case QLMHandBackUnknown:
        break;
    }
    if (snapshot.adapter.hasStatus && handBack.knobDecibels == nil) {
        return @"Now: no knob is in, so the level at the take-over is unknown.";
    }
    return nil;
}

BOOL QLMStopMayRaiseLevel(QLMSnapshot *snapshot) {
    BOOL holds = snapshot.busProblem == QLMBusProblemNone || snapshot.adapterProblem != QLMAdapterProblemNone;
    return snapshot.running && holds && snapshot.handBack.kind != QLMHandBackKnobLevel;
}

NSString *QLMStopRiseText(QLMSnapshot *snapshot) {
    QLMHandBack *handBack = snapshot.handBack;
    switch (handBack.kind) {
    case QLMHandBackLouder:
        return QLMRiseText(@"The knob", handBack);
    case QLMHandBackKnobLevel:
        return [QLMKnobText(@"The knob", @"at or below", handBack) stringByAppendingString:@" At the take-over, the level would not rise."];
    case QLMHandBackUnknown:
        break;
    }
    NSString *why = handBack.volumeDecibels == nil ? @"qlm has set no level"
                    : snapshot.adapter.hasStatus   ? @"No knob is in"
                                                   : @"qlm has not read the knob yet";
    return [why stringByAppendingString:@", so the level at the take-over is unknown."];
}

NSString *QLMBusProblemTitle(QLMBusProblem problem) {
    switch (problem) {
    case QLMBusProblemNoAdapter: return @"No adapter";
    case QLMBusProblemGLM: return @"GLM has the adapter";
    case QLMBusProblemOtherHost: return @"Another app has the adapter";
    case QLMBusProblemNone: break;
    }
    return nil;
}

// The error's sentence only names the other host. Nothing decides by it.
NSString *QLMBusProblemDetail(QLMSnapshot *snapshot) {
    switch (snapshot.busProblem) {
    case QLMBusProblemNoAdapter: return @"Connect the GLM adapter by USB.";
    case QLMBusProblemGLM: return @"qlm drives nothing while GLM runs. Quit GLM to hand the monitors to qlm.";
    case QLMBusProblemOtherHost:
    case QLMBusProblemNone: break;
    }
    return snapshot.adapterError.localizedDescription ?: @"Another process holds the GLM adapter.";
}
