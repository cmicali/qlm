#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// How often a number readout may change: four times a second.
extern const NSTimeInterval QLMReadoutInterval;

// Shows a readout's text at most once each QLMReadoutInterval. A change
// after a quiet interval shows at once, and the last change always shows
// within the interval. A change of the text's kind shows at once, so a
// readout that turns to MUTED, or DIM's level, is never held. Foundation
// only. On the main queue.
@interface QLMReadoutThrottle : NSObject

- (instancetype)initWithShow:(void (^)(NSString *text))show NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The clock and the one-shot timer. systemUptime and dispatch_after on the
// main queue until set.
@property (nonatomic, copy) NSTimeInterval (^now)(void);
@property (nonatomic, copy) void (^schedule)(NSTimeInterval delay, dispatch_block_t block);

// `kind` names what the text says apart from its number.
- (void)showText:(NSString *)text kind:(NSString *)kind;
// Shows what waits now.
- (void)flush;
// Forgets what shows, so the next text shows at once, as on a new view.
- (void)reset;

// The last text shown.
@property (nonatomic, readonly, copy, nullable) NSString *shownText;

@end

NS_ASSUME_NONNULL_END
