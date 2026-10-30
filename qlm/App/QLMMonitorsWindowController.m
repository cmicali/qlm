#import "QLMMonitorsWindowController.h"

#import "QLMBannerView.h"
#import "QLMFormat.h"
#import "QLMViews.h"

static NSUserInterfaceItemIdentifier const QLMColumnStatus = @"status";
static NSUserInterfaceItemIdentifier const QLMColumnModel = @"model";
static NSUserInterfaceItemIdentifier const QLMColumnSerial = @"serial";
static NSUserInterfaceItemIdentifier const QLMColumnFirmware = @"firmware";
static NSUserInterfaceItemIdentifier const QLMColumnTemperature = @"temperature";
static NSUserInterfaceItemIdentifier const QLMColumnInput = @"input";
static NSUserInterfaceItemIdentifier const QLMColumnHF = @"hf";
static NSUserInterfaceItemIdentifier const QLMColumnLF = @"lf";
static NSUserInterfaceItemIdentifier const QLMColumnSub = @"sub";
static NSUserInterfaceItemIdentifier const QLMColumnLastReply = @"lastReply";

// The meters read about 1 dB a count over 80. Real replies stayed under 9F
// (docs/refused-frames.md), so the bar spans 48 counts.
static const double QLMMeterBarCounts = 48;

// A label, centered in the row.
@interface QLMTextCell : NSTableCellView
@end

@implementation QLMTextCell

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSTextField *label = [NSTextField labelWithString:@""];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:label];
        self.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2],
            [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

@end

// A status dot and its name.
@interface QLMStatusCell : NSTableCellView
@property (nonatomic, readonly) NSImageView *dot;
@property (nonatomic, readonly) NSTextField *label;
@end

@implementation QLMStatusCell

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _dot = QLMDotView();
        _label = [NSTextField labelWithString:@""];
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
        NSStackView *stack = [NSStackView stackViewWithViews:@[_dot, _label]];
        stack.spacing = 5;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

@end

// A level bar and its count, or an em dash when the telemetry has none.
@interface QLMMeterCell : NSTableCellView
@property (nonatomic, readonly) NSLevelIndicator *bar;
@property (nonatomic, readonly) NSTextField *label;
- (void)showRaw:(NSInteger)raw;
@end

@implementation QLMMeterCell

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _bar = [[NSLevelIndicator alloc] init];
        _bar.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity;
        _bar.minValue = 0;
        _bar.maxValue = QLMMeterBarCounts;
        _bar.warningValue = QLMMeterBarCounts * 0.75;
        _bar.criticalValue = QLMMeterBarCounts * 0.9;
        _bar.editable = NO;
        _label = [NSTextField labelWithString:@""];
        _label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
        _label.textColor = NSColor.secondaryLabelColor;
        _label.alignment = NSTextAlignmentRight;
        NSStackView *stack = [NSStackView stackViewWithViews:@[_bar, _label]];
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.widthAnchor constraintEqualToConstant:22],
        ]];
    }
    return self;
}

- (void)showRaw:(NSInteger)raw {
    NSInteger counts = QLMMeterCounts(raw);
    self.bar.hidden = counts < 0;
    self.bar.doubleValue = (double)MAX(0, counts);
    self.label.stringValue = counts < 0 ? QLMEmDash : [NSString stringWithFormat:@"%ld", (long)counts];
    self.toolTip = counts < 0 ? @"Not in the last telemetry" : [NSString stringWithFormat:@"Raw %02lX: about %ld dB over the floor", (long)raw, (long)counts];
}

@end

@interface QLMMonitorsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) QLMBannerView *banner;
@property (nonatomic) NSTextField *adapterLabel;
@property (nonatomic) NSTextField *knobLabel;
@property (nonatomic) NSTextField *busLabel;
@property (nonatomic) NSTableView *table;
@end

@implementation QLMMonitorsWindowController

- (instancetype)initWithMonitorList:(QLMMonitorList *)monitorList {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 330)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"qlm Monitors";
    window.releasedWhenClosed = NO;
    window.contentMinSize = NSMakeSize(720, 240);
    window.frameAutosaveName = @"QLMMonitors";
    self = [super initWithWindow:window];
    if (self) {
        _monitorList = monitorList;
        [self buildContent];
        [window center];
    }
    return self;
}

- (void)buildContent {
    NSView *content = self.window.contentView;

    self.banner = [[QLMBannerView alloc] initWithTextWidth:820];

    self.adapterLabel = [NSTextField labelWithString:@""];
    self.adapterLabel.selectable = YES;
    self.knobLabel = [NSTextField labelWithString:@""];
    self.busLabel = [NSTextField labelWithString:@""];
    self.busLabel.selectable = YES;
    NSStackView *adapter = [NSStackView stackViewWithViews:@[
        [self headerRowTitled:@"Adapter" value:self.adapterLabel],
        [self headerRowTitled:@"Knob" value:self.knobLabel],
        [self headerRowTitled:@"Bus" value:self.busLabel],
    ]];
    adapter.orientation = NSUserInterfaceLayoutOrientationVertical;
    adapter.alignment = NSLayoutAttributeLeading;
    adapter.spacing = 4;

    self.table = [[NSTableView alloc] init];
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.table.rowHeight = 22;
    self.table.style = NSTableViewStyleFullWidth;
    self.table.allowsColumnReordering = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self addColumn:QLMColumnStatus title:@"Status" width:120 tip:@"Power state from telemetry, or why the monitor is offline"];
    [self addColumn:QLMColumnModel title:@"Model" width:56 tip:nil];
    [self addColumn:QLMColumnSerial title:@"Serial" width:124 tip:nil];
    [self addColumn:QLMColumnFirmware title:@"Firmware" width:64 tip:nil];
    [self addColumn:QLMColumnTemperature title:@"Temp" width:48 tip:nil];
    [self addColumn:QLMColumnInput title:@"Input" width:72 tip:@"Before the volume. Approximate: about 1 dB a count over the floor."];
    [self addColumn:QLMColumnHF title:@"HF out" width:72 tip:@"After the volume and mute. Approximate."];
    [self addColumn:QLMColumnLF title:@"LF out" width:72 tip:@"After the volume and mute. Approximate."];
    [self addColumn:QLMColumnSub title:@"Sub out" width:72 tip:@"Subwoofers only. Approximate."];
    [self addColumn:QLMColumnLastReply title:@"Last reply" width:84 tip:nil];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    NSTextField *note = QLMNoteLabel(
        @"Meters are approximate: counts over each meter's floor, about 1 dB a count. The input meter is before the volume, and the outputs after it. A monitor System drops stays here, offline.",
        0);
    [note setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *stack = [NSStackView stackViewWithViews:@[self.banner, adapter, scroll, note]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 14, 16);
    [content addSubview:stack];
    QLMPinToEdges(stack, content);
    [NSLayoutConstraint activateConstraints:@[
        [self.banner.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32],
        [note.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:120],
    ]];
}

- (NSStackView *)headerRowTitled:(NSString *)title value:(NSTextField *)value {
    NSTextField *label = [NSTextField labelWithString:title];
    label.textColor = NSColor.secondaryLabelColor;
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:56].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[label, value]];
    row.alignment = NSLayoutAttributeFirstBaseline;
    row.spacing = 8;
    return row;
}

- (void)addColumn:(NSUserInterfaceItemIdentifier)identifier title:(NSString *)title width:(CGFloat)width tip:(nullable NSString *)tip {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = 40;
    column.headerToolTip = tip;
    [self.table addTableColumn:column];
}

- (void)showWindow:(id)sender {
    [self render];
    [super showWindow:sender];
}

- (void)refresh {
    if (self.window.visible) {
        [self render];
    }
}

- (void)render {
    QLMSnapshot *snapshot = self.monitorList.snapshot;
    QLMAdapterState *adapter = snapshot.adapter;
    [self.banner showError:snapshot.adapterError];

    NSMutableArray<NSString *> *identity = [NSMutableArray array];
    [identity addObject:adapter.model ?: @"Not identified"];
    if (adapter.firmwareVersion != nil) {
        [identity addObject:[NSString stringWithFormat:@"firmware %@", adapter.firmwareVersion]];
    }
    if (adapter.serialNumber != nil) {
        [identity addObject:[NSString stringWithFormat:@"serial %@", adapter.serialNumber]];
    }
    self.adapterLabel.stringValue = [identity componentsJoinedByString:@", "];
    if (!adapter.hasStatus) {
        self.knobLabel.stringValue = QLMEmDash;
    } else if (adapter.knobTenths == nil) {
        self.knobLabel.stringValue = @"Not attached";
    } else {
        self.knobLabel.stringValue = QLMDecibelsText(adapter.knobTenths.doubleValue / 10);
    }
    NSString *device = adapter.device ?: QLMEmDash;
    self.busLabel.stringValue = [NSString stringWithFormat:@"%@, last reply %@", device, QLMReplyAgeText(adapter.lastReply)];
    // Keeps the row views when only their contents change.
    NSUInteger rows = self.monitorList.entries.count;
    if ((NSInteger)rows == self.table.numberOfRows) {
        [self.table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, rows)]
                              columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)self.table.numberOfColumns)]];
    } else {
        [self.table reloadData];
    }
}

#pragma mark - The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.monitorList.entries.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableColumn == nil) {
        return nil;
    }
    QLMMonitorEntry *entry = self.monitorList.entries[(NSUInteger)row];
    QLMMonitorState *monitor = entry.state;
    NSUserInterfaceItemIdentifier identifier = tableColumn.identifier;

    if ([identifier isEqualToString:QLMColumnStatus]) {
        QLMStatusCell *cell = [self cellOfClass:[QLMStatusCell class] identifier:identifier];
        cell.dot.contentTintColor = QLMPresenceColor(entry.presence);
        NSString *status = QLMEntryStatusText(entry);
        if (entry.tracked && monitor.muted) {
            status = [status stringByAppendingString:@", muted"];
        }
        cell.label.stringValue = status;
        cell.toolTip = [NSString stringWithFormat:@"Hardware ID %@, session %02X", [self hexOf:monitor.hardwareID], monitor.session];
        return cell;
    }
    NSNumber *meter = @{
        QLMColumnInput: @(monitor.inputMeter),
        QLMColumnHF: @(monitor.hfMeter),
        QLMColumnLF: @(monitor.lfMeter),
        QLMColumnSub: @(monitor.subMeter),
    }[identifier];
    if (meter != nil) {
        QLMMeterCell *cell = [self cellOfClass:[QLMMeterCell class] identifier:identifier];
        [cell showRaw:entry.tracked ? meter.integerValue : QLMMonitorValueAbsent];
        return cell;
    }

    QLMTextCell *cell = [self cellOfClass:[QLMTextCell class] identifier:identifier];
    NSTextField *label = cell.textField;
    label.textColor = entry.tracked ? NSColor.labelColor : NSColor.secondaryLabelColor;
    label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    if ([identifier isEqualToString:QLMColumnModel]) {
        label.stringValue = monitor.model ?: QLMEmDash;
    } else if ([identifier isEqualToString:QLMColumnSerial]) {
        label.stringValue = monitor.serialNumber ?: QLMEmDash;
        label.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    } else if ([identifier isEqualToString:QLMColumnFirmware]) {
        label.stringValue = monitor.firmwareVersion ?: QLMEmDash;
    } else if ([identifier isEqualToString:QLMColumnTemperature]) {
        label.stringValue = entry.tracked ? QLMTemperatureText(monitor.temperature) : QLMEmDash;
        label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    } else {
        label.stringValue = QLMReplyAgeText(monitor.lastReply);
        label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    }
    return cell;
}

// A reused cell for the column, or a new one.
- (__kindof NSTableCellView *)cellOfClass:(Class)cellClass identifier:(NSUserInterfaceItemIdentifier)identifier {
    NSTableCellView *cell = [self.table makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[cellClass alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;
    }
    return cell;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return NO;
}

- (NSString *)hexOf:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 3];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:i == 0 ? @"%02X" : @" %02X", bytes[i]];
    }
    return hex;
}

@end
