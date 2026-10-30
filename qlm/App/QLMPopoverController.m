#import "QLMPopoverController.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMBannerView.h"
#import "QLMFormat.h"
#import "QLMHostCheck.h"
#import "QLMViews.h"

static const CGFloat QLMPopoverWidth = 320;
static const CGFloat QLMPopoverInset = 14;
// After the user moves the slider, snapshots leave it alone this long, so a
// snapshot from before the move cannot pull it back mid-drag.
static const NSTimeInterval QLMSliderHoldInterval = 0.5;

static NSTextField *QLMSmallLabel(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

// GLM 5, when it runs: an app whose executable QLMHostCheck counts as GLM.
static NSRunningApplication *_Nullable QLMRunningGLM(void) {
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *path = app.executableURL.path;
        if (path != nil && QLMHostCheckIsGLMExecutable(path)) {
            return app;
        }
    }
    return nil;
}

static NSView *QLMSpacer(void) {
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spacer;
}

// One monitor's line: its status dot, model, serial, state, and mute toggle.
@interface QLMMonitorRow : NSObject
@property (nonatomic, readonly) NSStackView *view;
@property (nonatomic, readonly) NSImageView *dot;
@property (nonatomic, readonly) NSTextField *model;
@property (nonatomic, readonly) NSTextField *serial;
@property (nonatomic, readonly) NSTextField *detail;
@property (nonatomic, readonly) NSButton *muteButton;
@property (nonatomic, weak) QLMPopoverController *owner;
@property (nonatomic, nullable) QLMMonitorEntry *entry;
@end

@interface QLMPopoverController ()
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMBannerView *banner;
@property (nonatomic) QLMBannerView *setupBanner;
@property (nonatomic) NSTextField *deviceLabel;
@property (nonatomic) NSTextField *messageLabel;
@property (nonatomic) NSSlider *volumeSlider;
@property (nonatomic) NSTextField *volumeLabel;
@property (nonatomic) NSTextField *ceilingLabel;
@property (nonatomic) NSButton *muteButton;
@property (nonatomic) NSButton *dimButton;
@property (nonatomic) NSButton *powerButton;
@property (nonatomic) NSButton *fakeBusButton;
@property (nonatomic) NSPopUpButton *groupPicker;
@property (nonatomic) NSTextField *summaryLabel;
@property (nonatomic) NSStackView *monitorsStack;
@property (nonatomic) NSMutableArray<QLMMonitorRow *> *rows;  // one per entry, as the list only appends
@property (nonatomic) NSTimeInterval sliderMovedAt;
@property (nonatomic) BOOL askedGLMToQuit;  // until GLM lets go of the adapter
// GLM holds the adapter, as of checkedError. GLM starts and quits rarely, so
// the app list is scanned only when System's error changes.
@property (nonatomic) BOOL glmHolds;
@property (nonatomic, nullable) NSError *checkedError;
// The snapshot says an apply is running, not which group.
@property (nonatomic, copy, nullable) NSString *applyingGroupName;
@property (nonatomic, copy, nullable) NSString *message;  // the last apply's error
- (void)monitorRowMuteClicked:(QLMMonitorRow *)row;
@end

@implementation QLMMonitorRow

- (instancetype)initWithOwner:(QLMPopoverController *)owner {
    self = [super init];
    if (self) {
        _owner = owner;
        _dot = QLMDotView();
        [_dot.widthAnchor constraintEqualToConstant:10].active = YES;
        _model = [NSTextField labelWithString:@""];
        [_model.widthAnchor constraintEqualToConstant:52].active = YES;
        _serial = QLMSmallLabel(@"");
        _serial.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        _serial.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_serial setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        _detail = QLMSmallLabel(@"");
        _detail.alignment = NSTextAlignmentRight;
        _muteButton = [NSButton buttonWithImage:[[NSImage alloc] init] target:self action:@selector(muteClicked:)];
        _muteButton.bordered = NO;
        _muteButton.imagePosition = NSImageOnly;
        [_muteButton.widthAnchor constraintEqualToConstant:18].active = YES;
        _view = [NSStackView stackViewWithViews:@[_dot, _model, _serial, QLMSpacer(), _detail, _muteButton]];
        _view.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _view.spacing = 6;
    }
    return self;
}

- (void)setEntry:(QLMMonitorEntry *)entry {
    BOOL mutedChanged = _entry == nil || _entry.state.muted != entry.state.muted;
    _entry = entry;
    QLMMonitorState *monitor = entry.state;
    self.dot.contentTintColor = QLMPresenceColor(entry.presence);
    self.dot.toolTip = QLMPresenceName(entry.presence);
    self.model.stringValue = monitor.model ?: @"?";
    self.serial.stringValue = monitor.serialNumber ?: @"";
    self.detail.stringValue = entry.presence == QLMMonitorPresenceOnline ? QLMTemperatureText(monitor.temperature) : QLMEntryStatusText(entry);
    self.muteButton.enabled = entry.tracked;
    if (mutedChanged) {
        self.muteButton.image = [NSImage imageWithSystemSymbolName:monitor.muted ? @"speaker.slash.fill" : @"speaker.fill"
                                          accessibilityDescription:monitor.muted ? @"Unmute" : @"Mute"];
        self.muteButton.contentTintColor = monitor.muted ? NSColor.systemRedColor : nil;
    }
}

- (void)muteClicked:(NSButton *)button {
    [self.owner monitorRowMuteClicked:self];
}

@end

@implementation QLMPopoverController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _preferences = preferences;
        _monitorList = monitorList;
        _rows = [NSMutableArray array];
    }
    return self;
}

- (void)setShowsFakeBus:(BOOL)showsFakeBus {
    _showsFakeBus = showsFakeBus;
    self.fakeBusButton.hidden = !showsFakeBus;
}

- (void)setChangedSetupName:(NSString *)changedSetupName {
    _changedSetupName = [changedSetupName copy];
    [self refresh];
}

- (void)setSetup:(QLMSetup *)setup {
    _setup = setup;
    if (self.isViewLoaded) {
        [self reloadGroups];
        [self refresh];
    }
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, QLMPopoverWidth, 10)];
    CGFloat contentWidth = QLMPopoverWidth - 2 * QLMPopoverInset;

    self.banner = [[QLMBannerView alloc] initWithTextWidth:contentWidth - 50 style:QLMBannerStyleWarning];
    self.banner.actionButton.target = self;
    self.banner.actionButton.action = @selector(quitGLMClicked:);
    self.setupBanner = [[QLMBannerView alloc] initWithTextWidth:contentWidth - 50 style:QLMBannerStyleNotice];
    self.setupBanner.actionButton.title = @"Read Again";
    self.setupBanner.actionButton.target = self;
    self.setupBanner.actionButton.action = @selector(readSetupAgainClicked:);
    self.setupBanner.actionButton.hidden = NO;

    NSTextField *title = [NSTextField labelWithString:@"qlm"];
    title.font = [NSFont systemFontOfSize:NSFont.systemFontSize + 1 weight:NSFontWeightSemibold];
    [title setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.deviceLabel = QLMSmallLabel(@"");
    self.deviceLabel.alignment = NSTextAlignmentRight;
    self.deviceLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.deviceLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *header = [NSStackView stackViewWithViews:@[title, QLMSpacer(), self.deviceLabel]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeFirstBaseline;

    // Wraps, so a refusal reads in full.
    self.messageLabel = QLMNoteLabel(@"", contentWidth);
    self.messageLabel.selectable = YES;
    self.messageLabel.hidden = YES;

    NSImageView *speaker = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill"
                                                                       accessibilityDescription:@"Volume"]];
    speaker.contentTintColor = NSColor.secondaryLabelColor;
    [speaker setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    // Volume, in 0.5 dB steps, up to the ceiling.
    self.volumeSlider = [NSSlider sliderWithValue:self.preferences.lowestDecibels minValue:self.preferences.lowestDecibels
                                         maxValue:self.preferences.ceilingDecibels target:self action:@selector(volumeChanged:)];
    self.volumeSlider.continuous = YES;
    self.volumeSlider.enabled = NO;
    self.volumeLabel = [NSTextField labelWithString:QLMEmDash];
    self.volumeLabel.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightMedium];
    self.volumeLabel.alignment = NSTextAlignmentRight;
    [self.volumeLabel.widthAnchor constraintEqualToConstant:72].active = YES;
    NSStackView *volume = [NSStackView stackViewWithViews:@[speaker, self.volumeSlider, self.volumeLabel]];
    volume.orientation = NSUserInterfaceLayoutOrientationHorizontal;

    self.ceilingLabel = QLMNoteLabel(@"", contentWidth);
    self.ceilingLabel.toolTip = @"No volume frame goes above the ceiling. Change it in Settings.";

    self.muteButton = [self toggleWithTitle:@"Mute" symbol:@"speaker.slash.fill" action:@selector(muteClicked:)];
    self.dimButton = [self toggleWithTitle:@"Dim" symbol:@"speaker.wave.1.fill" action:@selector(dimClicked:)];
    self.dimButton.toolTip = [NSString stringWithFormat:@"Lowers the volume by %.0f dB.", QLMDimDecibels];
    self.powerButton = [NSButton buttonWithTitle:@"Standby" image:[NSImage imageWithSystemSymbolName:@"power" accessibilityDescription:nil]
                                          target:self action:@selector(powerClicked:)];
    self.powerButton.enabled = NO;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.muteButton, self.dimButton, self.powerButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.distribution = NSStackViewDistributionFillEqually;

    NSTextField *groupTitle = [NSTextField labelWithString:@"Group"];
    [groupTitle setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.groupPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.groupPicker.target = self;
    self.groupPicker.action = @selector(groupChosen:);
    NSStackView *group = [NSStackView stackViewWithViews:@[groupTitle, self.groupPicker]];
    group.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    group.alignment = NSLayoutAttributeFirstBaseline;

    NSTextField *monitorsTitle = [NSTextField labelWithString:@"Monitors"];
    monitorsTitle.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold];
    monitorsTitle.textColor = NSColor.secondaryLabelColor;
    self.summaryLabel = QLMSmallLabel(@"");
    NSStackView *monitorsHeader = [NSStackView stackViewWithViews:@[monitorsTitle, QLMSpacer(), self.summaryLabel]];
    monitorsHeader.orientation = NSUserInterfaceLayoutOrientationHorizontal;

    self.monitorsStack = [NSStackView stackViewWithViews:@[]];
    self.monitorsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.monitorsStack.alignment = NSLayoutAttributeLeading;
    self.monitorsStack.spacing = 5;

    NSButton *monitorsButton = QLMSmallButton(@"Monitors…", self, @selector(showMonitorsClicked:));
    NSButton *settingsButton = QLMSmallButton(@"Settings…", self, @selector(showSettingsClicked:));
    self.fakeBusButton = QLMSmallButton(@"Fake Bus…", self, @selector(showFakeBusClicked:));
    self.fakeBusButton.hidden = !self.showsFakeBus;
    NSButton *quit = QLMSmallButton(@"Quit", NSApp, @selector(terminate:));
    NSStackView *footer = [NSStackView stackViewWithViews:@[monitorsButton, settingsButton, self.fakeBusButton, QLMSpacer(), quit]];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.spacing = 6;

    NSArray<NSView *> *fullWidth = @[
        self.banner, self.setupBanner, header, self.messageLabel, volume, self.ceilingLabel, buttons, group,
        [self separator], monitorsHeader, self.monitorsStack, [self separator], footer,
    ];
    NSStackView *stack = [NSStackView stackViewWithViews:fullWidth];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    [stack setCustomSpacing:2 afterView:volume];
    [stack setCustomSpacing:6 afterView:monitorsHeader];
    stack.edgeInsets = NSEdgeInsetsMake(QLMPopoverInset, QLMPopoverInset, QLMPopoverInset - 2, QLMPopoverInset);
    [view addSubview:stack];
    QLMPinToEdges(stack, view);
    [view.widthAnchor constraintEqualToConstant:QLMPopoverWidth].active = YES;
    for (NSView *row in fullWidth) {
        [row.widthAnchor constraintEqualToConstant:contentWidth].active = YES;
    }
    self.view = view;
    [self reloadGroups];
}

- (NSButton *)toggleWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title image:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]
                                          target:self action:action];
    button.buttonType = NSButtonTypePushOnPushOff;
    return button;
}

- (NSBox *)separator {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    return box;
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self render];
}

- (void)reloadVolumeRange {
    if (!self.isViewLoaded) {
        return;
    }
    self.volumeSlider.minValue = self.preferences.lowestDecibels;
    self.volumeSlider.maxValue = self.preferences.ceilingDecibels;
    self.sliderMovedAt = 0;
    [self refresh];
}

#pragma mark - Actions

- (void)volumeChanged:(NSSlider *)slider {
    double decibels = QLMNearestStepDecibels(slider.doubleValue);
    self.sliderMovedAt = NSProcessInfo.processInfo.systemUptime;
    self.volumeLabel.stringValue = QLMDecibelsText(decibels);
    [self.system setVolumeDecibels:decibels];
}

- (void)muteClicked:(NSButton *)button {
    [self.system setAllMuted:button.state == NSControlStateValueOn];
}

- (void)dimClicked:(NSButton *)button {
    [self.system setDimmed:button.state == NSControlStateValueOn];
}

- (void)powerClicked:(NSButton *)button {
    if (self.monitorList.snapshot.anyOn) {
        [self.system sleep];
    } else {
        [self.system wake];
    }
}

- (void)monitorRowMuteClicked:(QLMMonitorRow *)row {
    QLMMonitorEntry *entry = row.entry;
    if (entry.tracked) {
        [self.system setMuted:!entry.state.muted forMonitorWithHardwareID:entry.state.hardwareID];
    }
}

- (void)groupChosen:(NSPopUpButton *)picker {
    NSInteger index = picker.indexOfSelectedItem - 1;
    QLMSystem *system = self.system;
    if (system == nil || index < 0 || (NSUInteger)index >= self.setup.groups.count) {
        [self selectGroupNamed:self.monitorList.snapshot.activeGroupName];
        return;
    }
    QLMSetupGroup *group = self.setup.groups[(NSUInteger)index];
    self.applyingGroupName = group.name;
    self.message = nil;
    [self refresh];
    __weak QLMPopoverController *weakSelf = self;
    [system applyGroup:group completion:^(NSError *error) {
        QLMPopoverController *strongSelf = weakSelf;
        strongSelf.applyingGroupName = nil;
        strongSelf.message = error.localizedDescription;
        [strongSelf refresh];
    }];
}

// Asks politely, as the Dock's Quit does. GLM may ask to save first, and it
// is never forced. The adapter opens on its own once GLM lets go.
- (void)quitGLMClicked:(id)sender {
    self.askedGLMToQuit = [[self runningGLM] terminate];
    [self refresh];
}

- (void)readSetupAgainClicked:(id)sender {
    [self.delegate popoverControllerReadSetupAgain:self];
}

// A method, so a check can stand in for GLM.
- (nullable NSRunningApplication *)runningGLM {
    return QLMRunningGLM();
}

- (void)showMonitorsClicked:(id)sender {
    [self.delegate popoverControllerShowMonitors:self];
}

- (void)showSettingsClicked:(id)sender {
    [self.delegate popoverControllerShowSettings:self];
}

- (void)showFakeBusClicked:(id)sender {
    [self.delegate popoverControllerShowFakeBus:self];
}

#pragma mark - Snapshots

- (void)reloadGroups {
    [self.groupPicker removeAllItems];
    [self.groupPicker addItemWithTitle:self.setup == nil ? @"No setup file" : @"Choose a group"];
    for (QLMSetupGroup *group in self.setup.groups) {
        [self.groupPicker addItemWithTitle:group.name];
    }
    [self selectGroupNamed:self.monitorList.snapshot.activeGroupName];
}

- (void)selectGroupNamed:(nullable NSString *)name {
    NSInteger index = name != nil ? [self.groupPicker indexOfItemWithTitle:name] : -1;
    [self.groupPicker selectItemAtIndex:index >= 0 ? index : 0];
}

// viewWillAppear draws on opening.
- (void)refresh {
    if (self.isViewLoaded && self.view.window.visible) {
        [self render];
    }
}

- (void)render {
    QLMSnapshot *snapshot = self.monitorList.snapshot;
    [self renderBanner:snapshot.adapterError];
    NSString *changed = self.changedSetupName;
    [self.setupBanner showTitle:changed == nil ? nil : [NSString stringWithFormat:@"GLM saved %@", changed]
                         detail:@"Read it again for its new groups."];
    self.deviceLabel.stringValue = snapshot.adapter.device ?: @"";
    self.deviceLabel.toolTip = snapshot.adapter.systemInfo;
    [self renderVolume:snapshot];

    BOOL haveMonitors = snapshot.running && snapshot.monitors.count > 0;
    self.muteButton.state = snapshot.allMuted ? NSControlStateValueOn : NSControlStateValueOff;
    self.muteButton.enabled = haveMonitors;
    self.dimButton.state = snapshot.dimmed ? NSControlStateValueOn : NSControlStateValueOff;
    self.dimButton.enabled = snapshot.running;
    self.powerButton.title = snapshot.anyOn ? @"Standby" : @"Wake";
    self.powerButton.enabled = haveMonitors;

    BOOL applying = self.applyingGroupName != nil || snapshot.applying;
    self.groupPicker.enabled = self.setup != nil && haveMonitors && !applying;
    if (!applying) {
        [self selectGroupNamed:snapshot.activeGroupName];
    }
    NSString *message = self.message;
    if (self.applyingGroupName != nil) {
        message = [NSString stringWithFormat:@"Applying %@…", self.applyingGroupName];
    }
    self.messageLabel.stringValue = message ?: @"";
    self.messageLabel.hidden = message == nil;

    [self renderMonitors:self.monitorList.entries snapshot:snapshot];
}

- (void)renderBanner:(nullable NSError *)error {
    [self.banner showError:error];
    if (error != self.checkedError) {
        self.checkedError = error;
        self.glmHolds = QLMAdapterErrorIsBusy(error) && [self runningGLM] != nil;
    }
    if (!self.glmHolds) {
        self.askedGLMToQuit = NO;
    }
    NSButton *quit = self.banner.actionButton;
    quit.hidden = !self.glmHolds;
    quit.enabled = !self.askedGLMToQuit;
    quit.title = self.askedGLMToQuit ? @"Asked GLM to Quit" : @"Quit GLM";
}

- (void)renderVolume:(nullable QLMSnapshot *)snapshot {
    double ceiling = self.preferences.ceilingDecibels;
    NSString *ceilingText = [NSString stringWithFormat:@"Ceiling %@", QLMDecibelsText(ceiling)];
    NSNumber *volume = snapshot.volumeDecibels;
    self.volumeSlider.enabled = snapshot.running;
    if (volume == nil) {
        self.volumeLabel.stringValue = QLMEmDash;
        self.ceilingLabel.stringValue = ceilingText;
        return;
    }
    double decibels = volume.doubleValue;
    double sent = [self.preferences cappedDecibels:decibels];
    self.volumeLabel.stringValue = QLMDecibelsText(sent);
    BOOL held = NSProcessInfo.processInfo.systemUptime - self.sliderMovedAt < QLMSliderHoldInterval;
    if (!held) {
        self.volumeSlider.doubleValue = fmax(self.volumeSlider.minValue, sent);
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (decibels > ceiling) {
        [parts addObject:[NSString stringWithFormat:@"Capped at the %@ ceiling", QLMDecibelsText(ceiling)]];
    } else {
        [parts addObject:ceilingText];
    }
    if (snapshot.dimmed) {
        [parts addObject:[NSString stringWithFormat:@"dimmed to %@", QLMDecibelsText(snapshot.handBack.volumeDecibels.doubleValue)]];
    }
    if (snapshot.allMuted) {
        [parts addObject:@"muted"];
    }
    self.ceilingLabel.stringValue = [parts componentsJoinedByString:@"\u00A0· "];
    self.ceilingLabel.textColor = decibels > ceiling ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
}

- (void)renderMonitors:(NSArray<QLMMonitorEntry *> *)monitors snapshot:(nullable QLMSnapshot *)snapshot {
    NSUInteger counts[4] = {0};
    for (NSUInteger i = 0; i < monitors.count; i++) {
        if (i == self.rows.count) {
            QLMMonitorRow *row = [[QLMMonitorRow alloc] initWithOwner:self];
            [self.rows addObject:row];
            [self.monitorsStack addArrangedSubview:row.view];
            [row.view.widthAnchor constraintEqualToAnchor:self.monitorsStack.widthAnchor].active = YES;
        }
        self.rows[i].entry = monitors[i];
        counts[monitors[i].presence] += 1;
    }

    NSMutableArray<NSString *> *summary = [NSMutableArray array];
    const QLMMonitorPresence shown[] = {QLMMonitorPresenceOnline, QLMMonitorPresenceStandby, QLMMonitorPresenceOffline,
                                        QLMMonitorPresenceIdentifying};
    for (size_t i = 0; i < sizeof shown / sizeof shown[0]; i++) {
        if (counts[shown[i]] > 0) {
            [summary addObject:[NSString stringWithFormat:@"%lu %@", (unsigned long)counts[shown[i]],
                                                          QLMPresenceName(shown[i]).lowercaseString]];
        }
    }
    if (monitors.count == 0) {
        [summary addObject:snapshot == nil ? @"Starting" : snapshot.running ? @"Looking for monitors" : @"Stopped"];
    }
    self.summaryLabel.stringValue = [summary componentsJoinedByString:@"\u00A0· "];
}

@end
