#import <Cocoa/Cocoa.h>

#import "QLMPreferences.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The on-screen display: a borderless window that shows the level when the
// adapter's knob turns, then fades. It takes no focus and no clicks, joins
// every Space, and shows over full-screen apps. QLMOSDRule decides when. It
// rereads the preferences, the skin among them, whenever the defaults
// change. On the main queue.
@interface QLMOSDController : NSObject

- (instancetype)initWithPreferences:(QLMPreferences *)preferences NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Takes each snapshot. It shows the OSD when the rule says so.
- (void)takeSnapshot:(QLMSnapshot *)snapshot;
// Shows the snapshot's level now, as a turn would. NO with no level yet.
- (BOOL)showSnapshot:(QLMSnapshot *)snapshot;
// Orders it out at once, with no fade.
- (void)hide;

@property (nonatomic, readonly) BOOL showing;
@property (nonatomic, readonly) NSWindow *window;

@end

NS_ASSUME_NONNULL_END
