#import <Cocoa/Cocoa.h>

#import "QLMMonitorList.h"
#import "QLMPreferences.h"
#import "QLMSetup.h"
#import "QLMSystem.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMMainWindowController;

@protocol QLMMainWindowControllerDelegate <NSObject>
- (void)mainWindowControllerShowMonitors:(QLMMainWindowController *)controller;
@end

// The main window, in the chosen skin. It reads the monitor list's snapshots
// and drives System, never the adapter, by the popover's rules for what is
// enabled when. On the main queue.
@interface QLMMainWindowController : NSWindowController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList;

@property (nonatomic, weak, nullable) id<QLMMainWindowControllerDelegate> delegate;
@property (nonatomic, nullable) QLMSystem *system;
// The loaded setup, the file's name, and why it did not read.
- (void)showSetup:(nullable QLMSetup *)setup fileName:(nullable NSString *)fileName error:(nullable NSError *)error;

// Draws the monitor list's snapshot while the window shows. It draws again
// when it next shows.
- (void)refresh;
// Reads the volume range from the preferences again.
- (void)reloadVolumeRange;
// Shows the named skin and keeps it in the preferences. Returns the
// library's refusal, and keeps nothing, for a skin that does not load.
- (nullable NSString *)chooseSkinNamed:(NSString *)name;
// The skin that shows: the preference's, or the default for a refused one.
@property (nonatomic, readonly, copy) NSString *shownSkinName;

@property (nonatomic, readonly, getter=isShowing) BOOL showing;
// The last apply's error, until the next click.
@property (nonatomic, readonly, copy, nullable) NSString *applyError;

// A click on the named group's button. Returns why it takes no click, or
// nil once the apply starts.
- (nullable NSString *)clickGroupNamed:(NSString *)name;
// A turn of the knob to the level, as a drag's. The caller checks the
// range. Returns the level the knob points at.
- (double)turnKnobTo:(double)decibels;

@end

NS_ASSUME_NONNULL_END
