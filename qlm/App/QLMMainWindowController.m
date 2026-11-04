#import "QLMMainWindowController.h"

#include "QLMCommands.h"
#import "QLMFormat.h"
#import "QLMMainWindowModel.h"
#import "QLMSkinLibrary.h"
#import "QLMSkinView.h"

static NSString *const QLMMainWindowAutosaveName = @"QLMMainWindow";
// A blink's half: about two a second.
static const NSTimeInterval QLMBlinkInterval = 0.25;

@interface QLMMainWindowController () <NSWindowDelegate>
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMMainWindowModel *model;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic) QLMSkin *skin;
@property (nonatomic, nullable) QLMSkinView *skinView;
@property (nonatomic, nullable) NSTimer *blinkTimer;
@property (nonatomic) NSTimeInterval knobTurnedAt;
@end

@implementation QLMMainWindowController {
    BOOL _windowMade;
}

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList {
    self = [super initWithWindow:nil];
    if (self) {
        _preferences = preferences;
        _monitorList = monitorList;
        _model = [[QLMMainWindowModel alloc] init];
        _skin = [self loadSkinNamed:preferences.skinName refusal:NULL];
        _model.groupCapacity = QLMSkinGroupButtonCount(_skin);
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
    NSAssert(self.skin != nil, @"the default skin is refused");
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                              | NSWindowStyleMaskResizable;
    NSWindow *window = QLMSkinHostWindow(self.skin, style);
    window.title = @"qlm";
    // The Window menu names it itself.
    window.excludedFromWindowsMenu = YES;
    window.delegate = self;
    super.window = window;
    [self showSkin:self.skin];
    if ([window setFrameUsingName:QLMMainWindowAutosaveName]) {
        [self growToSkin];
    } else {
        [window center];
    }
    window.frameAutosaveName = QLMMainWindowAutosaveName;
}

// With the library's fallback: a refused name gives the default skin.
- (QLMSkin *)loadSkinNamed:(NSString *)name refusal:(NSString *_Nullable *_Nullable)refusal {
    return [[QLMSkinLibrary standardLibrary] loadSkinNamed:name refusal:refusal];
}

// A frame kept under a skin with a smaller size could be too small for this
// one.
- (void)growToSkin {
    NSWindow *window = super.window;
    NSSize minimum = self.skin.windowSize;
    window.contentMinSize = minimum;
    NSSize size = window.contentView.bounds.size;
    if (size.width < minimum.width || size.height < minimum.height) {
        [window setContentSize:NSMakeSize(MAX(size.width, minimum.width), MAX(size.height, minimum.height))];
    }
}

- (void)showSkin:(QLMSkin *)skin {
    self.skin = skin;
    self.model.groupCapacity = QLMSkinGroupButtonCount(skin);
    if (!_windowMade) {
        return;
    }
    [self growToSkin];
    QLMSkinView *view = [[QLMSkinView alloc] initWithSkin:skin];
    QLMSkinHost(super.window, view);
    self.skinView = view;

    view.logo = QLMSkinLogo;
    view.tagline = QLMSkinTagline;
    view.groupsTitle = QLMSkinGroupsTitle;
    view.knobCaption = QLMSkinKnobCaption;
    view.display.unit = @"dB";
    view.muteButton.title = @"MUTE";
    view.dimButton.title = [@"DIM " stringByAppendingString:QLMDecibelsNumberText(-QLMDimDecibels, 0)];
    view.monitorsButton.title = @"Monitors";

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

- (NSString *)chooseSkinNamed:(NSString *)name {
    NSString *refusal = nil;
    QLMSkin *skin = [self loadSkinNamed:name refusal:&refusal];
    if (refusal != nil) {
        return refusal;
    }
    self.preferences.skinName = name;
    [self showSkin:skin];
    return nil;
}

- (NSString *)shownSkinName {
    return self.skin.name;
}

- (BOOL)isShowing {
    return _windowMade && super.window.visible;
}

- (NSString *)applyError {
    return self.model.applyError.localizedDescription;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self render];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self stopBlink];
}

// Escape closes it, as Cmd-W does. The window sends it here as Escape's
// default action.
- (void)cancelOperation:(id)sender {
    [super.window performClose:sender];
}

- (void)showSetup:(QLMSetup *)setup fileName:(NSString *)fileName error:(NSError *)error {
    self.setup = setup;
    NSMutableArray<NSString *> *names = nil;
    if (setup != nil) {
        names = [NSMutableArray array];
        for (QLMSetupGroup *group in setup.groups) {
            [names addObject:group.name];
        }
    }
    self.model.groupNames = names;
    self.model.setupFileName = fileName;
    self.model.setupError = error.localizedDescription;
    [self renderGroups];
    [self refresh];
}

- (void)reloadVolumeRange {
    self.model.lowestDecibels = self.preferences.lowestDecibels;
    self.model.ceilingDecibels = self.preferences.ceilingDecibels;
    self.knobTurnedAt = 0;
    [self renderRange];
    [self refresh];
}

- (void)refresh {
    if (self.showing) {
        [self render];
    }
}

#pragma mark - Actions

- (void)groupClicked:(QLMSkinButtonView *)button {
    (void)[self applyGroupAtIndex:(NSUInteger)button.tag];
}

- (NSString *)clickGroupNamed:(NSString *)name {
    self.model.snapshot = self.monitorList.snapshot;
    NSArray<NSString *> *names = self.model.shownGroupNames;
    NSUInteger index = [names indexOfObject:name];
    if (index == NSNotFound) {
        return names.count == 0 ? [NSString stringWithFormat:@"no group buttons show: %@", self.model.groupsMessage]
                                : [NSString stringWithFormat:@"no group button reads %@. They read: %@", name,
                                                             [names componentsJoinedByString:@", "]];
    }
    return [self applyGroupAtIndex:index];
}

// As the popover's picker: the error shows until the next click. Returns
// why the button takes no click, or nil once the apply starts.
- (nullable NSString *)applyGroupAtIndex:(NSUInteger)index {
    QLMMainWindowModel *model = self.model;
    model.snapshot = self.monitorList.snapshot;
    QLMSystem *system = self.system;
    if (system == nil) {
        return @"System is not running";
    }
    if (!model.groupsEnabled) {
        return model.applying ? @"the group buttons are disabled while an apply runs"
                              : @"the group buttons are disabled until System tracks a monitor";
    }
    if (index >= model.shownGroupNames.count) {
        return @"no group button there";
    }
    QLMSetupGroup *group = self.setup.groups[index];
    model.clickedGroupName = group.name;
    model.applyPending = YES;
    model.applyError = nil;
    [self refresh];
    __weak QLMMainWindowController *weakSelf = self;
    [system applyGroup:group completion:^(NSError *error) {
        QLMMainWindowController *strongSelf = weakSelf;
        strongSelf.model.applyPending = NO;
        strongSelf.model.applyError = error;
        [strongSelf refresh];
    }];
    return nil;
}

// In the common modes, so it blinks on through a live resize.
- (void)startBlink {
    if (self.blinkTimer != nil || !self.showing) {
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

- (void)knobTurned:(QLMKnobControl *)knob {
    double decibels = QLMNearestStepDecibels(knob.doubleValue);
    self.knobTurnedAt = NSProcessInfo.processInfo.systemUptime;
    self.skinView.display.level = QLMDecibelsNumberText(decibels, 1);
    // Once the hold lapses, the display catches up with no new snapshot.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refresh) object:nil];
    [self performSelector:@selector(refresh) withObject:nil afterDelay:QLMLevelHoldInterval inModes:@[NSRunLoopCommonModes]];
    [self.system setVolumeDecibels:decibels];
}

- (double)turnKnobTo:(double)decibels {
    (void)self.window;
    [self render];
    QLMKnobControl *knob = self.skinView.knob;
    [knob moveTo:decibels];
    return knob.doubleValue;
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

#pragma mark - Drawing

// What changes only with the setup or the skin.
- (void)renderGroups {
    QLMSkinView *view = self.skinView;
    QLMMainWindowModel *model = self.model;
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
    view.status.toolTip = model.busProblem;

    if (model.applyingGroupName != nil) {
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
