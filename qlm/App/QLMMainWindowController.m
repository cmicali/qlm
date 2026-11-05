#import "QLMMainWindowController.h"

#include "QLMCommands.h"
#import "QLMFormat.h"
#import "QLMMainWindowModel.h"
#import "QLMSkinView.h"
#import "QLMViews.h"

static NSString *const QLMMainWindowAutosaveName = @"QLMMainWindow";
// A blink's half: about two a second.
static const NSTimeInterval QLMBlinkInterval = 0.25;

@interface QLMMainWindowController () <NSWindowDelegate>
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMMainWindowModel *model;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic) QLMSkin *skin;
@property (nonatomic, nullable) QLMSkinView *skinView;
@property (nonatomic, nullable) NSTimer *blinkTimer;
@property (nonatomic) NSTimeInterval knobTurnedAt;
@end

@implementation QLMMainWindowController {
    QLMPreferences *_preferences;
    BOOL _windowMade;
}

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList skin:(QLMSkin *)skin {
    self = [super initWithWindow:nil];
    if (self) {
        _preferences = preferences;
        _monitorList = monitorList;
        _model = [[QLMMainWindowModel alloc] init];
        [self showSkin:skin];
        [self reloadVolumeRange];
    }
    return self;
}

// Built at the first use, since the window is closed at most launches.
- (NSWindow *)window {
    if (!_windowMade) {
        _windowMade = YES;
        [self makeWindow];
    }
    return super.window;
}

- (void)makeWindow {
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                              | NSWindowStyleMaskResizable;
    NSWindow *window = QLMSkinHostWindow(self.skin, style);
    window.title = @"qlm";
    // The Window menu names it itself.
    window.excludedFromWindowsMenu = YES;
    window.delegate = self;
    super.window = window;
    [self hostSkin];
    if ([window setFrameUsingName:QLMMainWindowAutosaveName]) {
        [self growToSkin];
    } else {
        [window center];
    }
    window.frameAutosaveName = QLMMainWindowAutosaveName;
}

// A frame kept under a skin with a smaller size could be too small for this
// one.
- (void)growToSkin {
    NSWindow *window = super.window;
    NSSize size = window.contentView.bounds.size;
    NSSize minimum = self.skin.windowSize;
    if (size.width < minimum.width || size.height < minimum.height) {
        [window setContentSize:QLMSizeAtLeast(size, minimum)];
    }
}

- (void)showSkin:(QLMSkin *)skin {
    self.skin = skin;
    self.model.groupCapacity = QLMSkinGroupButtonCount(skin);
    if (!_windowMade) {
        [self renderGroups];
        return;
    }
    super.window.contentMinSize = skin.windowSize;
    [self growToSkin];
    [self hostSkin];
}

- (void)hostSkin {
    QLMSkinView *view = [[QLMSkinView alloc] initWithSkin:self.skin];
    QLMSkinHost(super.window, view);
    self.skinView = view;

    view.display.accessibilityElement = YES;
    view.display.accessibilityRole = NSAccessibilityStaticTextRole;
    view.display.accessibilityLabel = @"Level";
    view.status.accessibilityElement = YES;
    view.status.accessibilityRole = NSAccessibilityStaticTextRole;
    view.status.accessibilityLabel = @"Monitors online";
    for (QLMSkinButtonView *button in view.groupButtons) {
        button.tag = (NSInteger)[view.groupButtons indexOfObject:button];
        button.target = self;
        button.action = @selector(groupClicked:);
        button.accessibilityRole = NSAccessibilityRadioButtonRole;
    }
    view.muteButton.target = self;
    view.muteButton.action = @selector(muteClicked:);
    view.muteButton.accessibilityRole = NSAccessibilityCheckBoxRole;
    view.muteButton.accessibilitySubrole = NSAccessibilityToggleSubrole;
    view.muteButton.accessibilityLabel = @"Mute all";
    view.dimButton.target = self;
    view.dimButton.action = @selector(dimClicked:);
    view.dimButton.accessibilityRole = NSAccessibilityCheckBoxRole;
    view.dimButton.accessibilitySubrole = NSAccessibilityToggleSubrole;
    view.dimButton.accessibilityLabel = [NSString stringWithFormat:@"Dim by %.0f dB", QLMDimDecibels];
    view.knob.target = self;
    view.knob.action = @selector(knobTurned:);
    view.knob.accessibilityLabel = @"Volume";
    view.monitorsButton.target = self;
    view.monitorsButton.action = @selector(monitorsClicked:);
    view.monitorsButton.accessibilityLabel = @"Show the monitors";
    view.powerButton.target = self;
    view.powerButton.action = @selector(powerClicked:);
    self.knobTurnedAt = 0;
    [self renderGroups];
    [self renderRange];
    [self render];
}

- (BOOL)isShowing {
    return _windowMade && super.window.visible;
}

- (NSString *)applyError {
    return self.model.applyError.localizedDescription;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self renderAtOnce];
}

// What changed while the window was out of view shows at once.
- (void)renderAtOnce {
    QLMSkinWithoutEase(^{
        [self render];
    });
}

- (void)windowWillClose:(NSNotification *)notification {
    [self stopBlink];
    [self.delegate mainWindowControllerWillClose:self];
}

// Escape closes it, as Cmd-W does. The window sends it here as Escape's
// default action.
- (void)cancelOperation:(id)sender {
    [super.window performClose:sender];
}

- (void)showSetup:(QLMSetup *)setup fileName:(NSString *)fileName error:(NSError *)error {
    self.setup = setup;
    self.model.groupNames = setup.groupNames;
    self.model.setupFileName = fileName;
    self.model.setupError = error.localizedDescription;
    [self renderGroups];
    [self refresh];
}

- (void)reloadVolumeRange {
    self.model.lowestDecibels = _preferences.lowestDecibels;
    self.model.ceilingDecibels = _preferences.ceilingDecibels;
    self.knobTurnedAt = 0;
    [self renderRange];
    [self refresh];
}

- (void)refresh {
    if (_windowMade && QLMWindowIsSeen(super.window)) {
        [self render];
    }
}

#if DEBUG
- (void)drawWhileOpen {
    if (self.showing) {
        [self render];
    }
}
#endif

// A window that comes into view catches up at once.
- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
    if (QLMWindowIsSeen(super.window)) {
        [self renderAtOnce];
    } else {
        [self stopBlink];
    }
}

#pragma mark - Actions

- (void)setSystem:(QLMSystem *)system {
    _system = system;
    self.model.hasSystem = system != nil;
    [self refresh];
}

- (void)groupClicked:(QLMSkinButtonView *)button {
    [self clickGroupAtIndex:(NSUInteger)button.tag];
}

- (void)clickGroupAtIndex:(NSUInteger)index {
    NSArray<NSString *> *names = self.model.shownGroupNames;
    if (index < names.count) {
        (void)[self clickGroup:names[index] atIndex:index];
    }
}

- (NSString *)clickGroupNamed:(NSString *)name {
    return [self clickGroup:name atIndex:[self.model.shownGroupNames indexOfObject:name]];
}

// As the popover's picker: the error shows until the next click. Returns
// why the button takes no click, or nil once the apply starts.
- (nullable NSString *)clickGroup:(NSString *)name atIndex:(NSUInteger)index {
    QLMMainWindowModel *model = self.model;
    model.snapshot = self.monitorList.snapshot;
    NSString *refusal = [model refusalToClickGroupNamed:name];
    if (refusal != nil) {
        return refusal;
    }
    QLMSetupGroup *group = self.setup.groups[index];
    model.clickedGroupName = group.name;
    model.applyPending = YES;
    model.applyError = nil;
    [self refresh];
    __weak QLMMainWindowController *weakSelf = self;
    [self.system applyGroup:group completion:^(NSError *error) {
        QLMMainWindowController *strongSelf = weakSelf;
        strongSelf.model.applyPending = NO;
        strongSelf.model.applyError = error;
        [strongSelf refresh];
    }];
    return nil;
}

// In the common modes, so it blinks on through a live resize.
- (void)startBlink {
    if (self.blinkTimer != nil || !QLMWindowIsSeen(super.window)) {
        return;
    }
    self.model.blinkOn = YES;
    self.blinkTimer = [NSTimer timerWithTimeInterval:QLMBlinkInterval target:self selector:@selector(blink:) userInfo:nil
                                             repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.blinkTimer forMode:NSRunLoopCommonModes];
}

- (void)stopBlink {
    [self.blinkTimer invalidate];
    self.blinkTimer = nil;
}

- (void)blink:(NSTimer *)timer {
    self.model.blinkOn = !self.model.blinkOn;
    NSUInteger chosen = self.model.chosenGroupIndex;
    if (chosen < self.skinView.groupButtons.count) {
        self.skinView.groupButtons[chosen].selected = self.model.blinkOn;
    }
}

- (void)muteClicked:(id)sender {
    [self.system setAllMuted:!self.monitorList.snapshot.allMuted];
}

- (void)dimClicked:(id)sender {
    [self.system setDimmed:!self.monitorList.snapshot.dimmed];
}

// The knob sends only its steps.
- (void)knobTurned:(QLMKnobControl *)knob {
    double decibels = knob.doubleValue;
    self.knobTurnedAt = NSProcessInfo.processInfo.systemUptime;
    self.skinView.display.level = QLMDecibelsNumberText(decibels, 1);
    // Once the hold lapses, the display catches up with no new snapshot.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh) object:nil];
    [self performSelector:@selector(refresh) withObject:nil afterDelay:QLMLevelHoldInterval inModes:@[NSRunLoopCommonModes]];
    [self.system setVolumeDecibels:decibels];
}

- (NSString *)turnKnobTo:(double)decibels level:(double *)level {
    if (!self.showing) {
        return QLMWindowClosedRefusal;
    }
    [self render];
    QLMKnobControl *knob = self.skinView.knob;
    [knob moveTo:decibels];
    *level = knob.doubleValue;
    return nil;
}

- (NSString *)resizeTo:(NSSize)size {
    if (!self.showing) {
        return QLMWindowClosedRefusal;
    }
    NSWindow *window = super.window;
    // Within the screen, so the frame kept on quit still shows.
    NSRect visible = (window.screen ?: NSScreen.mainScreen).visibleFrame;
    NSSize most = [window contentRectForFrameRect:visible].size;
    size = NSMakeSize(MIN(size.width, most.width), MIN(size.height, most.height));
    [window setContentSize:QLMSizeAtLeast(size, self.skin.windowSize)];
    NSRect frame = window.frame;
    if (NSMaxY(frame) > NSMaxY(visible)) {
        frame.origin.y = MAX(NSMinY(visible), NSMaxY(visible) - frame.size.height);
        [window setFrame:frame display:YES];
    }
    return nil;
}

- (NSSize)contentSize {
    return _windowMade ? super.window.contentView.bounds.size : NSZeroSize;
}

- (void)monitorsClicked:(id)sender {
    [self.delegate mainWindowControllerShowMonitors:self];
}

- (void)powerClicked:(id)sender {
    if (self.monitorList.snapshot.anyOn) {
        [self.system sleep];
    } else {
        [self.system wake];
    }
}

#pragma mark - The menu

@synthesize controlsMenu = _controlsMenu;

// It lists the groups the window shows.
- (void)setControlsMenu:(NSMenu *)controlsMenu {
    _controlsMenu = controlsMenu;
    [self renderGroups];
}

- (void)toggleMute:(id)sender {
    [self muteClicked:sender];
}

- (void)toggleDim:(id)sender {
    [self dimClicked:sender];
}

- (void)togglePower:(id)sender {
    [self powerClicked:sender];
}

- (void)volumeUp:(id)sender {
    [self stepVolumeBy:1];
}

- (void)volumeDown:(id)sender {
    [self stepVolumeBy:-1];
}

- (void)chooseGroup:(NSMenuItem *)sender {
    [self clickGroupAtIndex:[sender.representedObject unsignedIntegerValue]];
}

// The menu acts on the window it names, so not while another of qlm's
// windows, or none, has the keys.
- (BOOL)menuActs {
    return self.showing && NSApp.keyWindow == super.window;
}

// Through the knob, as its arrow keys turn it, so its action sends the
// level. Not before a level is known.
- (BOOL)canStepVolumeBy:(int)steps {
    self.model.snapshot = self.monitorList.snapshot;
    QLMMainWindowModel *model = self.model;
    return model.knobEnabled && model.knobDecibels != nil && [self.skinView.knob canStepBy:steps];
}

- (void)stepVolumeBy:(int)steps {
    if ([self menuActs] && [self canStepVolumeBy:steps]) {
        [self.skinView.knob stepBy:steps];
    }
}

// Each item's state and title follow the snapshot even while the menu
// doesn't act, so a disabled item shows no stale check or title.
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    BOOL acts = [self menuActs];
    QLMMainWindowModel *model = self.model;
    model.snapshot = self.monitorList.snapshot;
    SEL action = item.action;
    if (action == @selector(toggleMute:)) {
        item.state = model.muteOn ? NSControlStateValueOn : NSControlStateValueOff;
        return acts && model.muteEnabled;
    }
    if (action == @selector(toggleDim:)) {
        item.state = model.dimOn ? NSControlStateValueOn : NSControlStateValueOff;
        return acts && model.dimEnabled;
    }
    if (action == @selector(togglePower:)) {
        item.title = model.powerTitle;
        return acts && model.powerEnabled;
    }
    if (action == @selector(volumeUp:) || action == @selector(volumeDown:)) {
        return acts && [self canStepVolumeBy:action == @selector(volumeUp:) ? 1 : -1];
    }
    if (action == @selector(chooseGroup:)) {
        NSArray<NSString *> *names = model.shownGroupNames;
        NSUInteger index = [item.representedObject unsignedIntegerValue];
        item.state = index == model.chosenGroupIndex ? NSControlStateValueOn : NSControlStateValueOff;
        return acts && index < names.count && [model refusalToClickGroupNamed:names[index]] == nil;
    }
    return NO;
}

#pragma mark - Drawing

// What changes only with the setup or the skin.
- (void)renderGroups {
    QLMSkinView *view = self.skinView;
    QLMMainWindowModel *model = self.model;
    if (self.controlsMenu != nil) {
        QLMMainMenuSetGroups(self.controlsMenu, model.shownGroupNames, self);
    }
    [view setGroupTitles:model.groupTitles prefixes:model.groupPrefixes];
    NSArray<NSString *> *names = model.shownGroupNames;
    for (NSUInteger i = 0; i < names.count && i < view.groupButtons.count; i++) {
        view.groupButtons[i].accessibilityLabel = names[i];
    }
}

// What changes only with the range.
- (void)renderRange {
    QLMSkinView *view = self.skinView;
    view.knob.minValue = self.model.lowestDecibels;
    view.knob.maxValue = self.model.ceilingDecibels;
    view.knobMin = self.model.knobMinText;
    view.knobMax = self.model.knobMaxText;
}

- (void)render {
    QLMSkinView *view = self.skinView;
    if (view == nil) {
        return;
    }
    QLMMainWindowModel *model = self.model;
    model.snapshot = self.monitorList.snapshot;
    BOOL held = QLMLevelHolds(self.knobTurnedAt, NSProcessInfo.processInfo.systemUptime);

    view.status.text = model.statusText;
    view.status.lit = model.statusLit;
    view.status.enabled = model.statusEnabled;
    view.status.toolTip = model.busProblem;

    if (model.applying) {
        [self startBlink];
    } else {
        [self stopBlink];
    }
    NSUInteger selected = model.selectedGroupIndex;
    NSUInteger chosen = model.chosenGroupIndex;
    BOOL enabled = model.groupsEnabled;
    NSUInteger shown = model.shownGroupNames.count;
    for (NSUInteger i = 0; i < shown && i < view.groupButtons.count; i++) {
        QLMSkinButtonView *button = view.groupButtons[i];
        button.selected = i == selected;
        button.enabled = enabled;
        button.accessibilityValue = @(i == chosen);
    }
    view.groupsMessage = model.groupsMessage;

    QLMSkinDisplayView *display = view.display;
    display.caption = model.caption;
    if (!held) {
        display.level = model.levelText;
    }
    display.output = model.outputText;
    display.max = model.maxText;
    display.disabled = model.displayDisabled;
    display.toolTip = model.applyError.localizedDescription;

    view.muteButton.selected = model.muteOn;
    view.muteButton.ledLit = model.muteOn;
    view.muteButton.enabled = model.muteEnabled;
    view.muteButton.accessibilityValue = @(model.muteOn);
    view.dimButton.selected = model.dimOn;
    view.dimButton.enabled = model.dimEnabled;
    view.dimButton.accessibilityValue = @(model.dimOn);

    QLMKnobControl *knob = view.knob;
    knob.enabled = model.knobEnabled;
    knob.waitsForLevel = model.knobDecibels == nil;
    // With no level to show, the knob stays where it is.
    NSNumber *level = model.knobDecibels;
    if (level != nil && !held) {
        knob.doubleValue = level.doubleValue;
    }

    view.powerButton.title = model.powerTitle;
    view.powerButton.enabled = model.powerEnabled;
    view.powerButton.accessibilityLabel = model.powerWakes ? @"Wake the monitors" : @"Put the monitors in standby";
}

@end

#if DEBUG
@implementation QLMMainWindowController (Debug)
@end
#endif
