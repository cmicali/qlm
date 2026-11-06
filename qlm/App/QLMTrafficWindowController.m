#import "QLMTrafficWindowController.h"

#import "QLMViews.h"

static NSUserInterfaceItemIdentifier const QLMTrafficColumnNumber = @"number";
static NSUserInterfaceItemIdentifier const QLMTrafficColumnTime = @"time";
static NSUserInterfaceItemIdentifier const QLMTrafficColumnDirection = @"direction";
static NSUserInterfaceItemIdentifier const QLMTrafficColumnTarget = @"target";
static NSUserInterfaceItemIdentifier const QLMTrafficColumnBytes = @"bytes";
static NSUserInterfaceItemIdentifier const QLMTrafficColumnWhat = @"what";

@interface QLMTrafficWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property (nonatomic, readwrite) QLMTrafficLog *log;
@property (nonatomic) NSTableView *table;
@property (nonatomic) NSButton *pauseButton;
@property (nonatomic) NSPopUpButton *directionPopup;
@property (nonatomic) NSPopUpButton *opcodePopup;
@property (nonatomic) NSPopUpButton *targetPopup;
@property (nonatomic) NSTextField *countLabel;
@property (nonatomic, readwrite) NSArray<QLMTrafficRow *> *shown;
@property (nonatomic, readwrite, getter=isOpen) BOOL open;
@property (nonatomic) BOOL subscribed;
// What the table hasn't drawn: rows appended, or a change that redraws all.
@property (nonatomic) QLMTrafficChange pending;
@property (nonatomic) NSUInteger choicesShown;  // the log's choicesChanges the popups show
@end

@implementation QLMTrafficWindowController

- (instancetype)initWithMonitorList:(QLMMonitorList *)monitorList {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 520)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"qlm Traffic";
    window.releasedWhenClosed = NO;
    window.contentMinSize = NSMakeSize(760, 240);
    window.frameAutosaveName = @"QLMTraffic";
    self = [super initWithWindow:window];
    if (self) {
        _log = [[QLMTrafficLog alloc] init];
        _log.monitorList = monitorList;
        _shown = @[];
        window.delegate = self;
        [self buildContent];
        [window center];
    }
    return self;
}

- (void)buildContent {
    NSView *content = self.window.contentView;

    self.pauseButton = QLMSmallButton(@"Pause", self, @selector(togglePause:));
    self.pauseButton.buttonType = NSButtonTypePushOnPushOff;
    self.pauseButton.toolTip = @"Holds the list still. Frames still arrive, and show on resume.";
    NSButton *clear = QLMSmallButton(@"Clear", self, @selector(clearRows:));

    self.directionPopup = [self popupWithAction:@selector(chooseDirection:)];
    [self.directionPopup addItemsWithTitles:@[@"Both ways", @"Sent", @"Received"]];
    self.opcodePopup = [self popupWithAction:@selector(chooseOpcode:)];
    self.targetPopup = [self popupWithAction:@selector(chooseTarget:)];
    [self rebuildFilterPopups];

    NSButton *copy = QLMSmallButton(@"Copy", self, @selector(copy:));
    copy.toolTip = @"Copies the selected rows, or every row shown, as text for a run's notes.md.";
    NSButton *export = QLMSmallButton(@"Export…", self, @selector(exportRows:));

    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *controls = [NSStackView stackViewWithViews:@[
        self.pauseButton, clear, self.directionPopup, self.opcodePopup, self.targetPopup, spacer, copy, export
    ]];
    controls.spacing = 8;

    self.table = [[NSTableView alloc] init];
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.table.rowHeight = 17;
    self.table.style = NSTableViewStyleFullWidth;
    self.table.allowsMultipleSelection = YES;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self addColumn:QLMTrafficColumnNumber title:@"#" width:56];
    [self addColumn:QLMTrafficColumnTime title:@"Time" width:92];
    [self addColumn:QLMTrafficColumnDirection title:@"Dir" width:84];
    [self addColumn:QLMTrafficColumnTarget title:@"Target" width:250];
    [self addColumn:QLMTrafficColumnBytes title:@"Bytes" width:230];
    [self addColumn:QLMTrafficColumnWhat title:@"What it does" width:420];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    self.countLabel = QLMNoteLabel(@"", 0);
    [self.countLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *stack = [NSStackView stackViewWithViews:@[controls, scroll, self.countLabel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(12, 16, 12, 16);
    [content addSubview:stack];
    QLMPinToEdges(stack, content);
    [NSLayoutConstraint activateConstraints:@[
        [controls.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32],
        [self.countLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-32],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:120],
    ]];
}

- (NSPopUpButton *)popupWithAction:(SEL)action {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.controlSize = NSControlSizeSmall;
    popup.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    popup.target = self;
    popup.action = action;
    return popup;
}

- (void)addColumn:(NSUserInterfaceItemIdentifier)identifier title:(NSString *)title width:(CGFloat)width {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = 30;
    [self.table addTableColumn:column];
}

#pragma mark - System's traffic

- (void)setSystem:(nullable QLMSystem *)system {
    if (system == _system) {
        return;
    }
    [self unsubscribe];
    _system = system;
    if (self.open) {
        [self subscribe];
    }
}

- (nullable QLMSetup *)setup {
    return self.log.setup;
}

- (void)setSetup:(nullable QLMSetup *)setup {
    self.log.setup = setup;
}

- (void)subscribe {
    QLMSystem *system = self.system;
    if (system == nil || self.subscribed) {
        return;
    }
    self.subscribed = YES;
    __weak QLMTrafficWindowController *weakSelf = self;
    __weak QLMSystem *weakSystem = system;
    [system setTrafficHandler:^(NSArray<QLMTrafficEntry *> *entries) {
        QLMTrafficWindowController *strongSelf = weakSelf;
        QLMSystem *from = weakSystem;
        // A batch from a System already replaced, or after a close, is stale.
        if (strongSelf != nil && from != nil && from == strongSelf.system && strongSelf.subscribed) {
            [strongSelf takeEntries:entries from:from];
        }
    } queue:dispatch_get_main_queue()];
}

- (void)unsubscribe {
    if (self.subscribed) {
        self.subscribed = NO;
        [self.system setTrafficHandler:nil queue:dispatch_get_main_queue()];
    }
}

- (void)takeEntries:(NSArray<QLMTrafficEntry *> *)entries from:(QLMSystem *)system {
    QLMTrafficChange change = [self.log addEntries:entries fromSystem:system];
    self.pending = MAX(self.pending, change);
    if (self.paused || !QLMWindowIsSeen(self.window)) {
        return;
    }
    [self render];
}

#pragma mark - The window

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    self.open = YES;
    [self subscribe];
    [self render];
}

- (void)windowWillClose:(NSNotification *)notification {
    self.open = NO;
    [self unsubscribe];
}

// A window that comes into view catches up at once.
- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
    if (!self.paused && QLMWindowIsSeen(self.window)) {
        [self render];
    }
}

#if DEBUG
- (void)drawWhileOpen {
    if (self.open) {
        [self render];
    }
}
#endif

// Appended rows go in at the end. Anything else redraws every row.
- (void)render {
    if (self.log.choicesChanges != self.choicesShown) {
        [self rebuildFilterPopups];
    }
    if (self.pending != QLMTrafficChangeNone && !self.paused) {
        NSClipView *clip = self.table.enclosingScrollView.contentView;
        BOOL atEnd = NSMaxY(clip.documentVisibleRect) >= NSMaxY(self.table.bounds) - self.table.rowHeight * 2;
        NSUInteger drawn = self.shown.count;
        self.shown = self.log.shownRows;
        if (self.pending == QLMTrafficChangeAppended && self.shown.count >= drawn) {
            [self.table insertRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(drawn, self.shown.count - drawn)]
                              withAnimation:NSTableViewAnimationEffectNone];
        } else {
            [self.table reloadData];
        }
        self.pending = QLMTrafficChangeNone;
        if (atEnd && self.shown.count > 0) {
            [self.table scrollRowToVisible:(NSInteger)self.shown.count - 1];
        }
    }
    NSString *count = [NSString stringWithFormat:@"%lu frames held, %lu shown.", (unsigned long)self.log.rowCount,
                                                 (unsigned long)self.shown.count];
    if (self.paused) {
        count = [count stringByAppendingString:@" Paused: the list holds still while frames arrive."];
    }
    self.countLabel.stringValue = [count stringByAppendingString:
        @" qlm only reads here. Each reply names the request it answers. Unknown fields say unknown."];
}

#pragma mark - Controls

- (void)setPaused:(BOOL)paused {
    _paused = paused;
    self.pauseButton.state = paused ? NSControlStateValueOn : NSControlStateValueOff;
    self.pauseButton.title = paused ? @"Resume" : @"Pause";
    [self render];
}

- (void)togglePause:(NSButton *)sender {
    self.paused = sender.state == NSControlStateValueOn;
}

- (void)clear {
    [self.log clear];
    self.pending = QLMTrafficChangeReset;
    [self render];
}

- (void)clearRows:(id)sender {
    [self clear];
}

- (void)rebuildFilterPopups {
    self.choicesShown = self.log.choicesChanges;
    [self.opcodePopup removeAllItems];
    [self.opcodePopup addItemWithTitle:@"Every opcode"];
    for (NSNumber *opcode in self.log.opcodes) {
        [self.opcodePopup addItemWithTitle:[NSString stringWithFormat:@"Opcode %02lX", (long)opcode.integerValue]];
        self.opcodePopup.lastItem.representedObject = opcode;
    }
    [self selectItemOf:self.opcodePopup representing:self.log.opcode];

    [self.targetPopup removeAllItems];
    [self.targetPopup addItemWithTitle:@"Every target"];
    for (NSArray<NSString *> *target in self.log.targets) {
        [self.targetPopup addItemWithTitle:target[1]];
        self.targetPopup.lastItem.representedObject = target[0];
    }
    [self selectItemOf:self.targetPopup representing:self.log.targetKey];
}

- (void)selectItemOf:(NSPopUpButton *)popup representing:(nullable id)object {
    NSInteger index = object == nil ? 0 : [popup indexOfItemWithRepresentedObject:object];
    [popup selectItemAtIndex:MAX(index, 0)];
}

- (void)filtersChanged {
    self.pending = QLMTrafficChangeReset;
    [self render];
}

- (void)chooseDirection:(NSPopUpButton *)sender {
    [self filterDirection:(QLMTrafficDirection)sender.indexOfSelectedItem];
}

- (void)chooseOpcode:(NSPopUpButton *)sender {
    [self filterOpcode:sender.selectedItem.representedObject];
}

- (void)chooseTarget:(NSPopUpButton *)sender {
    [self filterTarget:sender.selectedItem.representedObject];
}

- (void)filterDirection:(QLMTrafficDirection)direction {
    self.log.direction = direction;
    [self.directionPopup selectItemAtIndex:direction];
    [self filtersChanged];
}

- (nullable NSString *)filterOpcode:(nullable NSNumber *)opcode {
    if (self.log.choicesChanges != self.choicesShown) {
        [self rebuildFilterPopups];
    }
    if (opcode != nil && [self.opcodePopup indexOfItemWithRepresentedObject:opcode] < 0) {
        return [NSString stringWithFormat:@"no frame of opcode %02lX is held", (long)opcode.integerValue];
    }
    self.log.opcode = opcode;
    [self selectItemOf:self.opcodePopup representing:opcode];
    [self filtersChanged];
    return nil;
}

- (nullable NSString *)filterTarget:(nullable NSString *)targetKey {
    if (self.log.choicesChanges != self.choicesShown) {
        [self rebuildFilterPopups];
    }
    if (targetKey != nil && [self.targetPopup indexOfItemWithRepresentedObject:targetKey] < 0) {
        return [NSString stringWithFormat:@"no frame to %@ is held", targetKey];
    }
    self.log.targetKey = targetKey;
    [self selectItemOf:self.targetPopup representing:targetKey];
    [self filtersChanged];
    return nil;
}

- (NSArray<QLMTrafficRow *> *)chosenRows {
    NSIndexSet *selected = self.table.selectedRowIndexes;
    if (selected.count == 0) {
        return self.shown;
    }
    NSMutableArray<QLMTrafficRow *> *rows = [NSMutableArray array];
    [selected enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        if (index < self.shown.count) {
            [rows addObject:self.shown[index]];
        }
    }];
    return rows;
}

- (void)put:(NSString *)text {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

// Edit > Copy, and Cmd-C.
- (void)copy:(id)sender {
    [self put:[QLMTrafficLog textOfRows:[self chosenRows]]];
}

- (void)exportRows:(id)sender {
    NSString *text = [QLMTrafficLog textOfRows:[self chosenRows]];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"qlm traffic.txt";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        NSError *error = nil;
        if (![text writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            [[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

#pragma mark - The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.shown.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableColumn == nil || row < 0 || (NSUInteger)row >= self.shown.count) {
        return nil;
    }
    QLMTrafficRow *traffic = self.shown[(NSUInteger)row];
    NSUserInterfaceItemIdentifier identifier = tableColumn.identifier;
    NSTextField *label = [tableView makeViewWithIdentifier:identifier owner:self];
    if (label == nil) {
        label = [NSTextField labelWithString:@""];
        label.identifier = identifier;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        BOOL words = [identifier isEqualToString:QLMTrafficColumnTarget] || [identifier isEqualToString:QLMTrafficColumnWhat];
        label.font = words ? [NSFont systemFontOfSize:NSFont.smallSystemFontSize]
                           : [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    }
    NSString *text = nil;
    if ([identifier isEqualToString:QLMTrafficColumnNumber]) {
        text = [NSString stringWithFormat:@"%llu", traffic.entry.number];
    } else if ([identifier isEqualToString:QLMTrafficColumnTime]) {
        text = traffic.timeText;
    } else if ([identifier isEqualToString:QLMTrafficColumnDirection]) {
        text = traffic.directionText;
    } else if ([identifier isEqualToString:QLMTrafficColumnTarget]) {
        text = traffic.targetText;
    } else if ([identifier isEqualToString:QLMTrafficColumnBytes]) {
        text = traffic.bytesText;
    } else {
        text = traffic.descriptionText;
    }
    if (![label.stringValue isEqualToString:text]) {
        label.stringValue = text;
        label.toolTip = text;
    }
    label.textColor = traffic.entry.outgoing ? NSColor.labelColor : NSColor.secondaryLabelColor;
    return label;
}

@end
