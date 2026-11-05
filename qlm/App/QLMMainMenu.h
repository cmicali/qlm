#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The menu's own actions, which the app delegate answers.
@protocol QLMMainMenuActions
- (void)showMainWindow:(nullable id)sender;
- (void)showMonitors:(nullable id)sender;
- (void)showSettings:(nullable id)sender;
@end

// The Controls menu's actions, which the main window's controller answers
// by its controls' rules, only while the main window is key.
@protocol QLMMainMenuControls <NSMenuItemValidation>
// The Controls menu, which QLMMainMenu sets as it builds it.
@property (nonatomic, weak, nullable) NSMenu *controlsMenu;
- (void)toggleMute:(nullable id)sender;
- (void)toggleDim:(nullable id)sender;
- (void)togglePower:(nullable id)sender;
- (void)volumeUp:(nullable id)sender;
- (void)volumeDown:(nullable id)sender;
// The sender's representedObject is the group's index among those the
// window shows, so two groups of one name stay apart.
- (void)chooseGroup:(NSMenuItem *)sender;
@end

// The app's main menu: qlm, File, Edit, Controls, Window, and Help. macOS
// shows it while the main window is open, when qlm takes a Dock icon. Its
// key equivalents work while any of qlm's windows is key.
NSMenu *QLMMainMenu(id<QLMMainMenuActions> app, id<QLMMainMenuControls> controls);

// Puts one item per group in the Controls menu, in place of the last, on
// Cmd-1 to Cmd-9. The window shows at most six.
void QLMMainMenuSetGroups(NSMenu *controls, NSArray<NSString *> *names, id<QLMMainMenuControls> target);

NS_ASSUME_NONNULL_END
