#import <Cocoa/Cocoa.h>

#import "QLMMainMenu.h"
#import "QLMMonitorList.h"
#import "QLMPreferences.h"
#import "QLMSetup.h"
#import "QLMSkin.h"
#import "QLMSystem.h"
#if DEBUG
#import "QLMDebugChannel.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@class QLMMainWindowController;

@protocol QLMMainWindowControllerDelegate <NSObject>
- (void)mainWindowControllerShowMonitors:(QLMMainWindowController *)controller;
- (void)mainWindowControllerWillClose:(QLMMainWindowController *)controller;
@end

// The main window, in the skin it is handed. It reads the monitor list's
// snapshots and drives System, never the adapter, by the popover's rules
// for what is enabled when. It answers the Controls menu by the same
// rules, through the same calls its controls make. On the main queue.
@interface QLMMainWindowController : NSWindowController <QLMMainMenuControls>

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList skin:(QLMSkin *)skin;

@property (nonatomic, weak, nullable) id<QLMMainWindowControllerDelegate> delegate;
@property (nonatomic, nullable) QLMSystem *system;
// The loaded setup, the file's name, and why it did not read.
- (void)showSetup:(nullable QLMSetup *)setup fileName:(nullable NSString *)fileName error:(nullable NSError *)error;

// Draws the monitor list's snapshot while any of the window is on screen.
// It draws again when it next comes into view.
- (void)refresh;
// Reads the volume range from the preferences again.
- (void)reloadVolumeRange;
// Draws the window in the skin, from now on.
- (void)showSkin:(QLMSkin *)skin;

@property (nonatomic, readonly, getter=isShowing) BOOL showing;
// The last apply's error, until the next click.
@property (nonatomic, readonly, copy, nullable) NSString *applyError;

// A click on the named group's button. Returns why it takes no click, or
// nil once the apply starts.
- (nullable NSString *)clickGroupNamed:(NSString *)name;
// A turn of the knob to the level, as a drag's, with the level it points
// at. The caller checks the range. Returns why not while the window is
// closed.
- (nullable NSString *)turnKnobTo:(double)decibels level:(double *)level;
// The content size, as a drag of the window's corner sets it, never below
// the skin's size. Returns why not while the window is closed.
- (nullable NSString *)resizeTo:(NSSize)size;
@property (nonatomic, readonly) NSSize contentSize;

@end

#if DEBUG
@interface QLMMainWindowController (Debug) <QLMDebugWindow>
@end
#endif

NS_ASSUME_NONNULL_END
