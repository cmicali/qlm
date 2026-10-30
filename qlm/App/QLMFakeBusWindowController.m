#import "QLMFakeBusWindowController.h"

#include <math.h>

#import "QLMFormat.h"

// The shape of QLMHostCheck's description, so the banner reads as it will.
static NSString *const QLMFakeBusyReason = @"GLM is running (pid 4242, /Applications/GLMv5.app/Contents/MacOS/GLMv5). Quit GLM first.";
static const NSInteger QLMKnobBottomTenths = -1004;

// One simulated monitor's controls.
@interface QLMFakeMonitorRow : NSObject
@property (nonatomic, readonly) QLMFakeMonitor *monitor;
@property (nonatomic, readonly) NSButton *onCheckbox;
@property (nonatomic, readonly) NSButton *presentCheckbox;
@property (nonatomic, readonly) NSStepper *temperatureStepper;
@property (nonatomic, readonly) NSTextField *temperatureLabel;
@property (nonatomic, readonly) NSArray<NSView *> *views;
@end

@interface QLMFakeBusWindowController ()
@property (nonatomic) NSButton *knobCheckbox;
@property (nonatomic) NSSlider *knobSlider;
@property (nonatomic) NSTextField *knobLabel;
@property (nonatomic) NSButton *busyCheckbox;
@property (nonatomic) NSButton *unpluggedCheckbox;
@property (nonatomic) NSGridView *monitorsGrid;
@property (nonatomic, copy) NSArray<QLMFakeMonitorRow *> *rows;
- (void)monitorOnClicked:(NSButton *)checkbox;
- (void)monitorPresentClicked:(NSButton *)checkbox;
- (void)monitorTemperatureStepped:(NSStepper *)stepper;
@end

@implementation QLMFakeMonitorRow

- (instancetype)initWithMonitor:(QLMFakeMonitor *)monitor target:(id)target {
    self = [super init];
    if (self) {
        _monitor = monitor;
        NSTextField *name = [NSTextField labelWithString:monitor.serialNumber];
        name.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        _onCheckbox = [NSButton checkboxWithTitle:@"On" target:target action:@selector(monitorOnClicked:)];
        _presentCheckbox = [NSButton checkboxWithTitle:@"Plugged in" target:target action:@selector(monitorPresentClicked:)];
        _temperatureStepper = [[NSStepper alloc] init];
        _temperatureStepper.minValue = 20;
        _temperatureStepper.maxValue = 90;
        _temperatureStepper.increment = 1;
        _temperatureStepper.autorepeat = YES;
        _temperatureStepper.target = target;
        _temperatureStepper.action = @selector(monitorTemperatureStepped:);
        _temperatureLabel = [NSTextField labelWithString:@""];
        _temperatureLabel.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
        NSStackView *temperature = [NSStackView stackViewWithViews:@[_temperatureStepper, _temperatureLabel]];
        temperature.spacing = 4;
        _views = @[name, _onCheckbox, _presentCheckbox, temperature];
    }
    return self;
}

@end


@implementation QLMFakeBusWindowController

- (instancetype)init {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 300)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    panel.title = @"Fake Bus";
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    self = [super initWithWindow:panel];
    if (self) {
        _rows = @[];
        [self buildContent];
        [panel center];
    }
    return self;
}

- (void)buildContent {
    NSView *content = self.window.contentView;

    NSTextField *intro = [NSTextField wrappingLabelWithString:
        @"qlm runs on a fake bus until the controls are checked on real monitors. These play what the bus can do. qlm never opens the adapter."];
    intro.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    intro.textColor = NSColor.secondaryLabelColor;
    intro.preferredMaxLayoutWidth = 480;

    self.knobCheckbox = [NSButton checkboxWithTitle:@"Attached" target:self action:@selector(knobAttachedClicked:)];
    self.knobSlider = [NSSlider sliderWithValue:QLMKnobBottomTenths minValue:QLMKnobBottomTenths maxValue:0
                                         target:self action:@selector(knobTurned:)];
    self.knobSlider.continuous = YES;
    [self.knobSlider.widthAnchor constraintEqualToConstant:220].active = YES;
    self.knobLabel = [NSTextField labelWithString:@""];
    self.knobLabel.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    [self.knobLabel.widthAnchor constraintEqualToConstant:80].active = YES;
    NSStackView *knob = [NSStackView stackViewWithViews:@[self.knobCheckbox, self.knobSlider, self.knobLabel]];

    self.busyCheckbox = [NSButton checkboxWithTitle:@"GLM holds the adapter" target:self action:@selector(busyClicked:)];
    self.unpluggedCheckbox = [NSButton checkboxWithTitle:@"Unplugged" target:self action:@selector(unpluggedClicked:)];
    NSStackView *adapter = [NSStackView stackViewWithViews:@[self.busyCheckbox, self.unpluggedCheckbox]];
    adapter.spacing = 16;

    self.monitorsGrid = [NSGridView gridViewWithNumberOfColumns:4 rows:0];
    self.monitorsGrid.rowSpacing = 6;
    self.monitorsGrid.columnSpacing = 14;
    self.monitorsGrid.rowAlignment = NSGridRowAlignmentFirstBaseline;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Knob:"], knob],
        @[[NSTextField labelWithString:@"Adapter:"], adapter],
        @[[NSTextField labelWithString:@"Monitors:"], self.monitorsGrid],
    ]];
    grid.rowSpacing = 12;
    grid.columnSpacing = 8;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;

    NSStackView *stack = [NSStackView stackViewWithViews:@[intro, grid]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14;
    stack.edgeInsets = NSEdgeInsetsMake(16, 18, 18, 18);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
}

- (void)setBus:(QLMFakeBus *)bus {
    _bus = bus;
    while (self.monitorsGrid.numberOfRows > 0) {
        [self.monitorsGrid removeRowAtIndex:0];
    }
    NSMutableArray<QLMFakeMonitorRow *> *rows = [NSMutableArray array];
    for (QLMFakeMonitor *monitor in bus.monitors) {
        QLMFakeMonitorRow *row = [[QLMFakeMonitorRow alloc] initWithMonitor:monitor target:self];
        [self.monitorsGrid addRowWithViews:row.views];
        [rows addObject:row];
    }
    self.rows = rows;
    __block NSNumber *knob = nil;
    [bus perform:^{
        knob = bus.knobTenths;
    }];
    self.knobSlider.doubleValue = knob != nil ? knob.doubleValue : QLMKnobBottomTenths;
    [self refresh];
    [self.window setContentSize:self.window.contentView.fittingSize];
}

- (void)refresh {
    QLMFakeBus *bus = self.bus;
    if (bus == nil) {
        return;
    }
    __block NSNumber *knob = nil;
    __block BOOL unplugged = NO;
    NSMutableArray<NSArray<NSNumber *> *> *monitors = [NSMutableArray array];
    [bus perform:^{
        knob = bus.knobTenths;
        unplugged = bus.disconnected;
        for (QLMFakeMonitor *monitor in bus.monitors) {
            [monitors addObject:@[@(monitor.on), @(monitor.present), @(monitor.temperature)]];
        }
    }];
    self.knobCheckbox.state = knob != nil ? NSControlStateValueOn : NSControlStateValueOff;
    self.knobSlider.enabled = knob != nil;
    self.knobLabel.stringValue = knob != nil ? QLMDecibelsText(knob.doubleValue / 10) : @"Out";
    self.busyCheckbox.state = bus.busyReason != nil ? NSControlStateValueOn : NSControlStateValueOff;
    self.unpluggedCheckbox.state = unplugged ? NSControlStateValueOn : NSControlStateValueOff;
    [self.rows enumerateObjectsUsingBlock:^(QLMFakeMonitorRow *row, NSUInteger i, BOOL *stop) {
        NSArray<NSNumber *> *state = monitors[i];
        row.onCheckbox.state = state[0].boolValue ? NSControlStateValueOn : NSControlStateValueOff;
        row.presentCheckbox.state = state[1].boolValue ? NSControlStateValueOn : NSControlStateValueOff;
        row.temperatureStepper.integerValue = state[2].integerValue;
        row.temperatureLabel.stringValue = QLMTemperatureText(state[2].integerValue);
    }];
}

// TRAP: the fake bus keeps a lease forever. A real monitor drops its lease
// within 23 to 42 s of the host going quiet (qlm-first-discover), and System
// finds it again only by a probe, which a leased monitor ignores. So when
// the adapter comes back, the leases lapse here.
- (void)dropLeasesOnBus:(QLMFakeBus *)bus {
    for (QLMFakeMonitor *monitor in bus.monitors) {
        monitor.session = 0;
    }
}

#pragma mark - Actions

- (void)knobAttachedClicked:(NSButton *)checkbox {
    QLMFakeBus *bus = self.bus;
    NSNumber *knob = checkbox.state == NSControlStateValueOn ? @((NSInteger)self.knobSlider.doubleValue) : nil;
    [bus perform:^{
        bus.knobTenths = knob;
    }];
    [self refresh];
}

- (void)knobTurned:(NSSlider *)slider {
    QLMFakeBus *bus = self.bus;
    NSNumber *knob = @((NSInteger)lround(slider.doubleValue));
    [bus perform:^{
        bus.knobTenths = knob;
    }];
    [self refresh];
}

- (void)busyClicked:(NSButton *)checkbox {
    QLMFakeBus *bus = self.bus;
    BOOL busy = checkbox.state == NSControlStateValueOn;
    [bus perform:^{
        bus.busyReason = busy ? QLMFakeBusyReason : nil;
        if (!busy) {
            [self dropLeasesOnBus:bus];
        }
    }];
    [self refresh];
}

- (void)unpluggedClicked:(NSButton *)checkbox {
    QLMFakeBus *bus = self.bus;
    BOOL unplugged = checkbox.state == NSControlStateValueOn;
    [bus perform:^{
        bus.disconnected = unplugged;
        if (!unplugged) {
            [self dropLeasesOnBus:bus];
        }
    }];
    [self refresh];
}

- (nullable QLMFakeMonitorRow *)rowForControl:(NSControl *)control {
    for (QLMFakeMonitorRow *row in self.rows) {
        if (row.onCheckbox == control || row.presentCheckbox == control || row.temperatureStepper == control) {
            return row;
        }
    }
    return nil;
}

- (void)monitorOnClicked:(NSButton *)checkbox {
    QLMFakeMonitor *monitor = [self rowForControl:checkbox].monitor;
    BOOL on = checkbox.state == NSControlStateValueOn;
    [self.bus perform:^{
        monitor.on = on;
    }];
    [self refresh];
}

- (void)monitorPresentClicked:(NSButton *)checkbox {
    QLMFakeMonitor *monitor = [self rowForControl:checkbox].monitor;
    BOOL present = checkbox.state == NSControlStateValueOn;
    [self.bus perform:^{
        monitor.present = present;
        // A monitor plugged back in holds no lease.
        if (present) {
            monitor.session = 0;
        }
    }];
    [self refresh];
}

- (void)monitorTemperatureStepped:(NSStepper *)stepper {
    QLMFakeMonitor *monitor = [self rowForControl:stepper].monitor;
    uint8_t temperature = (uint8_t)stepper.integerValue;
    [self.bus perform:^{
        monitor.temperature = temperature;
    }];
    [self refresh];
}

@end
