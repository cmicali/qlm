#import <Cocoa/Cocoa.h>

#import "QLMPreferences.h"
#import "QLMSkin.h"
#import "QLMSnapshot.h"
#if DEBUG
#import "QLMDebugChannel.h"
#endif

NS_ASSUME_NONNULL_BEGIN

// The on-screen display: a borderless window that shows the level when the
// adapter's knob turns, then fades. QLMOSDRule decides when. On the main
// queue.
@interface QLMOSDController : NSObject

- (instancetype)initWithPreferences:(QLMPreferences *)preferences skin:(QLMSkin *)skin NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// What it draws in. A change redraws it while it shows.
@property (nonatomic) QLMSkin *skin;

// Call after the OSD's settings change in the preferences.
- (void)reloadSettings;
- (void)takeSnapshot:(QLMSnapshot *)snapshot;
// Shows the snapshot's level now, as a turn would, or says why not.
- (nullable NSString *)showSnapshot:(nullable QLMSnapshot *)snapshot;
// At once, with no fade.
- (void)hide;
// Shows the level that waits its turn now, as a verb that reads the OSD
// must.
- (void)flushReadout;

@property (nonatomic, readonly) BOOL showing;

@end

#if DEBUG
@interface QLMOSDController (Debug) <QLMDebugOSD>
@end
#endif

NS_ASSUME_NONNULL_END
