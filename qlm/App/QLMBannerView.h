#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A tinted strip that says why nothing reaches the bus: System's
// adapterError. It hides itself when there is none.
@interface QLMBannerView : NSView

// The width its text wraps at.
- (instancetype)initWithTextWidth:(CGFloat)textWidth;

- (void)showError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
