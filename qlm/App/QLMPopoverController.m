#import "QLMPopoverController.h"

#include "QLMReplies.h"

static const double QLMSliderMinimumDecibels = -60;
static const double QLMSliderStepDecibels = 0.5;

static BOOL QLMAnyMonitorOn(QLMSnapshot *_Nullable snapshot);

@interface QLMPopoverController ()
@property (nonatomic) QLMSystem *system;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic) NSTextField *stateLabel;
@property (nonatomic) NSSlider *volumeSlider;
@property (nonatomic) NSTextField *volumeLabel;
@property (nonatomic) NSPopUpButton *groupPicker;
@property (nonatomic) NSStackView *monitorsStack;
@property (nonatomic) NSButton *muteButton;
@property (nonatomic) NSButton *dimButton;
@property (nonatomic) NSButton *powerButton;
@property (nonatomic, nullable) QLMSnapshot *shownSnapshot;
@property (nonatomic, copy, nullable) NSString *applyingGroupName;
@property (nonatomic, copy, nullable) NSString *selectedGroupName;  // the last group applied
@property (nonatomic, copy, nullable) NSString *message;            // shown in place of the monitor count
@end

@implementation QLMPopoverController

- (instancetype)initWithSystem:(QLMSystem *)system setup:(QLMSetup *)setup {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _system = system;
        _setup = setup;
        if (setup == nil) {
            _message = @"no setup file";
        }
    }
    return self;
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
    [self.groupPicker addItemWithTitle:@"Group"];
    for (QLMSetupGroup *group in self.setup.groups) {
        [self.groupPicker addItemWithTitle:group.name];
    }
    self.groupPicker.target = self;
    self.groupPicker.action = @selector(groupChosen:);
    self.groupPicker.enabled = self.setup != nil;

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
    if (self.shownSnapshot != nil) {
        [self showSnapshot:self.shownSnapshot];
    } else {
        [self refreshGroupControls];
    }
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
    if (QLMAnyMonitorOn(self.shownSnapshot)) {
        [self.system sleep];
    } else {
        [self.system wake];
    }
}

- (void)monitorMuteClicked:(NSButton *)button {
    NSArray<QLMMonitorState *> *monitors = self.shownSnapshot.monitors;
    if (button.tag < 0 || (NSUInteger)button.tag >= monitors.count) {
        return;
    }
    QLMMonitorState *monitor = monitors[(NSUInteger)button.tag];
    [self.system setMuted:!monitor.muted forMonitorWithHardwareID:monitor.hardwareID];
}

- (void)groupChosen:(NSPopUpButton *)picker {
    NSInteger index = picker.indexOfSelectedItem - 1;
    if (self.setup == nil || index < 0 || (NSUInteger)index >= self.setup.groups.count) {
        [self selectGroupNamed:self.selectedGroupName];
        return;
    }
    QLMSetupGroup *group = self.setup.groups[(NSUInteger)index];
    self.applyingGroupName = group.name;
    self.message = nil;
    [self refreshGroupControls];
    __weak QLMPopoverController *weakSelf = self;
    [self.system applyGroup:group completion:^(NSError *error) {
        QLMPopoverController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.applyingGroupName = nil;
        if (error == nil) {
            strongSelf.selectedGroupName = group.name;
        } else {
            strongSelf.message = error.localizedDescription;
        }
        [strongSelf selectGroupNamed:strongSelf.selectedGroupName];
        [strongSelf refreshGroupControls];
    }];
}

#pragma mark - Snapshots

static BOOL QLMAnyMonitorOn(QLMSnapshot *_Nullable snapshot) {
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if (monitor.status == QLMMonitorStatusOn) {
            return YES;
        }
    }
    return NO;
}

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

static NSString *QLMModelName(QLMMonitorState *monitor) {
    // The info string reads c-1;model-8330A;ver-...; take the model.
    NSRange model = [monitor.systemInfo rangeOfString:@"model-"];
    if (model.location == NSNotFound) {
        return monitor.systemInfo ?: @"?";
    }
    NSString *rest = [monitor.systemInfo substringFromIndex:NSMaxRange(model)];
    NSRange end = [rest rangeOfString:@";"];
    return end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
}

- (void)selectGroupNamed:(nullable NSString *)name {
    NSInteger index = name != nil ? [self.groupPicker indexOfItemWithTitle:name] : -1;
    [self.groupPicker selectItemAtIndex:index >= 0 ? index : 0];
}

- (void)refreshGroupControls {
    QLMSnapshot *snapshot = self.shownSnapshot;
    BOOL applying = self.applyingGroupName != nil || snapshot.applying;
    self.groupPicker.enabled = self.setup != nil && !applying;
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
    if (!self.isViewLoaded) {
        return;
    }

    if (snapshot.volumeDecibels != nil) {
        double decibels = snapshot.volumeDecibels.doubleValue;
        self.volumeLabel.stringValue = [NSString stringWithFormat:@"%.1f dB", decibels];
        if (fabs(self.volumeSlider.doubleValue - decibels) >= QLMSliderStepDecibels) {
            self.volumeSlider.doubleValue = decibels;
        }
    }

    BOOL allMuted = snapshot.monitors.count > 0;
    for (QLMMonitorState *monitor in snapshot.monitors) {
        allMuted = allMuted && monitor.muted;
    }
    self.muteButton.state = allMuted ? NSControlStateValueOn : NSControlStateValueOff;
    self.dimButton.state = snapshot.dimmed ? NSControlStateValueOn : NSControlStateValueOff;
    self.powerButton.title = QLMAnyMonitorOn(snapshot) ? @"Sleep" : @"Wake";
    self.powerButton.enabled = snapshot.monitors.count > 0;

    if (self.applyingGroupName == nil && !snapshot.applying && snapshot.activeGroupName != nil
        && [self.groupPicker indexOfItemWithTitle:snapshot.activeGroupName] > 0) {
        self.selectedGroupName = snapshot.activeGroupName;
        [self selectGroupNamed:self.selectedGroupName];
    }
    [self refreshGroupControls];

    for (NSView *row in [self.monitorsStack.arrangedSubviews copy]) {
        [self.monitorsStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    [snapshot.monitors enumerateObjectsUsingBlock:^(QLMMonitorState *monitor, NSUInteger index, BOOL *stop) {
        NSImageView *dot = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil]];
        dot.contentTintColor = QLMDotColor(monitor);
        [dot.widthAnchor constraintEqualToConstant:10].active = YES;
        NSString *temperature = monitor.temperature == QLMMonitorValueAbsent ? @"" : [NSString stringWithFormat:@"  %ld °C", (long)monitor.temperature];
        NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"%@  %@%@", QLMModelName(monitor), monitor.serialNumber ?: @"", temperature]];
        label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        NSImage *speaker = [NSImage imageWithSystemSymbolName:monitor.muted ? @"speaker.slash.fill" : @"speaker.fill"
                                     accessibilityDescription:monitor.muted ? @"Unmute" : @"Mute"];
        NSButton *mute = [NSButton buttonWithImage:speaker target:self action:@selector(monitorMuteClicked:)];
        mute.bordered = NO;
        mute.imagePosition = NSImageOnly;
        mute.tag = (NSInteger)index;
        NSView *spacer = [[NSView alloc] init];
        [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *row = [NSStackView stackViewWithViews:@[dot, label, spacer, mute]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        [self.monitorsStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.monitorsStack.widthAnchor].active = YES;
    }];
}

@end
