#import "QLMAppDelegate.h"

#import "QLMFakeBus.h"
#import "QLMPopoverController.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"

@interface QLMAppDelegate ()
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) NSPopover *popover;
@property (nonatomic) QLMSystem *system;
@property (nonatomic) QLMPopoverController *controller;
@end

// The first setup file GLM saved, by name. Nil when there is none or it
// does not read.
static QLMSetup *_Nullable QLMLoadSetup(void) {
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Genelec/GLM5/Setup Files"];
    NSArray<NSString *> *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name.pathExtension caseInsensitiveCompare:@"sam"] == NSOrderedSame) {
            return [QLMSetupReader readFileAtPath:[directory stringByAppendingPathComponent:name] error:NULL];
        }
    }
    return nil;
}

@implementation QLMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Until the adapter over HID exists, the app runs on a fake bus, so the
    // menu bar and the popover can be seen working.
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:YES];
    bus.recordsSentMessages = NO;
    self.system = [[QLMSystem alloc] initWithAdapter:bus settings:[[QLMSystemSettings alloc] init]];
    self.controller = [[QLMPopoverController alloc] initWithSystem:self.system];

    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = self.controller;
    self.popover.behavior = NSPopoverBehaviorTransient;

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"hifispeaker.2" accessibilityDescription:@"qlm"];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);

    __weak QLMAppDelegate *weakSelf = self;
    [self.system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        QLMAppDelegate *strongSelf = weakSelf;
        [strongSelf.controller showSnapshot:snapshot];
        strongSelf.statusItem.button.toolTip = [NSString stringWithFormat:@"qlm: %lu monitors", (unsigned long)snapshot.monitors.count];
    } queue:dispatch_get_main_queue()];
    [self.system start];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        QLMSetup *setup = QLMLoadSetup();
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.controller.setup = setup;
        });
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.system stop];
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
}

@end
