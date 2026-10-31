#import "QLMMicText.h"

static NSString *QLMStale(NSString *text, QLMAdapterState *adapter) {
    NSUInteger missed = adapter.missedPolls;
    if (missed == 0) {
        return text;
    }
    return [text stringByAppendingFormat:@" (stale, %lu poll%s missed)", (unsigned long)missed, missed == 1 ? "" : "s"];
}

NSString *QLMKnobText(QLMAdapterState *adapter) {
    if (!adapter.hasStatus) {
        return @"?";
    }
    NSNumber *tenths = adapter.knobTenths;
    return QLMStale(tenths != nil ? [NSString stringWithFormat:@"in, at %.1f dB", tenths.doubleValue / 10.0] : @"none", adapter);
}

NSString *QLMMicText(QLMAdapterState *adapter) {
    if (!adapter.hasStatus) {
        return @"?";
    }
    NSString *text = @"none";
    if (adapter.micPresent) {
        text = adapter.micDE == nil && adapter.micDD == nil
                   ? @"in, no readings"
                   : [NSString stringWithFormat:@"in, DE %@, DD %@", adapter.micDE ?: @"?", adapter.micDD ?: @"?"];
    }
    return QLMStale(text, adapter);
}
