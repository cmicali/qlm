#import <Cocoa/Cocoa.h>

#import "QLMPreferences.h"
#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

@class QLMSettingsWindowController;

@protocol QLMSettingsWindowControllerDelegate <NSObject>
// The bottom of the volume range, or the ceiling, changed in the preferences.
- (void)settingsDidChangeVolumeRange:(QLMSettingsWindowController *)controller;
// The preferences name another setup file.
- (void)settingsDidChooseSetupFile:(QLMSettingsWindowController *)controller;
@end

// Settings: the setup file, the volume range and ceiling, waking the
// monitors at launch, and opening at login. Each change is saved at once.
// On the main queue.
@interface QLMSettingsWindowController : NSWindowController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences;

@property (nonatomic, weak, nullable) id<QLMSettingsWindowControllerDelegate> delegate;

// The setup file in use, or why it did not read. Both nil: none was found.
- (void)showSetup:(nullable QLMSetup *)setup error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
