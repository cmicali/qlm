#import "QLMFormat.h"

#import "QLMAdapter.h"
#import "QLMSnapshot.h"

static NSString *const QLMEmDash = @"—";

NSString *QLMDecibelsText(double decibels) {
    NSString *text = [NSString stringWithFormat:@"%.1f dB", decibels];
    if ([text isEqualToString:@"-0.0 dB"]) {
        return @"0.0 dB";
    }
    return [text stringByReplacingOccurrencesOfString:@"-" withString:@"−"];
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
    return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
}

NSString *QLMAdapterErrorTitle(NSError *error) {
    if ([error.domain isEqualToString:QLMAdapterErrorDomain]) {
        if (error.code == QLMAdapterErrorBusy) {
            return @"Another host has the adapter";
        }
        if (error.code == QLMAdapterErrorDisconnected) {
            return @"No adapter";
        }
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
