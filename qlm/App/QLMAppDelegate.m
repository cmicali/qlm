#import "QLMAppDelegate.h"

@interface QLMAppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@end

@implementation QLMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"hifispeaker.2"
                                             accessibilityDescription:@"qlm"];

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Not connected" action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit qlm" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

@end
