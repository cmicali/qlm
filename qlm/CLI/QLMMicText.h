#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The mic as info and poll print it: ?, none, or in with its two readings
// as raw counts, for example "in, DE 2301456, DD 2298770".
NSString *QLMMicText(QLMAdapterState *adapter);

NS_ASSUME_NONNULL_END
