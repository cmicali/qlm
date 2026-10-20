#import <Cocoa/Cocoa.h>

#import "QLMAppDelegate.h"

// No main nib. NSApplication.delegate is weak, so this keeps the delegate alive.
static QLMAppDelegate *appDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        appDelegate = [[QLMAppDelegate alloc] init];
        NSApplication.sharedApplication.delegate = appDelegate;
    }
    return NSApplicationMain(argc, argv);
}
