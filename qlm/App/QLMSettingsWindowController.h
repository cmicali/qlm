#import <Cocoa/Cocoa.h>

#import "QLMMonitorList.h"
#import "QLMPreferences.h"
#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMSettingsWindowController;

@protocol QLMSettingsWindowControllerDelegate <NSObject>
// The bottom of the volume range, or the ceiling, changed in the preferences.
- (void)settingsDidChangeVolumeRange:(QLMSettingsWindowController *)controller;
// The preferences name another setup file.
- (void)settingsDidChooseSetupFile:(QLMSettingsWindowController *)controller;
// The user turns the adapter off, which stops the real monitors. NO keeps
// it on.
- (BOOL)settingsShouldTurnOffAdapter:(QLMSettingsWindowController *)controller;
// The preferences switched between the GLM adapter and the fake bus.
- (void)settingsDidChangeAdapter:(QLMSettingsWindowController *)controller;
// The OSD's setting, place, or seconds changed in the preferences.
- (void)settingsDidChangeOSD:(QLMSettingsWindowController *)controller;
// The user picked a skin. Returns the library's refusal, and then nothing
// changes.
- (nullable NSString *)settings:(QLMSettingsWindowController *)controller chooseSkinNamed:(NSString *)name;
@end

// Settings: the GLM adapter or the fake bus and its hand-back, the setup
// file, the volume range and ceiling, waking the monitors and opening the
// main window at launch, opening at login, the skin, and the OSD. Each
// change is saved at once. On the main queue.
@interface QLMSettingsWindowController : NSWindowController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList;

@property (nonatomic, weak, nullable) id<QLMSettingsWindowControllerDelegate> delegate;

// The setup file in use, or why it did not read. Both nil: none was found.
- (void)showSetup:(nullable QLMSetup *)setup error:(nullable NSError *)error;

// Draws the hand-back from the monitor list's snapshot while the window is
// open.
- (void)refresh;

// Draws the skin's picker, its note, and the groups note again, after the
// skin changed elsewhere, while the window is open.
- (void)reloadSkin;

// Saves a field still being edited, as Return would.
- (void)endEditing;

@end

NS_ASSUME_NONNULL_END
