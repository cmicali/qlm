#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// What QLMSkinEases asks. Only the tests import this, to swap them.
extern BOOL (*QLMSkinEaseWindowIsSeen)(NSWindow *_Nullable window);
extern BOOL (*QLMSkinEaseMotionIsReduced)(void);

NS_ASSUME_NONNULL_END
