#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// GLM 5, when it runs: an app whose executable QLMHostCheck counts as GLM.
NSRunningApplication *_Nullable QLMRunningGLM(void);

// System's adapterError says another host has the adapter.
BOOL QLMAdapterErrorIsBusy(NSError *_Nullable error);

NS_ASSUME_NONNULL_END
