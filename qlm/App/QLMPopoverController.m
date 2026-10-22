#import "QLMPopoverController.h"

static const double QLMSliderMinimumDecibels = -60;
static const double QLMSliderStepDecibels = 0.5;

static NSColor *QLMDotColor(QLMMonitorState *monitor) {
    if (monitor.missedPolls > 0) {
        return NSColor.systemRedColor;
    }
    switch (monitor.status) {
    case QLMMonitorStatusOn: return NSColor.systemGreenColor;
    case QLMMonitorStatusStandby: return NSColor.systemYellowColor;
    case QLMMonitorStatusUnknown: break;
    }
    return NSColor.systemGrayColor;
}

// One monitor's line: its status dot, its label, and its mute toggle.
@interface QLMMonitorRow : NSObject
@property (nonatomic, readonly) NSStackView *view;
@property (nonatomic, readonly) NSImageView *dot;
@property (nonatomic, readonly) NSTextField *label;
@property (nonatomic, readonly) NSButton *muteButton;
@property (nonatomic, readonly) QLMSystem *system;
@property (nonatomic, nullable) QLMMonitorState *monitor;
@end

@implementation QLMMonitorRow

- (instancetype)initWithSystem:(QLMSystem *)system {
    self = [super init];
    if (self) {
        _system = system;
        _dot = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil]];
        [_dot.widthAnchor constraintEqualToConstant:10].active = YES;
        _label = [NSTextField labelWithString:@""];
        _label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        _muteButton = [NSButton buttonWithImage:[[NSImage alloc] init] target:self action:@selector(muteClicked:)];
        _muteButton.bordered = NO;
        _muteButton.imagePosition = NSImageOnly;
        NSView *spacer = [[NSView alloc] init];
        [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        _view = [NSStackView stackViewWithViews:@[_dot, _label, spacer, _muteButton]];
        _view.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    }
    return self;
}

- (void)setMonitor:(QLMMonitorState *)monitor {
    BOOL mutedChanged = _monitor == nil || _monitor.muted != monitor.muted;
    _monitor = monitor;
    self.dot.contentTintColor = QLMDotColor(monitor);
    NSString *temperature = monitor.temperature == QLMMonitorValueAbsent ? @"" : [NSString stringWithFormat:@"  %ld °C", (long)monitor.temperature];
    self.label.stringValue = [NSString stringWithFormat:@"%@  %@%@", monitor.model ?: @"?", monitor.serialNumber ?: @"", temperature];
    if (mutedChanged) {
        self.muteButton.image = [NSImage imageWithSystemSymbolName:monitor.muted ? @"speaker.slash.fill" : @"speaker.fill"
                                          accessibilityDescription:monitor.muted ? @"Unmute" : @"Mute"];
    }
}

- (void)muteClicked:(NSButton *)button {
    QLMMonitorState *monitor = self.monitor;
    if (monitor != nil) {
        [self.system setMuted:!monitor.muted forMonitorWithHardwareID:monitor.hardwareID];
    }
}

@end

@interface QLMPopoverController ()
@property (nonatomic) QLMSystem *system;
@property (nonatomic) NSTextField *stateLabel;
@property (nonatomic) NSSlider *volumeSlider;
@property (nonatomic) NSTextField *volumeLabel;
@property (nonatomic) NSPopUpButton *groupPicker;
@property (nonatomic) NSStackView *monitorsStack;
@property (nonatomic) NSMutableDictionary<NSData *, QLMMonitorRow *> *rows;  // by hardware ID
@property (nonatomic) NSButton *muteButton;
@property (nonatomic) NSButton *dimButton;
@property (nonatomic) NSButton *powerButton;
@property (nonatomic, nullable) QLMSnapshot *shownSnapshot;
// The snapshot says an apply is running, not which group.
@property (nonatomic, copy, nullable) NSString *applyingGroupName;
@property (nonatomic, copy, nullable) NSString *message;  // shown in place of the monitor count
@end

@implementation QLMPopoverController

- (instancetype)initWithSystem:(QLMSystem *)system {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _system = system;
        _rows = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setSetup:(QLMSetup *)setup {
    _setup = setup;
    self.message = setup == nil ? @"no setup file" : nil;
    if (self.isViewLoaded) {
        [self reloadGroups];
        [self refresh];
    }
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 10)];

    NSTextField *title = [NSTextField labelWithString:@"qlm"];
    title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
    [title setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    // Wraps, so a refusal reads in full.
    self.stateLabel = [NSTextField wrappingLabelWithString:@"starting"];
    self.stateLabel.textColor = NSColor.secondaryLabelColor;
    self.stateLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.stateLabel.preferredMaxLayoutWidth = 250;
    [self.stateLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *header = [NSStackView stackViewWithViews:@[title, self.stateLabel]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeFirstBaseline;

    // Volume, in 0.5 dB steps, up to the user's ceiling.
    self.volumeSlider = [NSSlider sliderWithValue:QLMSliderMinimumDecibels minValue:QLMSliderMinimumDecibels
                                         maxValue:self.system.settings.ceilingDecibels target:self action:@selector(volumeChanged:)];
    self.volumeSlider.continuous = YES;
    self.volumeLabel = [NSTextField labelWithString:@"—"];
    self.volumeLabel.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    self.volumeLabel.alignment = NSTextAlignmentRight;
    [self.volumeLabel.widthAnchor constraintEqualToConstant:64].active = YES;
    NSStackView *volume = [NSStackView stackViewWithViews:@[self.volumeSlider, self.volumeLabel]];
    volume.orientation = NSUserInterfaceLayoutOrientationHorizontal;

    self.groupPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.groupPicker.target = self;
    self.groupPicker.action = @selector(groupChosen:);

    self.muteButton = [NSButton buttonWithTitle:@"Mute" target:self action:@selector(muteClicked:)];
    self.muteButton.buttonType = NSButtonTypePushOnPushOff;
    self.dimButton = [NSButton buttonWithTitle:@"Dim" target:self action:@selector(dimClicked:)];
    self.dimButton.buttonType = NSButtonTypePushOnPushOff;
    self.powerButton = [NSButton buttonWithTitle:@"Wake" target:self action:@selector(powerClicked:)];
    self.powerButton.enabled = NO;
    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:NSApp action:@selector(terminate:)];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.muteButton, self.dimButton, self.powerButton, spacer, quit]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;

    self.monitorsStack = [NSStackView stackViewWithViews:@[]];
    self.monitorsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.monitorsStack.alignment = NSLayoutAttributeLeading;
    self.monitorsStack.spacing = 4;

    NSStackView *stack = [NSStackView stackViewWithViews:@[header, volume, self.groupPicker, self.monitorsStack, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [view.widthAnchor constraintEqualToConstant:320],
        [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [volume.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [self.groupPicker.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [self.monitorsStack.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
    ]];
    self.view = view;
    [self reloadGroups];
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self render];
}

#pragma mark - Actions

- (void)volumeChanged:(NSSlider *)slider {
    double decibels = round(slider.doubleValue / QLMSliderStepDecibels) * QLMSliderStepDecibels;
    self.volumeLabel.stringValue = [NSString stringWithFormat:@"%.1f dB", decibels];
    [self.system setVolumeDecibels:decibels];
}

- (void)muteClicked:(NSButton *)button {
    [self.system setAllMuted:button.state == NSControlStateValueOn];
}

- (void)dimClicked:(NSButton *)button {
    [self.system setDimmed:button.state == NSControlStateValueOn];
}

- (void)powerClicked:(NSButton *)button {
    if (self.shownSnapshot.anyOn) {
        [self.system sleep];
    } else {
        [self.system wake];
    }
}

- (void)groupChosen:(NSPopUpButton *)picker {
    NSInteger index = picker.indexOfSelectedItem - 1;
    if (self.setup == nil || index < 0 || (NSUInteger)index >= self.setup.groups.count) {
        [self selectGroupNamed:self.shownSnapshot.activeGroupName];
        return;
    }
    QLMSetupGroup *group = self.setup.groups[(NSUInteger)index];
    self.applyingGroupName = group.name;
    self.message = nil;
    [self refreshGroupControls];
    __weak QLMPopoverController *weakSelf = self;
    [self.system applyGroup:group completion:^(NSError *error) {
        QLMPopoverController *strongSelf = weakSelf;
        strongSelf.applyingGroupName = nil;
        strongSelf.message = error.localizedDescription;
        [strongSelf refresh];
    }];
}

#pragma mark - Snapshots

- (void)reloadGroups {
    [self.groupPicker removeAllItems];
    [self.groupPicker addItemWithTitle:@"Group"];
    for (QLMSetupGroup *group in self.setup.groups) {
        [self.groupPicker addItemWithTitle:group.name];
    }
    [self refreshGroupControls];
}

- (void)selectGroupNamed:(nullable NSString *)name {
    NSInteger index = name != nil ? [self.groupPicker indexOfItemWithTitle:name] : -1;
    [self.groupPicker selectItemAtIndex:index >= 0 ? index : 0];
}

- (void)refreshGroupControls {
    QLMSnapshot *snapshot = self.shownSnapshot;
    BOOL applying = self.applyingGroupName != nil || snapshot.applying;
    self.groupPicker.enabled = self.setup != nil && !applying;
    if (!applying) {
        [self selectGroupNamed:snapshot.activeGroupName];
    }
    if (self.applyingGroupName != nil) {
        self.stateLabel.stringValue = [NSString stringWithFormat:@"applying %@", self.applyingGroupName];
    } else if (self.message != nil) {
        self.stateLabel.stringValue = self.message;
    } else if (snapshot == nil || !snapshot.running) {
        self.stateLabel.stringValue = snapshot == nil ? @"starting" : @"stopped";
    } else if (snapshot.monitors.count == 0) {
        self.stateLabel.stringValue = @"looking for monitors";
    } else {
        self.stateLabel.stringValue = [NSString stringWithFormat:@"%lu monitors on the fake bus", (unsigned long)snapshot.monitors.count];
    }
}

- (void)showSnapshot:(QLMSnapshot *)snapshot {
    self.shownSnapshot = snapshot;
    [self refresh];
}

// Draws only while the popover is open. viewWillAppear draws the rest.
- (void)refresh {
    if (self.isViewLoaded && self.view.window != nil) {
        [self render];
    }
}

- (void)render {
    QLMSnapshot *snapshot = self.shownSnapshot;
    if (snapshot.volumeDecibels != nil) {
        double decibels = snapshot.volumeDecibels.doubleValue;
        self.volumeLabel.stringValue = [NSString stringWithFormat:@"%.1f dB", decibels];
        if (fabs(self.volumeSlider.doubleValue - decibels) >= QLMSliderStepDecibels) {
            self.volumeSlider.doubleValue = decibels;
        }
    }
    self.muteButton.state = snapshot.allMuted ? NSControlStateValueOn : NSControlStateValueOff;
    self.dimButton.state = snapshot.dimmed ? NSControlStateValueOn : NSControlStateValueOff;
    self.powerButton.title = snapshot.anyOn ? @"Sleep" : @"Wake";
    self.powerButton.enabled = snapshot.monitors.count > 0;
    [self refreshGroupControls];
    [self renderMonitors:snapshot.monitors ?: @[]];
}

- (void)renderMonitors:(NSArray<QLMMonitorState *> *)monitors {
    NSMutableArray<NSView *> *order = [NSMutableArray arrayWithCapacity:monitors.count];
    NSMutableSet<NSData *> *present = [NSMutableSet setWithCapacity:monitors.count];
    for (QLMMonitorState *monitor in monitors) {
        QLMMonitorRow *row = self.rows[monitor.hardwareID];
        if (row == nil) {
            row = [[QLMMonitorRow alloc] initWithSystem:self.system];
            self.rows[monitor.hardwareID] = row;
        }
        row.monitor = monitor;
        [order addObject:row.view];
        [present addObject:monitor.hardwareID];
    }
    for (NSData *hardwareID in self.rows.allKeys) {
        if (![present containsObject:hardwareID]) {
            [self.rows removeObjectForKey:hardwareID];
        }
    }
    if ([self.monitorsStack.arrangedSubviews isEqualToArray:order]) {
        return;
    }
    for (NSView *view in [self.monitorsStack.arrangedSubviews copy]) {
        [self.monitorsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSView *view in order) {
        [self.monitorsStack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:self.monitorsStack.widthAnchor].active = YES;
    }
}

@end
