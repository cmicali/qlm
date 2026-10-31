#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The app's main menu: Quit, Close, and the text fields' edit commands. qlm
// is a menu bar item with no Dock icon, so macOS never shows the menu. Its
// key equivalents still work while one of qlm's windows is key.
NSMenu *QLMMainMenu(void);

NS_ASSUME_NONNULL_END
