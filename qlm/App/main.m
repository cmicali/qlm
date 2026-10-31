#import <Cocoa/Cocoa.h>

#import "QLMAppDelegate.h"
#if DEBUG
#import "QLMDebugChannel.h"
#endif

// No main nib. NSApplication.delegate is weak, so this keeps the delegate alive.
static QLMAppDelegate *appDelegate;

int main(int argc, const char *argv[]) {
#if DEBUG
    // The debug channel's client is this binary, so it runs before any app
    // starts.
    if (argc > 1 && strcmp(argv[1], "--debug-cmd") == 0) {
        return QLMDebugClientMain(argc, argv);
    }
#endif
    @autoreleasepool {
        appDelegate = [[QLMAppDelegate alloc] init];
        NSApplication.sharedApplication.delegate = appDelegate;
    }
    return NSApplicationMain(argc, argv);
}
