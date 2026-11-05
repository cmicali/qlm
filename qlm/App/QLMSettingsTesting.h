#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// What Settings asks before it draws a snapshot. The tests swap it. No app
// code but QLMSettingsWindowController.m imports this.
extern BOOL (*QLMSettingsWindowIsSeen)(NSWindow *_Nullable window);

NS_ASSUME_NONNULL_END
