#import <Cocoa/Cocoa.h>

#import "QLMPreferences.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The on-screen display: a borderless window that shows the level when the
// adapter's knob turns, then fades. QLMOSDRule decides when. On the main
// queue.
@interface QLMOSDController : NSObject

- (instancetype)initWithPreferences:(QLMPreferences *)preferences NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Call after the OSD's settings or the skin change in the preferences.
- (void)reloadPreferences;
- (void)takeSnapshot:(QLMSnapshot *)snapshot;
// Shows the snapshot's level now, as a turn would, or says why not.
- (nullable NSString *)showSnapshot:(nullable QLMSnapshot *)snapshot;
// At once, with no fade.
- (void)hide;

@property (nonatomic, readonly) BOOL showing;

@end

NS_ASSUME_NONNULL_END
