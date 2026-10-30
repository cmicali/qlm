#import "QLMGLM.h"

#import "QLMAdapter.h"
#import "QLMHostCheck.h"

NSRunningApplication *QLMRunningGLM(void) {
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *path = app.executableURL.path;
        if (path != nil && QLMHostCheckIsGLMExecutable(path)) {
            return app;
        }
    }
    return nil;
}

BOOL QLMAdapterErrorIsBusy(NSError *error) {
    return [error.domain isEqualToString:QLMAdapterErrorDomain] && error.code == QLMAdapterErrorBusy;
}
