#import "QLMPopoverController.h"

#include "QLMReplies.h"

static const double QLMSliderMinimumDecibels = -60;
static const double QLMSliderStepDecibels = 0.5;

@interface QLMPopoverController ()
@property (nonatomic) QLMSystem *system;
@property (nonatomic) NSTextField *stateLabel;
@property (nonatomic) NSSlider *volumeSlider;
@property (nonatomic) NSTextField *volumeLabel;
@property (nonatomic) NSStackView *monitorsStack;
@end

@implementation QLMPopoverController

- (instancetype)initWithSystem:(QLMSystem *)system {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _system = system;
    }
    return self;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 10)];

    NSTextField *title = [NSTextField labelWithString:@"qlm"];
    title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
    self.stateLabel = [NSTextField labelWithString:@"starting"];
    self.stateLabel.textColor = NSColor.secondaryLabelColor;
    self.stateLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
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

    // Mute and dim arrive with Phase 2 of the plan.
    NSButton *mute = [NSButton buttonWithTitle:@"Mute" target:nil action:NULL];
    NSButton *dim = [NSButton buttonWithTitle:@"Dim" target:nil action:NULL];
    mute.enabled = NO;
    dim.enabled = NO;
    mute.toolTip = @"Phase 2";
    dim.toolTip = @"Phase 2";
    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:NSApp action:@selector(terminate:)];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[mute, dim, spacer, quit]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;

    self.monitorsStack = [NSStackView stackViewWithViews:@[]];
    self.monitorsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.monitorsStack.alignment = NSLayoutAttributeLeading;
    self.monitorsStack.spacing = 4;

    NSStackView *stack = [NSStackView stackViewWithViews:@[header, volume, self.monitorsStack, buttons]];
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
        [buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
    ]];
    self.view = view;
}

- (void)volumeChanged:(NSSlider *)slider {
    double decibels = round(slider.doubleValue / QLMSliderStepDecibels) * QLMSliderStepDecibels;
    self.volumeLabel.stringValue = [NSString stringWithFormat:@"%.1f dB", decibels];
    [self.system setVolumeDecibels:decibels];
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

- (void)showSnapshot:(QLMSnapshot *)snapshot {
    if (!snapshot.running) {
        self.stateLabel.stringValue = @"stopped";
    } else if (snapshot.monitors.count == 0) {
        self.stateLabel.stringValue = @"looking for monitors";
    } else {
        self.stateLabel.stringValue = [NSString stringWithFormat:@"%lu monitors on the fake bus", (unsigned long)snapshot.monitors.count];
    }

    if (snapshot.volumeDecibels != nil) {
        double decibels = snapshot.volumeDecibels.doubleValue;
        self.volumeLabel.stringValue = [NSString stringWithFormat:@"%.1f dB", decibels];
        if (fabs(self.volumeSlider.doubleValue - decibels) >= QLMSliderStepDecibels) {
            self.volumeSlider.doubleValue = decibels;
        }
    }

    for (NSView *row in [self.monitorsStack.arrangedSubviews copy]) {
        [self.monitorsStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    for (QLMMonitorState *monitor in snapshot.monitors) {
        NSImageView *dot = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil]];
        dot.contentTintColor = QLMDotColor(monitor);
        [dot.widthAnchor constraintEqualToConstant:10].active = YES;
        NSString *temperature = monitor.temperature == QLMMonitorValueAbsent ? @"" : [NSString stringWithFormat:@"  %ld °C", (long)monitor.temperature];
        NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"%@  %@%@", QLMModelName(monitor), monitor.serialNumber ?: @"", temperature]];
        label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        NSStackView *row = [NSStackView stackViewWithViews:@[dot, label]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        [self.monitorsStack addArrangedSubview:row];
    }
}

@end
