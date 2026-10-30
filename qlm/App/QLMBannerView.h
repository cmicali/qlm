#import <Cocoa/Cocoa.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QLMBannerStyle) {
    QLMBannerStyleWarning,  // orange: nothing reaches the bus
    QLMBannerStyleNotice,   // the accent color: something to act on
};

// A tinted strip with a title, a detail, and an optional button. It hides
// itself when there is no title.
@interface QLMBannerView : NSView

// The width its text wraps at.
- (instancetype)initWithTextWidth:(CGFloat)textWidth style:(QLMBannerStyle)style;

- (void)showTitle:(nullable NSString *)title detail:(nullable NSString *)detail;

// Why nothing reaches the bus, from the snapshot's busProblem.
- (void)showBusProblemOf:(nullable QLMSnapshot *)snapshot;

// Under the text, hidden until a caller sets it up and shows it.
@property (nonatomic, readonly) NSButton *actionButton;

@end

NS_ASSUME_NONNULL_END
