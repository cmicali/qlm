#import "QLMAppDelegate.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMAlerts.h"
#import "QLMFakeBus.h"
#import "QLMFakeBusWindowController.h"
#import "QLMFormat.h"
#import "QLMHIDAdapter.h"
#import "QLMMonitorList.h"
#import "QLMMonitorsWindowController.h"
#import "QLMPopoverController.h"
#import "QLMPreferences.h"
#import "QLMSettingsWindowController.h"
#import "QLMSetupReader.h"
#import "QLMSetupWatcher.h"
#import "QLMSystem.h"
#if DEBUG
#import "QLMDebugChannel.h"
#endif

// How long quit and sleep wait for System to let go, well within the Mac's
// allowance for a sleep. A stop sends at most the hand-back level, then
// closes the adapter.
static const NSTimeInterval QLMStopAllowance = 3;

@interface QLMAppDelegate () <QLMPopoverControllerDelegate, QLMSettingsWindowControllerDelegate>
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMMonitorAlerts *alerts;
@property (nonatomic) QLMNotifier *notifier;
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) NSPopover *popover;
@property (nonatomic) QLMPopoverController *popoverController;
@property (nonatomic, nullable) QLMMonitorsWindowController *monitorsController;
@property (nonatomic, nullable) QLMSettingsWindowController *settingsController;
@property (nonatomic, nullable) QLMFakeBusWindowController *fakeBusController;
@property (nonatomic, nullable) QLMFakeBus *bus;
@property (nonatomic, nullable) QLMSystem *system;
// The mute record last kept, as System started from it or last saved.
@property (nonatomic, copy) NSSet<NSData *> *keptMutedIDs;
@property (nonatomic) BOOL keptMutingAll;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, nullable) NSError *setupError;
@property (nonatomic) NSUInteger setupLoads;  // the latest load wins
@property (nonatomic, nullable) QLMSetupWatcher *setupWatcher;
// What the status item shows, so an unchanged snapshot does not redraw it.
@property (nonatomic, copy, nullable) NSString *statusSymbol;
@property (nonatomic, copy, nullable) NSString *statusTip;
#if DEBUG
// A debug command's answer to the louder hand-back alert, while its quit runs.
@property (nonatomic, nullable) NSNumber *debugQuitAnswer;
#endif
@end

#if DEBUG
@interface QLMAppDelegate (Debug) <QLMDebugApp>
@end
#endif

@implementation QLMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.preferences = [[QLMPreferences alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    self.monitorList = [[QLMMonitorList alloc] init];
    self.notifier = [[QLMNotifier alloc] init];
    self.alerts = [[QLMMonitorAlerts alloc] initWithNotifier:self.notifier];

    self.popoverController = [[QLMPopoverController alloc] initWithPreferences:self.preferences monitorList:self.monitorList];
    self.popoverController.delegate = self;
    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = self.popoverController;
    self.popover.behavior = NSPopoverBehaviorTransient;

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);
    [self renderStatusItem];

    [self startSystemDimmed:NO];
    if (self.preferences.wakesAtLaunch) {
        [self.system wake];
    }
    [self loadSetup];

    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(macWillSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(macDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
#if DEBUG
    QLMDebugInstallChannel(self);
#endif
}

// Quit waits for the stop, so the hand-back level goes out before qlm does.
// On the real monitors, a take-over that would raise the level asks first.
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    QLMHandBack *handBack = self.monitorList.snapshot.handBack;
    if ([self takeOverRaisesLevel:handBack] && [self answerLouderHandBack:handBack] != NSAlertSecondButtonReturn) {
        return NSTerminateCancel;
    }
    [self stopSystemAndWait];
    return NSTerminateNow;
}

// A debug command's quit answers in place of the user.
- (NSModalResponse)answerLouderHandBack:(QLMHandBack *)handBack {
#if DEBUG
    if (self.debugQuitAnswer != nil) {
        return self.debugQuitAnswer.integerValue;
    }
#endif
    [self activateApp];
    return [[self louderHandBackAlert:handBack] runModal];
}

// Only on the real monitors: on the fake bus a take-over moves no level.
- (BOOL)takeOverRaisesLevel:(QLMHandBack *)handBack {
    return handBack.kind == QLMHandBackLouder && self.bus == nil;
}

// Cancel is the default.
- (NSAlert *)louderHandBackAlert:(QLMHandBack *)handBack {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Quitting makes the monitors louder";
    alert.informativeText = [NSString stringWithFormat:@"%@ About 2.6 s after qlm quits, the adapter sets the knob's level. "
                                                       @"Turn the knob down first, or quit anyway.",
                                                       QLMHandBackRiseText(handBack)];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *quit = [alert addButtonWithTitle:@"Quit Anyway"];
    quit.hasDestructiveAction = YES;
    return alert;
}

#pragma mark - System

// TRAP: a QLMHIDAdapter drives the real monitors. Only the user's setting
// makes one. Tests and harnesses leave it off.
- (void)startSystemDimmed:(BOOL)dimmed {
    id<QLMAdapter> adapter = nil;
    QLMFakeBus *bus = nil;
    if (self.preferences.usesAdapter) {
        adapter = [[QLMHIDAdapter alloc] init];
    } else {
        bus = [QLMFakeBus demoBusWithSubwoofer:YES];
        bus.recordsSentMessages = NO;
        adapter = bus;
    }
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.ceilingDecibels = self.preferences.ceilingDecibels;
    self.keptMutedIDs = self.preferences.mutedHardwareIDs;
    self.keptMutingAll = self.preferences.mutingAll;
    settings.mutedHardwareIDs = self.keptMutedIDs;
    settings.mutingAll = self.keptMutingAll;
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:adapter settings:settings];
    self.bus = bus;
    self.system = system;
    self.popoverController.system = system;
    self.popoverController.showsFakeBus = bus != nil;
    self.fakeBusController.bus = bus;
    if (bus == nil) {
        [self.fakeBusController close];
    }

    __weak QLMAppDelegate *weakSelf = self;
    __weak QLMSystem *weakSystem = system;
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        QLMAppDelegate *strongSelf = weakSelf;
        // A snapshot from a System already replaced is stale.
        if (strongSelf != nil && weakSystem == strongSelf.system) {
            [strongSelf showSnapshot:snapshot];
        }
    } queue:dispatch_get_main_queue()];
    // On a stopped System this only records it, so the first frame is dimmed.
    if (dimmed) {
        [system setDimmed:YES];
    }
    [system start];
    // At connect, keep the app's own level. The knob moves nothing until a
    // volume is set.
    [system setVolumeDecibels:self.preferences.volumeDecibels];
}

// System lets go of the adapter before the Mac sleeps. As at quit, the
// adapter takes over at the knob's level about 2.6 s after the last report
// (qlm-control-first). No one can answer a prompt now, so a louder
// take-over is logged, and on the real monitors it is a notification.
- (void)macWillSleep:(NSNotification *)notification {
    QLMSnapshot *snapshot = self.monitorList.snapshot;
    NSLog(@"qlm: the Mac sleeps. %@", QLMHandBackLine(snapshot) ?: @"the level at the take-over is unknown.");
    if ([self takeOverRaisesLevel:snapshot.handBack]) {
        [self.notifier postIdentifier:@"hand-back"
                                title:@"The level may have risen as the Mac slept"
                                 body:QLMHandBackRiseText(snapshot.handBack)];
    }
    [self stopSystemAndWait];
}

// Waits up to QLMStopAllowance for System to let go: the Mac waits for a
// sleep's handler, though not without limit. The completion runs on the
// main queue, so the run loop turns until then. TRAP: inside a block on the
// main queue, the completion waits for that block, so only the deadline
// ends the wait. A restart that finishes meanwhile starts a new System, so
// that one is stopped too.
- (void)stopSystemAndWait {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:QLMStopAllowance];
    QLMSystem *system = nil;
    while (self.system != system && deadline.timeIntervalSinceNow > 0) {
        system = self.system;
        __block BOOL stopped = NO;
        [system stopWithCompletion:^{
            stopped = YES;
        }];
        while (!stopped && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
        }
    }
}

// The same System starts again. It keeps the volume, dim, the mutes, and
// the active group across a stop, and takes back the leases the monitors
// still hold.
- (void)macDidWake:(NSNotification *)notification {
    [self.system start];
}

// A new adapter setting takes a new System, with a new adapter: a stopped
// one is not handed to another. The new System starts once the old has let
// go, so the two never hold the adapter at once. Dim carries over, read
// from the old System's last snapshot. Each bus keeps its own mute record.
// The active group and the fake bus's state do not carry over. A second
// change during a restart finds the new System already made, and stops.
- (void)restartSystem {
    QLMSystem *old = self.system;
    [old setSnapshotHandler:nil queue:dispatch_get_main_queue()];
    __weak QLMAppDelegate *weakSelf = self;
    [old stopWithCompletion:^{
        QLMAppDelegate *strongSelf = weakSelf;
        if (strongSelf.system == old) {
            [strongSelf startSystemDimmed:old.snapshot.dimmed];
        }
    }];
}

- (void)showSnapshot:(QLMSnapshot *)snapshot {
    [self.monitorList updateWithSnapshot:snapshot];
    [self.alerts updateWithMonitorList:self.monitorList];
    [self.popoverController refresh];
    [self.monitorsController refresh];
    [self.settingsController refresh];
    if (self.fakeBusController.window.visible) {
        [self.fakeBusController refresh];
    }
    [self keepMuteRecord:snapshot];
    // The knob moves the volume too. Keep whichever set it last.
    NSNumber *volume = snapshot.volumeDecibels;
    if (volume != nil) {
        double kept = fmin(volume.doubleValue, snapshot.ceilingDecibels);
        if (fabs(kept - self.preferences.volumeDecibels) >= QLMVolumeDecibelsStep / 2) {
            self.preferences.volumeDecibels = kept;
        }
    }
    [self renderStatusItem];
}

// TRAP: a snapshot from before System starts carries an empty record, not
// the one System starts from. Only a running System's record is kept. It is
// compared with the last one kept, not read back from the defaults.
- (void)keepMuteRecord:(QLMSnapshot *)snapshot {
    if (!snapshot.running) {
        return;
    }
    if (![snapshot.mutedHardwareIDs isEqualToSet:self.keptMutedIDs]) {
        self.keptMutedIDs = snapshot.mutedHardwareIDs;
        self.preferences.mutedHardwareIDs = snapshot.mutedHardwareIDs;
    }
    if (snapshot.mutingAll != self.keptMutingAll) {
        self.keptMutingAll = snapshot.mutingAll;
        self.preferences.mutingAll = snapshot.mutingAll;
    }
}

- (void)renderStatusItem {
    QLMSnapshot *snapshot = self.monitorList.snapshot;
    NSString *symbol = @"hifispeaker.2";
    NSString *tip = @"qlm";
    NSString *problem = QLMBusProblemTitle(snapshot.busProblem);
    if (problem != nil) {
        symbol = @"exclamationmark.triangle";
        tip = [NSString stringWithFormat:@"qlm: %@", problem];
    } else if (snapshot.allMuted) {
        symbol = @"speaker.slash";
        tip = @"qlm: muted";
    } else if (snapshot.volumeDecibels != nil) {
        double volume = fmin(snapshot.volumeDecibels.doubleValue, snapshot.ceilingDecibels);
        tip = [NSString stringWithFormat:@"qlm: %@%@", QLMDecibelsText(volume), snapshot.dimmed ? @", dimmed" : @""];
    }
    if ([symbol isEqualToString:self.statusSymbol] && [tip isEqualToString:self.statusTip]) {
        return;
    }
    self.statusSymbol = symbol;
    self.statusTip = tip;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.button.toolTip = tip;
}

#pragma mark - The setup file

// The watch starts before the read, so a save during the read still
// offers to read again.
- (void)loadSetup {
    NSUInteger load = ++self.setupLoads;
    NSString *chosen = self.preferences.setupFileName;
    NSArray<NSString *> *names = QLMSetupFileNames();
    NSString *name = chosen != nil && [names containsObject:chosen] ? chosen : names.firstObject;
    NSString *path = name == nil ? nil : [QLMSetupDirectory() stringByAppendingPathComponent:name];
    self.popoverController.changedSetupName = nil;
    [self watchSetupAtPath:path];
    __weak QLMAppDelegate *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        QLMSetup *setup = path == nil ? nil : [QLMSetupReader readFileAtPath:path error:&error];
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

// When GLM saves the file in use, the popover offers to read it again.
- (void)watchSetupAtPath:(nullable NSString *)path {
    if (path != nil && [path isEqualToString:self.setupWatcher.path]) {
        return;
    }
    [self.setupWatcher stop];
    self.setupWatcher = nil;
    if (path == nil) {
        return;
    }
    __weak QLMAppDelegate *weakSelf = self;
    self.setupWatcher = [[QLMSetupWatcher alloc] initWithPath:path queue:dispatch_get_main_queue() handler:^{
        weakSelf.popoverController.changedSetupName = path.lastPathComponent;
    }];
    [self.setupWatcher start];
}

- (void)popoverControllerReadSetupAgain:(QLMPopoverController *)controller {
    [self loadSetup];
}

#pragma mark - Windows

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
}

// The app has no Dock icon, so a window or alert comes forward only if the
// app does.
- (void)activateApp {
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)bringForward:(NSWindowController *)controller {
    [self.popover close];
    [self activateApp];
    [controller showWindow:self];
}

- (void)popoverControllerShowMonitors:(QLMPopoverController *)controller {
    if (self.monitorsController == nil) {
        self.monitorsController = [[QLMMonitorsWindowController alloc] initWithMonitorList:self.monitorList];
    }
    [self bringForward:self.monitorsController];
}

- (void)popoverControllerShowSettings:(QLMPopoverController *)controller {
    if (self.settingsController == nil) {
        self.settingsController = [[QLMSettingsWindowController alloc] initWithPreferences:self.preferences monitorList:self.monitorList];
        self.settingsController.delegate = self;
        [self.settingsController showSetup:self.setup error:self.setupError];
    }
    [self bringForward:self.settingsController];
}

- (void)popoverControllerShowFakeBus:(QLMPopoverController *)controller {
    if (self.bus == nil) {
        return;
    }
    if (self.fakeBusController == nil) {
        self.fakeBusController = [[QLMFakeBusWindowController alloc] init];
        self.fakeBusController.bus = self.bus;
    }
    [self bringForward:self.fakeBusController];
}

#pragma mark - Settings

// System caps every frame at once, and sends a volume already set again
// under the new ceiling. Mutes and the active group are untouched.
- (void)settingsDidChangeVolumeRange:(QLMSettingsWindowController *)controller {
    [self.popoverController reloadVolumeRange];
    [self.system setCeilingDecibels:self.preferences.ceilingDecibels];
}

- (void)settingsDidChooseSetupFile:(QLMSettingsWindowController *)controller {
    [self loadSetup];
}

- (void)settingsDidChangeAdapter:(QLMSettingsWindowController *)controller {
    [self restartSystem];
}

@end

#if DEBUG

@implementation QLMAppDelegate (Debug)

- (QLMSnapshot *)debugSnapshot {
    return self.monitorList.snapshot;
}

- (NSPopover *)debugPopover {
    return self.popover;
}

- (void)debugShowPopover {
    if (!self.popover.isShown) {
        [self togglePopover:nil];
    }
}

- (void)debugShowMonitors {
    [self popoverControllerShowMonitors:self.popoverController];
}

- (void)debugShowSettings {
    [self popoverControllerShowSettings:self.popoverController];
}

- (void)debugReadSetup {
    [self popoverControllerReadSetupAgain:self.popoverController];
}

- (QLMSystem *)debugSystem {
    return self.system;
}

- (QLMPreferences *)debugPreferences {
    return self.preferences;
}

// Settings draws the preferences as its window opens, so an open one keeps
// the old value.
- (void)debugVolumeRangeDidChange {
    [self settingsDidChangeVolumeRange:self.settingsController];
}

- (void)debugAdapterDidChange {
    [self settingsDidChangeAdapter:self.settingsController];
}

- (NSString *)debugQuitGLMTitle {
    return self.popoverController.quitGLMTitle;
}

- (BOOL)debugQuitGLM {
    return [self.popoverController quitGLM];
}

- (BOOL)debugQuitAsksFirst {
    return [self takeOverRaisesLevel:self.monitorList.snapshot.handBack];
}

- (void)debugQuitAnswering:(BOOL)quitAnyway {
    self.debugQuitAnswer = @(quitAnyway ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn);
    [NSApp terminate:self];
    self.debugQuitAnswer = nil;
}

@end

#endif
