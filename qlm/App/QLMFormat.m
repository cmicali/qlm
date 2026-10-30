#import "QLMFormat.h"

#import "QLMAdapter.h"
#import "QLMSnapshot.h"

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

BOOL QLMAdapterErrorIsBusy(NSError *error) {
    return [error.domain isEqualToString:QLMAdapterErrorDomain] && error.code == QLMAdapterErrorBusy;
}

NSString *QLMHandBackLine(QLMSnapshot *snapshot) {
    QLMHandBack *handBack = snapshot.handBack;
    switch (handBack.kind) {
    case QLMHandBackKnobLevel:
        return [NSString stringWithFormat:@"Now: the knob reads %@, at or below qlm's %@. qlm sends the knob's level as it stops, "
                                          @"so the take-over changes nothing.",
                                          QLMDecibelsText(handBack.knobDecibels.doubleValue),
                                          QLMDecibelsText(handBack.volumeDecibels.doubleValue)];
    case QLMHandBackLouder:
        return [@"Now: " stringByAppendingString:QLMHandBackRiseText(handBack)];
    case QLMHandBackUnknown:
        break;
    }
    if (snapshot.adapter.hasStatus && handBack.knobDecibels == nil) {
        return @"Now: no knob is in, so the level at the take-over is unknown.";
    }
    return nil;
}

NSString *QLMHandBackRiseText(QLMHandBack *handBack) {
    double knob = handBack.knobDecibels.doubleValue;
    double volume = handBack.volumeDecibels.doubleValue;
    return [NSString stringWithFormat:@"The knob reads %@, above qlm's %@. At the take-over, the level would rise %@.",
                                      QLMDecibelsText(knob), QLMDecibelsText(volume), QLMDecibelsText(knob - volume)];
}

NSString *QLMAdapterErrorTitle(NSError *error) {
    if (QLMAdapterErrorIsBusy(error)) {
        return @"Another host has the adapter";
    }
    if ([error.domain isEqualToString:QLMAdapterErrorDomain] && error.code == QLMAdapterErrorDisconnected) {
        return @"No adapter";
    }
    return @"The adapter failed";
}

NSString *QLMAdapterErrorDetail(NSError *error) {
    NSString *description = error.userInfo[NSLocalizedDescriptionKey];
    if (description != nil) {
        return description;
    }
    if ([error.domain isEqualToString:QLMAdapterErrorDomain] && error.code == QLMAdapterErrorDisconnected) {
        return @"No GLM adapter is connected.";
    }
    return error.localizedDescription;
}
