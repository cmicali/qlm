#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// What QLMSkinEases asks. The tests swap them. No app code but
// QLMSkinLayers.m imports this.
extern BOOL (*QLMSkinEaseWindowIsSeen)(NSWindow *_Nullable window);
extern BOOL (*QLMSkinEaseMotionIsReduced)(void);

NS_ASSUME_NONNULL_END
