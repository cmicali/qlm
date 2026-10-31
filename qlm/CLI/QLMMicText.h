#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The mic as info and poll print it: ?, none, in with no readings, or in
// with its two readings as raw counts, for example "in, DE 2301456,
// DD 2298770". A missing reading prints as ?. QLMStaleText ends it.
NSString *QLMMicText(QLMAdapterState *adapter);

// After a missed 01 08, the knob and mic lines show the last status read,
// and end with this: " (stale, 3 polls missed)". Otherwise it is empty.
NSString *QLMStaleText(QLMAdapterState *adapter);

NS_ASSUME_NONNULL_END
