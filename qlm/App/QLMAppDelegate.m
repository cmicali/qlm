#import "QLMAppDelegate.h"

#import "QLMAlerts.h"
#import "QLMFakeBus.h"
#import "QLMFakeBusWindowController.h"
#import "QLMFormat.h"
#import "QLMHIDAdapter.h"
#import "QLMMainMenu.h"
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
// How long a logout, restart, or shutdown waits for mute all to go out.
static const NSTimeInterval QLMMuteAllowance = 1;
// How long a stop's warning waits for System's snapshot now.
static const NSTimeInterval QLMSnapshotAllowance = 0.5;

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
// What System's bus keeps across launches. It follows the bus, so a
// snapshot from the fake bus never reaches the real monitors' store.
@property (nonatomic, readonly) QLMBusPreferences *kept;
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

// The quit Apple event's reason, or 0 with none.
static OSType QLMQuitReason(void) {
    NSAppleEventDescriptor *event = NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
    if (event.eventClass != kCoreEventClass || event.eventID != kAEQuitApplication) {
        return 0;
    }
    NSAppleEventDescriptor *reason = [event attributeDescriptorForKeyword:kAEQuitReason] ?: [event paramDescriptorForKeyword:kAEQuitReason];
    return reason.typeCodeValue;
}

@implementation QLMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSApp.mainMenu = QLMMainMenu();
    self.preferences = [[QLMPreferences alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    self.monitorList = [[QLMMonitorList alloc] init];
    self.notifier = [[QLMNotifier alloc] init];
    self.alerts = [[QLMMonitorAlerts alloc] initWithPoster:self.notifier clock:[[QLMSleepCountingClock alloc] init]];

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
// Every quit comes here: the popover's Quit, Cmd-Q, and logout, restart,
// and shut down.
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [self.settingsController endEditing];
    QLMSnapshot *now = [self snapshotNow];
    switch (QLMQuitStepFor([self stopMayRaiseLevel:now], QLMQuitReason())) {
    case QLMQuitStepAsk:
        if (![self askBeforeStop:@"Quitting" anyway:@"Quit Anyway" now:now]) {
            return NSTerminateCancel;
        }
        break;
    case QLMQuitStepMuteFirst:
        [self muteAllAndWait];
        break;
    case QLMQuitStepStop:
        break;
    }
    [self stopSystemAndWait];
    return NSTerminateNow;
}

// A logout, restart, or shutdown can't wait on the louder hand-back's alert,
// and a Mac left to restart overnight would hang on it. So every monitor is
// muted before qlm lets go. A mute outlasts the host (docs/protocol.md), so
// the take-over can't make them louder. The record keeps mute all, so the
// next launch starts muted. TRAP: a stop drops what is still queued, so
// this waits for the mute's frames to go out.
- (void)muteAllAndWait {
    QLMCallNumber call = [self.system setAllMuted:YES];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:QLMMuteAllowance];
    while (deadline.timeIntervalSinceNow > 0) {
        QLMSnapshot *latest = self.monitorList.snapshot;
        if (latest.lastCall >= call && latest.idle) {
            return;
        }
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    }
    NSLog(@"qlm: mute all did not go out within %.0f s of the quit.", QLMMuteAllowance);
}

// Only on the real monitors: on the fake bus a take-over moves no level.
- (BOOL)stopMayRaiseLevel:(QLMSnapshot *)snapshot {
    return self.bus == nil && QLMStopMayRaiseLevel(snapshot);
}

// System's snapshot now, since the latest may lag a level or a knob
// reading. While System's queue waits on an adapter that takes no report,
// the latest decides.
- (nullable QLMSnapshot *)snapshotNow {
    return [self.system snapshotNowWithin:QLMSnapshotAllowance] ?: self.monitorList.snapshot;
}

// Asks before a stop that may make the monitors louder. YES goes ahead.
- (BOOL)mayStop:(NSString *)stop anyway:(NSString *)anyway {
    QLMSnapshot *now = [self snapshotNow];
    return ![self stopMayRaiseLevel:now] || [self askBeforeStop:stop anyway:anyway now:now];
}

// A debug command's quit answers in place of the user.
- (BOOL)askBeforeStop:(NSString *)stop anyway:(NSString *)anyway now:(QLMSnapshot *)now {
#if DEBUG
    if (self.debugQuitAnswer != nil) {
        return self.debugQuitAnswer.integerValue == NSAlertSecondButtonReturn;
    }
#endif
    BOOL louder = now.handBack.kind == QLMHandBackLouder;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:louder ? @"%@ makes the monitors louder" : @"%@ may make the monitors louder", stop];
    alert.informativeText = [NSString stringWithFormat:@"%@ About 2.6 s after qlm lets go, the adapter sets %@. "
                                                       @"Turn the knob down first, or %@.",
                                                       QLMTakeOverText(now), louder ? @"the knob's level" : @"its own level",
                                                       anyway.lowercaseString];
    // Cancel is the default.
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:anyway].hasDestructiveAction = YES;
    [self activateApp];
    return [alert runModal] == NSAlertSecondButtonReturn;
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
    self.bus = bus;
    [self.monitorList forgetMonitors];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.ceilingDecibels = self.preferences.ceilingDecibels;
    [self.kept fillSettings:settings];
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:adapter settings:settings];
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
    [system setVolumeDecibels:self.kept.volumeDecibels];
}

- (QLMBusPreferences *)kept {
    return self.bus == nil ? self.preferences.adapterBus : self.preferences.fakeBus;
}

// System lets go of the adapter before the Mac sleeps. As at quit, the
// adapter takes over at the knob's level about 2.6 s after the last report
// (qlm-control-first). A louder take-over is logged, and on the real
// monitors it is an alert.
- (void)macWillSleep:(NSNotification *)notification {
    QLMSnapshot *snapshot = [self snapshotNow];
    NSLog(@"qlm: the Mac sleeps. %@", QLMHandBackLine(snapshot) ?: @"the level at the take-over is unknown.");
    if ([self stopMayRaiseLevel:snapshot]) {
        [self.alerts alertSleepWithSnapshot:snapshot];
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
// from the old System's last snapshot. Each bus keeps its own level, mute
// record, and leases. The active group, the fake bus's state, and the
// monitors seen do not carry over. A second change during a restart finds
// the new System already made, and stops.
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
    [self.kept keepFromSnapshot:snapshot];
    [self renderStatusItem];
}

- (void)renderStatusItem {
    QLMSnapshot *snapshot = self.monitorList.snapshot;
    NSString *symbol = @"hifispeaker.2";
    NSString *tip = @"qlm";
    NSString *problem = QLMBusProblemTitle(snapshot);
    if (problem != nil) {
        symbol = @"exclamationmark.triangle";
        tip = [NSString stringWithFormat:@"qlm: %@", problem];
    } else if (snapshot.allMuted) {
        symbol = @"speaker.slash";
        tip = @"qlm: muted";
    } else if (snapshot.volumeDecibels != nil) {
        tip = [NSString stringWithFormat:@"qlm: %@%@", QLMDecibelsText(snapshot.volumeDecibels.doubleValue), snapshot.dimmed ? @", dimmed" : @""];
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
            strongSelf.alerts.setup = setup;
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

- (BOOL)settingsShouldTurnOffAdapter:(QLMSettingsWindowController *)controller {
    return [self mayStop:@"Turning off the adapter" anyway:@"Turn Off Anyway"];
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
    return [self stopMayRaiseLevel:[self snapshotNow]];
}

- (void)debugQuitAnswering:(BOOL)quitAnyway {
    self.debugQuitAnswer = @(quitAnyway ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn);
    [NSApp terminate:self];
    self.debugQuitAnswer = nil;
}

@end

#endif
