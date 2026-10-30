#import "QLMAppDelegate.h"

#include <math.h>

#import "QLMFakeBus.h"
#import "QLMFakeBusWindowController.h"
#import "QLMFormat.h"
#import "QLMMonitorList.h"
#import "QLMMonitorsWindowController.h"
#import "QLMPopoverController.h"
#import "QLMPreferences.h"
#import "QLMSettingsWindowController.h"
#import "QLMSetupReader.h"
#import "QLMSystem.h"

// A ceiling change restarts System. Steps closer together than this make one.
static const NSTimeInterval QLMRestartDelay = 0.6;

@interface QLMAppDelegate () <QLMPopoverControllerDelegate, QLMSettingsWindowControllerDelegate>
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) NSPopover *popover;
@property (nonatomic) QLMPopoverController *popoverController;
@property (nonatomic, nullable) QLMMonitorsWindowController *monitorsController;
@property (nonatomic, nullable) QLMSettingsWindowController *settingsController;
@property (nonatomic, nullable) QLMFakeBusWindowController *fakeBusController;
@property (nonatomic, nullable) QLMFakeBus *bus;
@property (nonatomic, nullable) QLMSystem *system;
@property (nonatomic, nullable) QLMSnapshot *snapshot;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, nullable) NSError *setupError;
@property (nonatomic) NSUInteger setupLoads;  // the latest load wins
@end

@implementation QLMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.preferences = [[QLMPreferences alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    self.monitorList = [[QLMMonitorList alloc] init];

    self.popoverController = [[QLMPopoverController alloc] initWithPreferences:self.preferences];
    self.popoverController.delegate = self;
    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = self.popoverController;
    self.popover.behavior = NSPopoverBehaviorTransient;

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);
    [self renderStatusItem];

    [self startSystem];
    if (self.preferences.wakesAtLaunch) {
        [self.system wake];
    }
    [self loadSetup];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.system stop];
}

#pragma mark - System

// TRAP: the app runs on the fake bus. The controls are not yet checked on
// real monitors, so it never makes a QLMHIDAdapter.
- (void)startSystem {
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:YES];
    bus.recordsSentMessages = NO;
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.ceilingDecibels = self.preferences.ceilingDecibels;
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    self.bus = bus;
    self.system = system;
    self.popoverController.system = system;
    self.fakeBusController.bus = bus;

    __weak QLMAppDelegate *weakSelf = self;
    __weak QLMSystem *weakSystem = system;
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        QLMAppDelegate *strongSelf = weakSelf;
        // A snapshot from a System already replaced is stale.
        if (strongSelf != nil && weakSystem == strongSelf.system) {
            [strongSelf showSnapshot:snapshot];
        }
    } queue:dispatch_get_main_queue()];
    [system start];
    // At connect, keep the app's own level. The knob moves nothing until a
    // volume is set.
    [system setVolumeDecibels:self.preferences.volumeDecibels];
}

// System copies its settings when made, so a new ceiling takes a new System.
// It takes a new fake bus too: a stopped adapter is not handed to another.
// Dim carries over. Mute does not: it is per monitor, and the new System
// has leased none yet.
- (void)restartSystem {
    QLMSystem *old = self.system;
    BOOL dimmed = self.snapshot.dimmed;
    [old setSnapshotHandler:nil queue:dispatch_get_main_queue()];
    [old stop];
    [self startSystem];
    if (dimmed) {
        [self.system setDimmed:YES];
    }
}

- (void)showSnapshot:(QLMSnapshot *)snapshot {
    self.snapshot = snapshot;
    [self.monitorList updateWithSnapshot:snapshot];
    NSArray<QLMMonitorEntry *> *monitors = self.monitorList.entries;
    [self.popoverController showSnapshot:snapshot monitors:monitors];
    [self.monitorsController showSnapshot:snapshot monitors:monitors];
    if (self.fakeBusController.window.visible) {
        [self.fakeBusController refresh];
    }
    // The knob moves the volume too. Keep whichever set it last.
    NSNumber *volume = snapshot.volumeDecibels;
    if (volume != nil) {
        double kept = fmin(volume.doubleValue, self.preferences.ceilingDecibels);
        if (fabs(kept - self.preferences.volumeDecibels) >= 0.25) {
            self.preferences.volumeDecibels = kept;
        }
    }
    [self renderStatusItem];
}

- (void)renderStatusItem {
    QLMSnapshot *snapshot = self.snapshot;
    NSString *symbol = @"hifispeaker.2";
    NSString *tip = @"qlm";
    if (snapshot.adapterError != nil) {
        symbol = @"exclamationmark.triangle";
        tip = [NSString stringWithFormat:@"qlm: %@", QLMAdapterErrorTitle(snapshot.adapterError)];
    } else if (snapshot.allMuted) {
        symbol = @"speaker.slash";
        tip = @"qlm: muted";
    } else if (snapshot.volumeDecibels != nil) {
        double volume = fmin(snapshot.volumeDecibels.doubleValue, self.preferences.ceilingDecibels);
        tip = [NSString stringWithFormat:@"qlm: %@%@", QLMDecibelsText(volume), snapshot.dimmed ? @", dimmed" : @""];
    }
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.button.toolTip = tip;
}

#pragma mark - The setup file

- (void)loadSetup {
    NSUInteger load = ++self.setupLoads;
    NSString *chosen = self.preferences.setupFileName;
    __weak QLMAppDelegate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSString *> *names = QLMSetupFileNames();
        NSString *name = chosen != nil && [names containsObject:chosen] ? chosen : names.firstObject;
        NSError *error = nil;
        QLMSetup *setup = name == nil ? nil : [QLMSetupReader readFileAtPath:[QLMSetupDirectory() stringByAppendingPathComponent:name]
                                                                       error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            QLMAppDelegate *strongSelf = weakSelf;
            if (strongSelf == nil || load != strongSelf.setupLoads) {
                return;
            }
            strongSelf.setup = setup;
            strongSelf.setupError = setup == nil ? error : nil;
            strongSelf.popoverController.setup = setup;
            [strongSelf.settingsController showSetup:setup error:strongSelf.setupError];
        });
    });
}

#pragma mark - Windows

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
}

// The app has no Dock icon, so a window comes forward only if the app does.
- (void)bringForward:(NSWindowController *)controller {
    [self.popover close];
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }
    [controller showWindow:self];
    [controller.window makeKeyAndOrderFront:self];
}

- (void)popoverControllerShowMonitors:(QLMPopoverController *)controller {
    if (self.monitorsController == nil) {
        self.monitorsController = [[QLMMonitorsWindowController alloc] init];
        if (self.snapshot != nil) {
            [self.monitorsController showSnapshot:self.snapshot monitors:self.monitorList.entries];
        }
    }
    [self bringForward:self.monitorsController];
}

- (void)popoverControllerShowSettings:(QLMPopoverController *)controller {
    if (self.settingsController == nil) {
        self.settingsController = [[QLMSettingsWindowController alloc] initWithPreferences:self.preferences];
        self.settingsController.delegate = self;
        [self.settingsController showSetup:self.setup error:self.setupError];
    }
    [self bringForward:self.settingsController];
}

- (void)popoverControllerShowFakeBus:(QLMPopoverController *)controller {
    if (self.fakeBusController == nil) {
        self.fakeBusController = [[QLMFakeBusWindowController alloc] init];
        self.fakeBusController.bus = self.bus;
    }
    [self bringForward:self.fakeBusController];
}

#pragma mark - Settings

- (void)settingsDidChangeVolumeRange:(QLMSettingsWindowController *)controller {
    [self.popoverController reloadVolumeRange];
    double ceiling = self.preferences.ceilingDecibels;
    QLMSystem *system = self.system;
    if (system == nil || system.settings.ceilingDecibels == ceiling) {
        return;
    }
    // Until the restart, keep the level under the new ceiling.
    NSNumber *volume = self.snapshot.volumeDecibels;
    if (volume != nil && volume.doubleValue > ceiling) {
        [system setVolumeDecibels:ceiling];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(restartSystem) object:nil];
    [self performSelector:@selector(restartSystem) withObject:nil afterDelay:QLMRestartDelay];
}

- (void)settingsDidChooseSetupFile:(QLMSettingsWindowController *)controller {
    [self loadSetup];
}

@end
