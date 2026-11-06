#import <Foundation/Foundation.h>

#import "QLMScheduler.h"

NS_ASSUME_NONNULL_BEGIN

// How often a number readout may change: four times a second.
extern const NSTimeInterval QLMReadoutInterval;

// Shows a readout's text at most once each QLMReadoutInterval. A change
// after a quiet interval shows at once, and the last change always shows
// within the interval. A change its caller marks at once, as to MUTED or
// dim's level, shows at once too, and what waited is dropped. The first
// text shows at once. Foundation only. On the main queue.
@interface QLMReadoutThrottle : NSObject

- (instancetype)initWithShow:(void (^)(NSString *_Nullable text))show NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// systemUptime and QLMMainQueueScheduler() until set.
@property (nonatomic, copy) NSTimeInterval (^now)(void);
@property (nonatomic, copy) QLMScheduler schedule;

- (void)showText:(nullable NSString *)text atOnce:(BOOL)atOnce;
// Shows what waits now.
- (void)flush;

@end

NS_ASSUME_NONNULL_END
