#import "QLMAppDelegate.h"

#import "QLMFakeBus.h"
#import "QLMPopoverController.h"
#include "QLMReplies.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"

@interface QLMAppDelegate ()
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) NSPopover *popover;
@property (nonatomic) QLMSystem *system;
@property (nonatomic) QLMPopoverController *controller;
@end

@implementation QLMAppDelegate

// Until the adapter over HID exists, the app runs on a fake bus of three
// monitors, so the menu bar and the popover can be seen working.
- (id<QLMAdapter>)makeAdapter {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    const uint8_t subID[3] = {0x77, 0x88, 0x99};
    QLMFakeMonitor *left = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:leftID length:3]
                                                        serialNumber:@"8330apm21001234" systemInfo:@"c-1;model-8330A;ver-1.14.7"
                                                         deviceClass:QLMTelemetryClassTwoWay];
    QLMFakeMonitor *right = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:rightID length:3]
                                                         serialNumber:@"8330apm21005678" systemInfo:@"c-1;model-8330A;ver-1.14.7"
                                                          deviceClass:QLMTelemetryClassTwoWay];
    QLMFakeMonitor *sub = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:subID length:3]
                                                       serialNumber:@"7350apm21009999" systemInfo:@"c-1;model-7350A;ver-1.14.7"
                                                        deviceClass:QLMTelemetryClassSubwoofer];
    right.temperature = 41;
    sub.temperature = 33;
    return [[QLMFakeBus alloc] initWithMonitors:@[left, right, sub]];
}

// The first setup file GLM saved, by name. Nil when there is none or it
// does not read.
- (nullable QLMSetup *)loadSetup {
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

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    self.system = [[QLMSystem alloc] initWithAdapter:[self makeAdapter] settings:settings];
    self.controller = [[QLMPopoverController alloc] initWithSystem:self.system setup:[self loadSetup]];

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
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.system stop];
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }
    // Load the view before the first snapshot lands in it.
    [self.controller showSnapshot:self.system.snapshot];
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
}

@end
