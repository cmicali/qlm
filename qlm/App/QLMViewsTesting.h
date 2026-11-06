#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Answers QLMWindowIsSeen in its place while set, as a window offscreen in
// the tests is never seen. NULL in the app. No app code imports this.
extern BOOL (*_Nullable QLMWindowIsSeenOverride)(NSWindow *_Nullable window);

NS_ASSUME_NONNULL_END
