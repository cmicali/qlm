#import "QLMMicText.h"

NSString *QLMMicText(QLMAdapterState *adapter) {
    if (!adapter.hasStatus) {
        return @"?";
    }
    if (!adapter.micPresent) {
        return @"none";
    }
    return [NSString stringWithFormat:@"in, DE %@, DD %@", adapter.micDE, adapter.micDD];
}
