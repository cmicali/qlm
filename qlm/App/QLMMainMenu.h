#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The menu's own action, which the app delegate answers.
@protocol QLMMainMenuActions
- (void)showMainWindow:(nullable id)sender;
@end

// The app's main menu: Quit, Close, the text fields' edit commands, and the
// Window menu. qlm is a menu bar item with no Dock icon, so macOS never
// shows the menu. Its key equivalents still work while one of qlm's windows
// is key.
NSMenu *QLMMainMenu(void);

NS_ASSUME_NONNULL_END
