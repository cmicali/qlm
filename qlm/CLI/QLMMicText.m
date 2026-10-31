#import "QLMMicText.h"

NSString *QLMMicText(QLMAdapterState *adapter) {
    if (!adapter.hasStatus) {
        return @"?";
    }
    NSString *text = @"none";
    if (adapter.micPresent && adapter.micDE == nil && adapter.micDD == nil) {
        text = @"in, no readings";
    } else if (adapter.micPresent) {
        text = [NSString stringWithFormat:@"in, DE %@, DD %@", adapter.micDE ?: @"?", adapter.micDD ?: @"?"];
    }
    return [text stringByAppendingString:QLMStaleText(adapter)];
}

NSString *QLMStaleText(QLMAdapterState *adapter) {
    NSUInteger missed = adapter.missedPolls;
    if (missed == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@" (stale, %lu poll%s missed)", (unsigned long)missed, missed == 1 ? "" : "s"];
}
