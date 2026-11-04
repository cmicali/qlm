#import "QLMMainWindowController.h"

#include "QLMCommands.h"
#import "QLMFormat.h"
#import "QLMMainWindowModel.h"
#import "QLMSkinLibrary.h"
#import "QLMSkinView.h"

static NSString *const QLMMainWindowAutosaveName = @"QLMMainWindow";
// A blink's half: about two a second.
static const NSTimeInterval QLMBlinkInterval = 0.25;

@interface QLMMainWindowController ()
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMMainWindowModel *model;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, nullable) QLMSkin *skin;
@property (nonatomic, nullable) QLMSkinView *skinView;
@property (nonatomic, nullable) NSTimer *blinkTimer;
@property (nonatomic) NSTimeInterval knobTurnedAt;
@end

@implementation QLMMainWindowController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList {
    self = [super initWithWindow:nil];
    if (self) {
        _preferences = preferences;
        _monitorList = monitorList;
        _model = [[QLMMainWindowModel alloc] init];
        [self makeWindow];
    }
    return self;
}

- (void)makeWindow {
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                              | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    QLMSkin *skin = [self loadSkin:NULL];
    NSRect frame = NSMakeRect(0, 0, skin.windowSize.width, skin.windowSize.height);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:YES];
    window.title = @"qlm";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.movableByWindowBackground = YES;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.releasedWhenClosed = NO;
    // The Window menu names it itself.
    window.excludedFromWindowsMenu = YES;
    // TRAP: dump_screenshot draws a content view with no layer into an
    // unflipped context, so the flipped skin view comes out upside down.
    // So it fills an unflipped container, as QLMSkinPreview's does.
    window.contentView = [[NSView alloc] initWithFrame:frame];
    self.window = window;
    [self showSkin:skin];
    if (![window setFrameUsingName:QLMMainWindowAutosaveName]) {
        [window center];
    }
    window.frameAutosaveName = QLMMainWindowAutosaveName;
}

- (QLMSkin *)loadSkin:(NSString *_Nullable *_Nullable)refusal {
    QLMSkin *skin = [[QLMSkinLibrary standardLibrary] loadSkinNamed:self.preferences.skinName refusal:refusal];
    NSAssert(skin != nil, @"the default skin is refused");
    return skin;
}

// Replaces the skin view, and grows the window to the skin's size if it is
// smaller.
- (void)showSkin:(QLMSkin *)skin {
    NSWindow *window = self.window;
    NSView *container = window.contentView;
    [self.skinView removeFromSuperview];
    self.skin = skin;
    window.contentMinSize = skin.windowSize;
    NSSize size = container.bounds.size;
    if (size.width < skin.windowSize.width || size.height < skin.windowSize.height) {
        [window setContentSize:NSMakeSize(MAX(size.width, skin.windowSize.width), MAX(size.height, skin.windowSize.height))];
    }

    QLMSkinView *view = [[QLMSkinView alloc] initWithSkin:skin];
    view.frame = container.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
    self.skinView = view;

    view.logo = @"qlm.";
    view.tagline = @"REFERENCE CONTROL";
    view.groupsTitle = @"LISTENING SETUP";
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
    [self render];
}

- (NSString *)reloadSkin {
    NSString *refusal = nil;
    QLMSkin *skin = [self loadSkin:&refusal];
    [self showSkin:skin];
    return refusal;
}

- (BOOL)isShowing {
    return self.window.visible;
}

- (NSString *)applyError {
    return self.model.applyError;
}

- (void)showWindow:(id)sender {
    [self render];
    [super showWindow:sender];
}

- (void)showSetup:(QLMSetup *)setup fileName:(NSString *)fileName error:(NSError *)error {
    self.setup = setup;
    self.model.setupFileName = fileName;
    self.model.setupError = error.localizedDescription;
    [self refresh];
}

- (void)reloadVolumeRange {
    self.knobTurnedAt = 0;
    [self refresh];
}

- (void)refresh {
    if (self.showing) {
        [self render];
    }
}

#pragma mark - Actions

- (void)groupClicked:(QLMSkinButtonView *)button {
    [self applyGroupAtIndex:(NSUInteger)button.tag];
}

- (NSString *)clickGroupNamed:(NSString *)name {
    [self updateModel];
    NSArray<NSString *> *names = self.model.shownGroupNames;
    NSUInteger index = [names indexOfObject:name];
    if (index == NSNotFound) {
        return names.count == 0 ? [NSString stringWithFormat:@"no group buttons show: %@", self.model.groupsMessage]
                                : [NSString stringWithFormat:@"no group button reads %@. They read: %@", name,
                                                             [names componentsJoinedByString:@", "]];
    }
    if (!self.model.groupsEnabled) {
        return self.model.applying ? @"the group buttons are disabled while an apply runs"
                                   : @"the group buttons are disabled until System tracks a monitor";
    }
    [self applyGroupAtIndex:index];
    return nil;
}

// As the popover's picker: the refusal shows until the next click.
- (void)applyGroupAtIndex:(NSUInteger)index {
    [self updateModel];
    QLMSystem *system = self.system;
    NSArray<NSString *> *names = self.model.shownGroupNames;
    if (system == nil || !self.model.groupsEnabled || index >= names.count) {
        return;
    }
    QLMSetupGroup *group = self.setup.groups[index];
    self.model.applyingGroupName = group.name;
    self.model.applyError = nil;
    self.model.blinkOn = YES;
    [self.blinkTimer invalidate];
    self.blinkTimer = [NSTimer scheduledTimerWithTimeInterval:QLMBlinkInterval target:self selector:@selector(blink:)
                                                     userInfo:nil repeats:YES];
    [self refresh];
    __weak QLMMainWindowController *weakSelf = self;
    [system applyGroup:group completion:^(NSError *error) {
        QLMMainWindowController *strongSelf = weakSelf;
        [strongSelf.blinkTimer invalidate];
        strongSelf.blinkTimer = nil;
        strongSelf.model.applyingGroupName = nil;
        strongSelf.model.applyError = error.localizedDescription;
        strongSelf.model.refusedGroupName = error != nil ? group.name : nil;
        [strongSelf refresh];
    }];
}

- (void)blink:(NSTimer *)timer {
    self.model.blinkOn = !self.model.blinkOn;
    [self refresh];
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
    [self.system setVolumeDecibels:decibels];
}

- (double)turnKnobTo:(double)decibels {
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

- (void)updateModel {
    QLMMainWindowModel *model = self.model;
    model.snapshot = self.monitorList.snapshot;
    model.entries = self.monitorList.entries;
    model.lowestDecibels = self.preferences.lowestDecibels;
    model.ceilingDecibels = self.preferences.ceilingDecibels;
    NSMutableArray<NSString *> *names = nil;
    if (self.setup != nil) {
        names = [NSMutableArray array];
        for (QLMSetupGroup *group in self.setup.groups) {
            [names addObject:group.name];
        }
    }
    model.groupNames = names;
}

- (void)render {
    [self updateModel];
    QLMSkinView *view = self.skinView;
    if (view == nil) {
        return;
    }
    QLMMainWindowModel *model = self.model;

    view.status.text = model.statusText;
    view.status.lit = model.statusLit;
    view.status.toolTip = model.busProblem;
    view.status.accessibilityValue = model.busProblem ?: model.statusText;

    [view setGroupTitles:model.groupTitles prefixes:model.groupPrefixes];
    NSArray<NSString *> *names = model.shownGroupNames;
    for (NSUInteger i = 0; i < names.count && i < view.groupButtons.count; i++) {
        QLMSkinButtonView *button = view.groupButtons[i];
        BOOL selected = [model groupSelectedAtIndex:i];
        button.selected = selected;
        button.enabled = model.groupsEnabled;
        button.accessibilityLabel = names[i];
        button.accessibilityValue = @(selected);
    }
    view.groupsMessage = model.groupsMessage;

    QLMSkinDisplayView *display = view.display;
    display.caption = model.caption;
    if (!QLMKnobHolds(self.knobTurnedAt, NSProcessInfo.processInfo.systemUptime)) {
        display.level = model.levelText;
    }
    display.unit = model.unitText;
    display.output = model.outputText;
    display.max = model.maxText;
    display.disabled = model.displayDisabled;
    display.toolTip = model.applyError;
    display.accessibilityValue = model.displaySummary;

    view.muteButton.title = model.muteTitle;
    view.muteButton.selected = model.muteOn;
    view.muteButton.ledLit = model.muteOn;
    view.muteButton.enabled = model.muteEnabled;
    view.muteButton.accessibilityValue = @(model.muteOn);
    view.dimButton.title = model.dimTitle;
    view.dimButton.selected = model.dimOn;
    view.dimButton.enabled = model.dimEnabled;
    view.dimButton.accessibilityValue = @(model.dimOn);

    QLMKnobControl *knob = view.knob;
    knob.minValue = model.knobMinimum;
    knob.maxValue = model.knobMaximum;
    knob.enabled = model.knobEnabled;
    NSNumber *level = model.knobDecibels;
    if (level != nil && !QLMKnobHolds(self.knobTurnedAt, NSProcessInfo.processInfo.systemUptime)) {
        knob.doubleValue = level.doubleValue;
    }
    view.knobMin = model.knobMinText;
    view.knobMax = model.knobMaxText;
    view.knobCaption = model.knobCaption;

    view.monitorsButton.title = model.monitorsTitle;
    view.powerButton.title = model.powerTitle;
    view.powerButton.enabled = model.powerEnabled;
    view.powerButton.accessibilityLabel = model.powerWakes ? @"Wake the monitors" : @"Put the monitors in standby";
}

@end
