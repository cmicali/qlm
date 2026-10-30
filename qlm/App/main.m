#import <Cocoa/Cocoa.h>

#import "QLMAppDelegate.h"
#import "QLMDebugChannel.h"

// No main nib. NSApplication.delegate is weak, so this keeps the delegate alive.
static QLMAppDelegate *appDelegate;

int main(int argc, const char *argv[]) {
#if DEBUG
    // `qlm debug <verb> …` runs this binary as the debug channel's client.
    if (argc > 1 && strcmp(argv[1], "debug") == 0) {
        @autoreleasepool {
            NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
            return QLMDebugClientMain([arguments subarrayWithRange:NSMakeRange(2, arguments.count - 2)]);
        }
    }
#endif
    @autoreleasepool {
        appDelegate = [[QLMAppDelegate alloc] init];
        NSApplication.sharedApplication.delegate = appDelegate;
    }
    return NSApplicationMain(argc, argv);
}
