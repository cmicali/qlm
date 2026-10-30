#import "QLMFakeBusWindowController.h"

#include <math.h>

#import "QLMFormat.h"
#import "QLMViews.h"

// The shape of QLMHostCheck's sentence for GLM, so System reads it as GLM
// holding the adapter.
static NSString *const QLMFakeBusyReason = @"GLM is running (pid 4242, /Applications/GLMv5.app/Contents/MacOS/GLMv5). Quit GLM first.";
static const NSInteger QLMKnobBottomTenths = -1004;

// One simulated monitor's controls. Each control's tag is the monitor's
// index on the bus.
@interface QLMFakeMonitorRow : NSObject
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

- (instancetype)initWithMonitor:(QLMFakeMonitor *)monitor index:(NSInteger)index target:(id)target {
    self = [super init];
    if (self) {
        NSTextField *name = [NSTextField labelWithString:monitor.serialNumber];
        name.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        _onCheckbox = [NSButton checkboxWithTitle:@"On" target:target action:@selector(monitorOnClicked:)];
        _onCheckbox.tag = index;
        _presentCheckbox = [NSButton checkboxWithTitle:@"Plugged in" target:target action:@selector(monitorPresentClicked:)];
        _presentCheckbox.tag = index;
        _temperatureStepper = [[NSStepper alloc] init];
        _temperatureStepper.minValue = 20;
        _temperatureStepper.maxValue = 90;
        _temperatureStepper.increment = 1;
        _temperatureStepper.autorepeat = YES;
        _temperatureStepper.target = target;
        _temperatureStepper.action = @selector(monitorTemperatureStepped:);
        _temperatureStepper.tag = index;
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

    NSTextField *intro = QLMNoteLabel(
        @"qlm runs on a fake bus until the controls are checked on real monitors. These play what the bus can do. qlm never opens the adapter.",
        480);

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
    [content addSubview:stack];
    QLMPinToEdges(stack, content);
}

- (void)setBus:(QLMFakeBus *)bus {
    _bus = bus;
    while (self.monitorsGrid.numberOfRows > 0) {
        [self.monitorsGrid removeRowAtIndex:0];
    }
    NSMutableArray<QLMFakeMonitorRow *> *rows = [NSMutableArray array];
    [bus.monitors enumerateObjectsUsingBlock:^(QLMFakeMonitor *monitor, NSUInteger i, BOOL *stop) {
        QLMFakeMonitorRow *row = [[QLMFakeMonitorRow alloc] initWithMonitor:monitor index:(NSInteger)i target:self];
        [self.monitorsGrid addRowWithViews:row.views];
        [rows addObject:row];
    }];
    self.rows = rows;
    [self refresh];
    [self.window setContentSize:self.window.contentView.fittingSize];
}

- (void)refresh {
    [self change:nil];
}

// Runs the change on the bus's queue, reads the bus back in the same visit,
// and shows what it read.
- (void)change:(nullable void (^)(QLMFakeBus *bus))change {
    QLMFakeBus *bus = self.bus;
    if (bus == nil) {
        return;
    }
    __block NSNumber *knob = nil;
    __block BOOL unplugged = NO;
    NSMutableArray<NSArray<NSNumber *> *> *monitors = [NSMutableArray array];
    [bus perform:^{
        if (change != nil) {
            change(bus);
        }
        knob = bus.knobTenths;
        unplugged = bus.disconnected;
        for (QLMFakeMonitor *monitor in bus.monitors) {
            [monitors addObject:@[@(monitor.on), @(monitor.present), @(monitor.temperature)]];
        }
    }];
    self.knobCheckbox.state = knob != nil ? NSControlStateValueOn : NSControlStateValueOff;
    self.knobSlider.enabled = knob != nil;
    if (knob != nil) {
        self.knobSlider.doubleValue = knob.doubleValue;
    }
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

#pragma mark - Actions

- (void)knobAttachedClicked:(NSButton *)checkbox {
    NSNumber *knob = checkbox.state == NSControlStateValueOn ? @((NSInteger)self.knobSlider.doubleValue) : nil;
    [self change:^(QLMFakeBus *bus) {
        bus.knobTenths = knob;
    }];
}

- (void)knobTurned:(NSSlider *)slider {
    NSNumber *knob = @((NSInteger)lround(slider.doubleValue));
    [self change:^(QLMFakeBus *bus) {
        bus.knobTenths = knob;
    }];
}

- (void)busyClicked:(NSButton *)checkbox {
    BOOL busy = checkbox.state == NSControlStateValueOn;
    [self change:^(QLMFakeBus *bus) {
        bus.busyReason = busy ? QLMFakeBusyReason : nil;
    }];
}

- (void)unpluggedClicked:(NSButton *)checkbox {
    BOOL unplugged = checkbox.state == NSControlStateValueOn;
    [self change:^(QLMFakeBus *bus) {
        bus.disconnected = unplugged;
    }];
}

- (void)monitorOnClicked:(NSButton *)checkbox {
    NSUInteger index = (NSUInteger)checkbox.tag;
    BOOL on = checkbox.state == NSControlStateValueOn;
    [self change:^(QLMFakeBus *bus) {
        bus.monitors[index].on = on;
    }];
}

- (void)monitorPresentClicked:(NSButton *)checkbox {
    NSUInteger index = (NSUInteger)checkbox.tag;
    BOOL present = checkbox.state == NSControlStateValueOn;
    [self change:^(QLMFakeBus *bus) {
        QLMFakeMonitor *monitor = bus.monitors[index];
        monitor.present = present;
        // A monitor plugged back in holds no lease.
        if (present) {
            monitor.session = 0;
        }
    }];
}

- (void)monitorTemperatureStepped:(NSStepper *)stepper {
    NSUInteger index = (NSUInteger)stepper.tag;
    uint8_t temperature = (uint8_t)stepper.integerValue;
    [self change:^(QLMFakeBus *bus) {
        bus.monitors[index].temperature = temperature;
    }];
}

@end
