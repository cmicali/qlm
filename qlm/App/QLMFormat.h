#import <Foundation/Foundation.h>

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

// System's adapterError says another host has the adapter.
BOOL QLMAdapterErrorIsBusy(NSError *_Nullable error);

// The banner's lines for System's adapterError.
NSString *QLMAdapterErrorTitle(NSError *error);
NSString *QLMAdapterErrorDetail(NSError *error);

NS_ASSUME_NONNULL_END
