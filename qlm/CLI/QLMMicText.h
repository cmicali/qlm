#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The knob and the mic as info and poll print them. Before a status, each is
// ?. After a missed 01 08, each shows the last status read, and ends with
// " (stale, 3 polls missed)".

// none, or in at its position, for example "in, at -77.5 dB".
NSString *QLMKnobText(QLMAdapterState *adapter);

// none, in with no readings, or in with its two readings as raw counts, for
// example "in, DE 2301456, DD 2298770". A missing reading prints as ?.
NSString *QLMMicText(QLMAdapterState *adapter);

NS_ASSUME_NONNULL_END
