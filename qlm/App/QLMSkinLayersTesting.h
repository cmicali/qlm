#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// What QLMSkinEases asks of Reduce Motion. The tests swap it. No app code but
// QLMSkinLayers.m imports this.
extern BOOL (*QLMSkinEaseMotionIsReduced)(void);

NS_ASSUME_NONNULL_END
