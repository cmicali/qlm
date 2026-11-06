#import "QLMAppDelegate.h"

#import "QLMAlerts.h"
#import "QLMFakeBus.h"
#import "QLMFakeBusWindowController.h"
#import "QLMFormat.h"
#import "QLMFrameCoalescer.h"
#import "QLMHIDAdapter.h"
#import "QLMMainMenu.h"
#import "QLMMainWindowController.h"
#import "QLMMonitorList.h"
#import "QLMMonitorsWindowController.h"
#import "QLMOSDController.h"
#import "QLMPopoverController.h"
#import "QLMPreferences.h"
#import "QLMSettingsWindowController.h"
#import "QLMSetupReader.h"
#import "QLMSetupWatcher.h"
#import "QLMSkinChoice.h"
#import "QLMSystem.h"
#import "QLMTrafficWindowController.h"
#if DEBUG
#import "QLMCapture.h"
#import "QLMDebugChannel.h"
#import "QLMReplayAdapter.h"
#import "QLMSkinLayers.h"
#import "QLMSkinPreview.h"
#endif

// How long quit and sleep wait for System to let go, well within the Mac's
// allowance for a sleep. A stop sends at most the hand-back level, or mute
// all, then closes the adapter.
static const NSTimeInterval QLMStopAllowance = 3;
// How long a stop's warning waits for System's snapshot now.
static const NSTimeInterval QLMSnapshotAllowance = 0.5;

@interface QLMAppDelegate () <QLMMainMenuActions, QLMMainWindowControllerDelegate, QLMPopoverControllerDelegate,
                              QLMSettingsWindowControllerDelegate>
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMMonitorAlerts *alerts;
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) NSPopover *popover;
@property (nonatomic) QLMPopoverController *popoverController;
@property (nonatomic) QLMMainWindowController *mainWindowController;
@property (nonatomic, nullable) QLMMonitorsWindowController *monitorsController;
@property (nonatomic, nullable) QLMSettingsWindowController *settingsController;
@property (nonatomic, nullable) QLMFakeBusWindowController *fakeBusController;
@property (nonatomic, nullable) QLMTrafficWindowController *trafficController;
@property (nonatomic, nullable) QLMFakeBus *bus;
@property (nonatomic, nullable) QLMSystem *system;
#if DEBUG
// QLM_REPLAY's capture, chosen once at launch, which every System plays
// back in place of any bus. Its record is its own, wiped at each launch, so
// a replay reaches neither the real monitors' record nor the fake bus's.
// TRAP: QLM_REPLAY set but unreadable runs the fake bus, never the setting's
// bus, which a Debug build shares with the installed app.
@property (nonatomic, nullable) QLMCapture *replayCapture;
@property (nonatomic, nullable) QLMBusPreferences *replayKept;  // set whenever QLM_REPLAY is
#endif
// What System's bus keeps across launches. It follows the bus, so a
// snapshot from the fake bus never reaches the real monitors' store.
@property (nonatomic, readonly) QLMBusPreferences *kept;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, nullable) NSError *setupError;
@property (nonatomic) NSUInteger setupLoads;  // the latest load wins
@property (nonatomic, nullable) QLMSetupWatcher *setupWatcher;
// What the status item shows, so an unchanged snapshot changes nothing.
@property (nonatomic, copy, nullable) NSString *statusSymbol;
@property (nonatomic, copy, nullable) NSString *statusTip;
@property (nonatomic) QLMOSDController *osdController;
@property (nonatomic) QLMSkinChoice *skinChoice;
// The windows draw the newest snapshot once a main-queue turn at most.
@property (nonatomic) QLMFrameCoalescer<QLMSnapshot *> *frames;
#if DEBUG
// A debug command's answer to the louder hand-back alert, while its quit runs.
@property (nonatomic, nullable) NSNumber *debugQuitAnswer;
#endif
- (nullable NSString *)chooseSkinNamed:(NSString *)name;
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

// The adapter's host watch checks again as GLM launches or quits.
// NSWorkspace posts both for every app with a Dock icon, as GLM is.
static dispatch_block_t QLMWatchLaunches(void (^changed)(NSString *executablePath)) {
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    void (^take)(NSNotification *) = ^(NSNotification *notification) {
        NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
        NSString *path = app.executableURL.path;
        if (path != nil) {
            changed(path);
        }
    };
    id launched = [center addObserverForName:NSWorkspaceDidLaunchApplicationNotification object:nil queue:nil usingBlock:take];
    id quit = [center addObserverForName:NSWorkspaceDidTerminateApplicationNotification object:nil queue:nil usingBlock:take];
    return ^{
        [center removeObserver:launched];
        [center removeObserver:quit];
    };
}

#if DEBUG
// QLM_REPLAY names a capture's reports.txt, which a Debug build plays back
// as the adapter, for the traffic window and the UI.
static NSString *_Nullable QLMDebugReplayPath(void) {
    const char *path = getenv("QLM_REPLAY");
    return path == NULL || path[0] == '\0' ? nil : @(path);
}

static QLMCapture *_Nullable QLMDebugReplayCapture(NSString *path) {
    NSError *error = nil;
    QLMCapture *capture = [QLMCapture captureWithContentsOfFile:path error:&error];
    if (capture == nil) {
        NSLog(@"qlm: QLM_REPLAY %@ does not read, so qlm runs the fake bus: %@", path, error.localizedDescription);
    }
    return capture;
}
#endif

@implementation QLMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.preferences = [[QLMPreferences alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    self.monitorList = [[QLMMonitorList alloc] init];
    self.skinChoice = [[QLMSkinChoice alloc] initWithPreferences:self.preferences library:[QLMSkinLibrary standardLibrary]];
    self.alerts = [[QLMMonitorAlerts alloc] initWithPoster:[[QLMNotifier alloc] init] now:^NSTimeInterval {
        return QLMSecondsCountingSleep();
    }];

    self.popoverController = [[QLMPopoverController alloc] initWithPreferences:self.preferences monitorList:self.monitorList];
    self.popoverController.delegate = self;
    self.popover = [[NSPopover alloc] init];
    self.popover.contentViewController = self.popoverController;
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.mainWindowController = [[QLMMainWindowController alloc] initWithPreferences:self.preferences monitorList:self.monitorList
                                                                                skin:self.skinChoice.skin];
    self.mainWindowController.delegate = self;
    NSApp.mainMenu = QLMMainMenu(self, self.mainWindowController);
    NSApp.windowsMenu = [NSApp.mainMenu itemWithTitle:@"Window"].submenu;
    NSApp.helpMenu = [NSApp.mainMenu itemWithTitle:@"Help"].submenu;

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);
    [self renderStatusItem];
    self.osdController = [[QLMOSDController alloc] initWithPreferences:self.preferences skin:self.skinChoice.skin];
    __weak QLMAppDelegate *weakSelf = self;
    self.frames = [[QLMFrameCoalescer alloc] initWithApply:^(QLMSnapshot *snapshot) {
        [weakSelf drawSnapshot:snapshot];
    }];

#if DEBUG
    NSString *replay = QLMDebugReplayPath();
    if (replay != nil) {
        self.replayCapture = QLMDebugReplayCapture(replay);
        NSString *suite = @"com.commonwealthrecordings.qlm.replay";
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults removePersistentDomainForName:suite];
        self.replayKept = [[QLMPreferences alloc] initWithDefaults:defaults].fakeBus;
    }
#endif
    [self startSystemDimmed:NO];
    if (self.preferences.wakesAtLaunch) {
        [self.system wake];
    }
    [self loadSetup];
    if (self.preferences.opensWindowAtLaunch) {
        [self showMainWindow:nil];
    }

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
    QLMQuitStep step = QLMQuitStepFor([self stopMayRaiseLevel:now], QLMQuitReason());
    if (step == QLMQuitStepAsk && ![self askBeforeStop:@"Quitting" anyway:@"Quit Anyway" now:now]) {
        return NSTerminateCancel;
    }
    // A Mac left to restart overnight would hang on the alert. The next
    // launch starts from the record, muted.
    [self stopSystemAndWaitMuting:step == QLMQuitStepMuteFirst];
    return NSTerminateNow;
}

// Only on the real monitors: on the fake bus a take-over moves no level.
- (BOOL)stopMayRaiseLevel:(QLMSnapshot *)snapshot {
    return self.drivesAdapter && QLMStopMayRaiseLevel(snapshot);
}

// System drives the GLM adapter: neither the fake bus nor a replay.
- (BOOL)drivesAdapter {
#if DEBUG
    if (self.replayKept != nil) {
        return NO;
    }
#endif
    return self.bus == nil;
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
#if DEBUG
    if (self.replayCapture != nil) {
        adapter = [[QLMReplayAdapter alloc] initWithCapture:self.replayCapture];
    }
#endif
    BOOL realAdapter = self.preferences.usesAdapter;
#if DEBUG
    realAdapter = realAdapter && self.replayKept == nil;
#endif
    if (adapter == nil && realAdapter) {
        QLMHIDAdapter *hid = [[QLMHIDAdapter alloc] init];
        hid.launchWatch = ^dispatch_block_t(void (^changed)(NSString *executablePath)) {
            return QLMWatchLaunches(changed);
        };
        adapter = hid;
    } else if (adapter == nil) {
        bus = [QLMFakeBus demoBusWithSubwoofer:YES];
        bus.recordsSentMessages = NO;
        // A fresh bus's knob rests at the bottom. Where the last one read
        // elsewhere, a relaunch would find it turned.
        [self.preferences.fakeBus restoreKnobOn:bus];
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
    self.mainWindowController.system = system;
    self.trafficController.system = system;
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
    // On a stopped System these only record it, so the first frame is
    // dimmed, and the start sends the app's own level, or the knob's when
    // the knob was turned since the last reading kept and sits lower.
    if (dimmed) {
        [system setDimmed:YES];
    }
    [system setVolumeDecibels:self.kept.volumeDecibels];
    [system start];
}

- (QLMBusPreferences *)kept {
#if DEBUG
    if (self.replayKept != nil) {
        return self.replayKept;
    }
#endif
    return self.drivesAdapter ? self.preferences.adapterBus : self.preferences.fakeBus;
}

// System lets go of the adapter before the Mac sleeps. As at quit, the
// adapter takes over at the knob's level about 2.6 s after the last report
// (qlm-control-first). No one can answer then, so where that may be louder,
// the stop mutes every monitor first, as a logout does, and the wake lifts
// the mute once qlm's level is out. Where the mute can't go out, it alerts.
- (void)macWillSleep:(NSNotification *)notification {
    QLMSnapshot *snapshot = [self snapshotNow];
    BOOL louder = [self stopMayRaiseLevel:snapshot];
    BOOL alerts = louder && !QLMStopCanMute(snapshot);
    if (alerts) {
        [self.alerts alertSleepWithSnapshot:snapshot];
    }
    [self stopSystemAndWaitMuting:louder];
    NSString *did = alerts ? @"The bus took no frames, so qlm could not mute the monitors, and alerted." : QLMStopText(self.system.snapshot);
    NSLog(@"qlm: the Mac sleeps. %@ %@", QLMHandBackLine(snapshot) ?: @"The level at the take-over is unknown.", did);
}

// Waits up to QLMStopAllowance for System to let go: the Mac waits for a
// sleep's handler, though not without limit. The completion runs on the
// main queue, so the run loop turns until then. TRAP: inside a block on the
// main queue, the completion waits for that block, so only the deadline
// ends the wait. A restart that finishes meanwhile starts a new System, so
// that one is stopped too.
- (void)stopSystemAndWaitMuting:(BOOL)mutes {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:QLMStopAllowance];
    QLMSystem *system = nil;
    while (self.system != system && deadline.timeIntervalSinceNow > 0) {
        system = self.system;
        __block BOOL stopped = NO;
        dispatch_block_t completion = ^{
            stopped = YES;
        };
        if (mutes) {
            [system stopMutingIfLouderWithCompletion:completion];
        } else {
            [system stopWithCompletion:completion];
        }
        while (!stopped && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
        }
    }
    // A raise of the level or the knob reading waits up to a second.
    [self.preferences flushKept];
}

// The same System starts again. It keeps the volume, dim, the mutes, and
// the active group across a stop, and takes back the leases the monitors
// still hold. It sends no level above a knob turned during the sleep, and
// lifts the sleep's mute all once its level is out.
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
    // The old bus's, as self.bus still names it. No snapshot reaches it now.
    [self.kept flushKeeping:old.snapshot];
    [self.preferences flushKept];
    __weak QLMAppDelegate *weakSelf = self;
    [old stopWithCompletion:^{
        QLMAppDelegate *strongSelf = weakSelf;
        if (strongSelf.system == old) {
            [strongSelf startSystemDimmed:old.snapshot.dimmed];
        }
    }];
}

// What a snapshot keeps, and what it alerts, goes at once, every snapshot.
// What it draws waits for the main queue's next turn, and draws the newest.
// Each window draws only while it is seen.
- (void)showSnapshot:(QLMSnapshot *)snapshot {
    [self.monitorList updateWithSnapshot:snapshot];
    [self.alerts updateWithMonitorList:self.monitorList];
    [self.kept keepFromSnapshot:snapshot];
    [self.frames submit:snapshot];
}

- (void)drawSnapshot:(QLMSnapshot *)snapshot {
    [self.popoverController refresh];
    [self.mainWindowController refresh];
    [self.monitorsController refresh];
    [self.settingsController refresh];
    [self.fakeBusController refresh];
    [self renderStatusItem];
    [self.osdController takeSnapshot:snapshot];
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
    NSStatusBarButton *button = self.statusItem.button;
    // TRAP: a new image redraws the item on every display, about 5 ms each.
    // A tooltip or a label redraws nothing.
    if (![symbol isEqualToString:self.statusSymbol]) {
        self.statusSymbol = symbol;
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        image.template = YES;
        button.image = image;
    }
    if (![tip isEqualToString:self.statusTip]) {
        self.statusTip = tip;
        button.toolTip = tip;
        button.accessibilityLabel = tip;
    }
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
    if (self.setup == nil) {
        [self.mainWindowController showSetup:nil fileName:name error:nil];
    }
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
            strongSelf.trafficController.setup = setup;
            [strongSelf.mainWindowController showSetup:setup fileName:name error:strongSelf.setupError];
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

// While the main window is closed, the app has no Dock icon, so a window or
// alert comes forward only if the app does.
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

// The window takes a Dock icon, the Cmd-Tab switcher, and the menu bar,
// as a regular app's does, until it closes. The policy goes first, so the
// activation that follows brings the window to the front.
- (void)showMainWindow:(id)sender {
    [self becomeRegular];
    [self bringForward:self.mainWindowController];
}

// TRAP: an app that turns regular while it is active shows no menu bar
// until it activates again. So it lets go and activates on the next turn.
- (void)becomeRegular {
    if (NSApp.activationPolicy == NSApplicationActivationPolicyRegular) {
        return;
    }
    BOOL active = NSApp.isActive;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (active) {
        [NSApp deactivate];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self activateApp];
        });
    }
}

// TRAP: turning accessory can deactivate the app, which would leave a
// Settings or Monitors window still open behind other apps. So that
// window comes back to the front.
- (void)mainWindowControllerWillClose:(QLMMainWindowController *)controller {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindowController *settings = self.settingsController;
    NSWindowController *monitors = self.monitorsController;
    for (NSWindow *window in NSApp.orderedWindows) {
        BOOL kept = (settings.windowLoaded && window == settings.window) || (monitors.windowLoaded && window == monitors.window);
        if (kept && window.visible) {
            [self activateApp];
            [window makeKeyAndOrderFront:nil];
            return;
        }
    }
}

// A click on the Dock icon, or an open of the app while it runs.
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    [self showMainWindow:nil];
    return NO;
}

- (void)popoverControllerShowWindow:(QLMPopoverController *)controller {
    [self showMainWindow:nil];
}

- (void)mainWindowControllerShowMonitors:(QLMMainWindowController *)controller {
    [self showMonitors:nil];
}

- (void)popoverControllerShowMonitors:(QLMPopoverController *)controller {
    [self showMonitors:nil];
}

- (void)showMonitors:(id)sender {
    if (self.monitorsController == nil) {
        self.monitorsController = [[QLMMonitorsWindowController alloc] initWithMonitorList:self.monitorList];
    }
    [self bringForward:self.monitorsController];
}

- (void)showTraffic:(id)sender {
    if (self.trafficController == nil) {
        self.trafficController = [[QLMTrafficWindowController alloc] initWithMonitorList:self.monitorList];
        self.trafficController.setup = self.setup;
        self.trafficController.system = self.system;
    }
    [self bringForward:self.trafficController];
}

- (void)popoverControllerShowSettings:(QLMPopoverController *)controller {
    [self showSettings:nil];
}

- (void)showSettings:(id)sender {
    if (self.settingsController == nil) {
        self.settingsController = [[QLMSettingsWindowController alloc] initWithPreferences:self.preferences monitorList:self.monitorList];
        self.settingsController.delegate = self;
        [self.settingsController showSetup:self.setup error:self.setupError];
        [self.settingsController showSkin:self.skinChoice.skin refusal:self.skinChoice.refusal];
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
    [self.mainWindowController reloadVolumeRange];
    [self.system setCeilingDecibels:self.preferences.ceilingDecibels];
}

- (void)settingsDidChooseSetupFile:(QLMSettingsWindowController *)controller {
    [self loadSetup];
}

- (BOOL)settingsShouldTurnOffAdapter:(QLMSettingsWindowController *)controller {
    return [self mayStop:@"Turning off the adapter" anyway:@"Turn Off Anyway"];
}

- (void)settingsDidChangeOSD:(QLMSettingsWindowController *)controller {
    [self.osdController reloadSettings];
}

- (void)settingsDidChangeAdapter:(QLMSettingsWindowController *)controller {
    [self restartSystem];
}

- (NSString *)settings:(QLMSettingsWindowController *)controller chooseSkinNamed:(NSString *)name {
    return [self chooseSkinNamed:name];
}

// Settings' picker and the skin verb share it.
- (nullable NSString *)chooseSkinNamed:(NSString *)name {
    QLMSkinChoice *choice = self.skinChoice;
    NSString *refusal = [choice chooseSkinNamed:name];
    if (refusal == nil) {
        [self.mainWindowController showSkin:choice.skin];
        self.osdController.skin = choice.skin;
        [self.settingsController showSkin:choice.skin refusal:choice.refusal];
    }
    return refusal;
}

@end

#if DEBUG

@implementation QLMAppDelegate (Debug)

// A verb reads the windows as they are, so what waits for a frame draws
// first.
- (QLMSnapshot *)debugSnapshot {
    [self.frames flush];
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
    [self showMonitors:nil];
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
    [self.frames flush];
    return self.popoverController.quitGLMTitle;
}

- (BOOL)debugQuitGLM {
    return [self.popoverController quitGLM];
}

- (BOOL)debugQuitAsksFirst {
    return [self stopMayRaiseLevel:[self snapshotNow]];
}

- (NSDictionary *)debugShowSkinPreview:(NSString *)name osd:(BOOL)osd disabled:(BOOL)disabled {
    [self.popover close];
    [self activateApp];
    return QLMShowSkinPreview(name, osd, disabled);
}

- (QLMFakeBus *)debugFakeBus {
    return self.bus;
}

- (id<QLMDebugWindow>)debugWindow {
    return self.mainWindowController;
}

- (id<QLMDebugOSD>)debugOSD {
    return self.osdController;
}

- (void)debugShowWindow {
    [self showMainWindow:nil];
}

- (void)debugDrawWindows {
    [self.frames flush];
    [self.mainWindowController drawWhileOpen];
    [self.monitorsController drawWhileOpen];
    [self.settingsController drawWhileOpen];
    [self.fakeBusController drawWhileOpen];
    [self.trafficController drawWhileOpen];
    // TRAP: a screenshot renders the presentation tree, so within an ease
    // it would catch the pointer or the OSD's bar on the way.
    QLMSkinFinishEases();
}

- (nullable QLMTrafficWindowController *)debugTraffic {
    return self.trafficController;
}

- (void)debugShowTraffic {
    [self showTraffic:nil];
}

- (QLMSkinChoice *)debugSkinChoice {
    return self.skinChoice;
}

- (NSString *)debugChooseSkin:(NSString *)name {
    return [self chooseSkinNamed:name];
}

- (void)debugQuitAnswering:(BOOL)quitAnyway {
    self.debugQuitAnswer = @(quitAnyway ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn);
    [NSApp terminate:self];
    self.debugQuitAnswer = nil;
}

@end

#endif
