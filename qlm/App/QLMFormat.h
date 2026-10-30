#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// What a value with no reading shows.
extern NSString *const QLMEmDash;

// "−30.0 dB", with a true minus sign.
NSString *QLMDecibelsText(double decibels);

// "38 °C", or an em dash when absent.
NSString *QLMTemperatureText(NSInteger temperature);

// A raw meter reading as counts above the meter's floor, 80. A count is
// about 1 dB (docs/refused-frames.md). -1 when absent.
NSInteger QLMMeterCounts(NSInteger raw);

// "0.4 s ago" within a minute, then the time of day. An em dash for nil.
// On the main queue: it keeps one formatter.
NSString *QLMReplyAgeText(NSDate *_Nullable date);

// What a stop would do to the level now, from the snapshot's hand-back.
// Nil while no volume is set, and for no snapshot.
NSString *_Nullable QLMHandBackLine(QLMSnapshot *_Nullable snapshot);

// For a louder hand-back: the knob above qlm's level, and the rise.
NSString *QLMHandBackRiseText(QLMHandBack *handBack);

// The banner's lines for the snapshot's busProblem. The title is nil when
// there is none.
NSString *_Nullable QLMBusProblemTitle(QLMBusProblem problem);
NSString *QLMBusProblemDetail(QLMSnapshot *snapshot);

NS_ASSUME_NONNULL_END
