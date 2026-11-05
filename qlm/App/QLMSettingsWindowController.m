#import "QLMSettingsWindowController.h"

#import <ServiceManagement/ServiceManagement.h>

#include "QLMCommands.h"
#import "QLMFormat.h"
#import "QLMMainWindowModel.h"
#import "QLMSkinLayout.h"
#import "QLMSkinLibrary.h"
#import "QLMViews.h"

static const CGFloat QLMSettingsTextWidth = 360;

@interface QLMSettingsWindowController () <NSWindowDelegate, NSTextFieldDelegate>
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMMonitorList *monitorList;
@property (nonatomic) NSButton *adapterCheckbox;
@property (nonatomic) NSTextField *handBackLevel;
@property (nonatomic) NSGridRow *handBackRow;
@property (nonatomic) NSPopUpButton *setupPicker;
@property (nonatomic) NSTextField *setupNote;
@property (nonatomic) NSTextField *lowestField;
@property (nonatomic) NSStepper *lowestStepper;
@property (nonatomic) NSTextField *ceilingField;
@property (nonatomic) NSStepper *ceilingStepper;
@property (nonatomic) NSTextField *rangeNote;
@property (nonatomic) NSButton *wakeCheckbox;
@property (nonatomic) NSButton *windowCheckbox;
@property (nonatomic) NSButton *loginCheckbox;
@property (nonatomic) NSTextField *loginNote;
@property (nonatomic) NSButton *loginItemsButton;
@property (nonatomic) NSGridView *grid;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, nullable) NSError *setupError;
@property (nonatomic, copy, nullable) NSString *loginError;
@property (nonatomic) NSButton *osdCheckbox;
@property (nonatomic) NSPopUpButton *osdPlacementPicker;
@property (nonatomic) NSTextField *osdSecondsField;
@property (nonatomic) NSStepper *osdSecondsStepper;
@property (nonatomic) NSPopUpButton *skinPicker;
@property (nonatomic) NSTextField *skinNote;
@property (nonatomic, nullable) QLMSkin *skin;
@property (nonatomic, copy, nullable) NSString *skinRefusal;
// The last pick's refusal, until the window opens again or a pick loads.
@property (nonatomic, copy, nullable) NSString *skinPickRefusal;
@end

@implementation QLMSettingsWindowController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences monitorList:(QLMMonitorList *)monitorList {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 300)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"qlm Settings";
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        _preferences = preferences;
        _monitorList = monitorList;
        window.delegate = self;
        [self buildContent];
        [window center];
    }
    return self;
}

- (void)buildContent {
    NSView *content = self.window.contentView;

    self.adapterCheckbox = [NSButton checkboxWithTitle:@"Drive the real monitors through the GLM adapter" target:self
                                                action:@selector(adapterClicked:)];
    NSTextField *adapterNote = QLMNoteLabel(
        @"On, qlm sends volume, mute, dim, power, and groups to the real monitors through the GLM adapter, "
        @"every volume at or below the ceiling. Off, qlm runs on a fake bus and sends nothing. A change reconnects.",
        QLMSettingsTextWidth);
    NSTextField *handBackNote = QLMNoteLabel(
        @"When qlm quits, the Mac sleeps, or this goes off, the adapter takes over about 2.6 s after qlm lets go, at its knob's level. "
        @"The ceiling does not apply to the knob. With the knob at or below qlm's level, qlm sends the knob's level first, "
        @"so nothing changes. With it above, or unknown, the level may rise, and qlm asks first. If USB drops, qlm can send nothing first.",
        QLMSettingsTextWidth);
    self.handBackLevel = QLMNoteLabel(@"", QLMSettingsTextWidth);

    self.setupPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.setupPicker.target = self;
    self.setupPicker.action = @selector(setupChosen:);
    NSButton *reveal = [NSButton buttonWithTitle:@"Show in Finder" target:self action:@selector(revealSetups:)];
    NSStackView *setupRow = [NSStackView stackViewWithViews:@[self.setupPicker, reveal]];
    self.setupNote = QLMNoteLabel(@"", QLMSettingsTextWidth);
    self.setupNote.selectable = YES;

    self.lowestField = [self decibelsField];
    self.lowestStepper = [self stepperWithIncrement:QLMVolumeDecibelsStep action:@selector(rangeChanged:)];
    NSStackView *lowestRow = [NSStackView stackViewWithViews:@[self.lowestField, self.lowestStepper, [NSTextField labelWithString:@"dB, up to the ceiling"]]];
    lowestRow.spacing = 4;

    self.ceilingField = [self decibelsField];
    self.ceilingStepper = [self stepperWithIncrement:QLMVolumeDecibelsStep action:@selector(rangeChanged:)];
    NSStackView *ceilingRow = [NSStackView stackViewWithViews:@[self.ceilingField, self.ceilingStepper, [NSTextField labelWithString:@"dB"]]];
    ceilingRow.spacing = 4;
    self.rangeNote = QLMNoteLabel(@"", QLMSettingsTextWidth);
    NSTextField *ceilingNote = QLMNoteLabel(
        @"No volume goes out above the ceiling. qlm's protocol layer caps every volume frame at it, "
        @"whether the level comes from the slider, the knob, dim, or a group. 0 dB is the monitors' full level.",
        QLMSettingsTextWidth);

    self.wakeCheckbox = [NSButton checkboxWithTitle:@"Wake the monitors" target:self action:@selector(wakeClicked:)];
    self.windowCheckbox = [NSButton checkboxWithTitle:@"Open the window" target:self action:@selector(windowClicked:)];
    self.loginCheckbox = [NSButton checkboxWithTitle:@"Open qlm at login" target:self action:@selector(loginClicked:)];
    self.loginNote = QLMNoteLabel(@"", QLMSettingsTextWidth);
    self.loginItemsButton = [NSButton buttonWithTitle:@"Open Login Items" target:self action:@selector(openLoginItems:)];
    self.loginItemsButton.controlSize = NSControlSizeSmall;

    NSTextField *rangeTitle = [NSTextField labelWithString:@"Volume range:"];
    NSTextField *launchTitle = [NSTextField labelWithString:@"At launch:"];
    NSTextField *setupTitle = [NSTextField labelWithString:@"Setup file:"];
    NSTextField *osdTitle = [NSTextField labelWithString:@"On-screen display:"];
    NSTextField *skinTitle = [NSTextField labelWithString:@"Skin:"];
    [self buildOSD];
    [self buildSkin];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Monitors:"], self.adapterCheckbox],
        @[[NSGridCell emptyContentView], adapterNote],
        @[[NSGridCell emptyContentView], handBackNote],
        @[[NSGridCell emptyContentView], self.handBackLevel],
        @[setupTitle, setupRow],
        @[[NSGridCell emptyContentView], self.setupNote],
        @[rangeTitle, lowestRow],
        @[[NSTextField labelWithString:@"Ceiling:"], ceilingRow],
        @[[NSGridCell emptyContentView], self.rangeNote],
        @[[NSGridCell emptyContentView], ceilingNote],
        @[launchTitle, self.wakeCheckbox],
        @[[NSGridCell emptyContentView], self.windowCheckbox],
        @[[NSGridCell emptyContentView], self.loginCheckbox],
        @[[NSGridCell emptyContentView], self.loginNote],
        @[[NSGridCell emptyContentView], self.loginItemsButton],
        @[skinTitle, [self skinRow]],
        @[[NSGridCell emptyContentView], self.skinNote],
        @[osdTitle, self.osdCheckbox],
        @[[NSTextField labelWithString:@"Place:"], self.osdPlacementPicker],
        @[[NSTextField labelWithString:@"Keep it up for:"], [self osdSecondsRow]],
    ]];
    grid.rowSpacing = 8;
    grid.columnSpacing = 8;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    // A note sits close under its control, and a new section stands apart.
    for (NSView *note in @[adapterNote, handBackNote, self.handBackLevel, self.setupNote, self.rangeNote, ceilingNote, self.loginNote, self.skinNote]) {
        [grid cellForView:note].row.topPadding = -4;
    }
    for (NSView *title in @[setupTitle, rangeTitle, launchTitle, skinTitle, osdTitle]) {
        [grid cellForView:title].row.topPadding = 10;
    }
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    self.grid = grid;
    self.handBackRow = [grid cellForView:self.handBackLevel].row;
    [grid cellForView:self.rangeNote].row.hidden = YES;
    [content addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [content.widthAnchor constraintEqualToConstant:QLMSettingsTextWidth + 160],
    ]];
}

// The grid sets the height, so no row stretches.
- (void)fitWindow {
    [self.window setContentSize:self.window.contentView.fittingSize];
}

- (NSTextField *)numberFieldWithFormatter:(NSFormatter *)formatter action:(SEL)action {
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = formatter;
    field.alignment = NSTextAlignmentRight;
    field.target = self;
    field.action = action;
    // TRAP: by default only Return sends the action. In qlm-app-first, a
    // ceiling typed and left was lost.
    field.cell.sendsActionOnEndEditing = YES;
    [field.widthAnchor constraintEqualToConstant:64].active = YES;
    return field;
}

// The level fields' refusals come through control:didFailToFormatString:.
- (NSTextField *)decibelsField {
    NSTextField *field = [self numberFieldWithFormatter:[[QLMDecibelsFormatter alloc] init] action:@selector(rangeChanged:)];
    field.delegate = self;
    return field;
}

- (NSStepper *)stepperWithIncrement:(double)increment action:(SEL)action {
    NSStepper *stepper = [[NSStepper alloc] init];
    stepper.increment = increment;
    stepper.autorepeat = YES;
    stepper.valueWraps = NO;
    stepper.target = self;
    stepper.action = action;
    return stepper;
}

- (void)showWindow:(id)sender {
    self.adapterCheckbox.state = self.preferences.usesAdapter ? NSControlStateValueOn : NSControlStateValueOff;
    [self reloadSetupNames];
    [self renderSetup];
    [self renderRange];
    [self renderLaunch];
    [self renderHandBack];
    [self renderOSD];
    self.skinPickRefusal = nil;
    [self renderSkin];
    [self fitWindow];
    [super showWindow:sender];
}

// The live line changes with every turn of the knob, so the window refits
// only when the line's height does.
- (void)refresh {
    if (QLMWindowIsSeen(self.window) && [self renderHandBack]) {
        [self fitWindow];
    }
}

#if DEBUG
- (void)drawWhileOpen {
    if (self.window.visible && [self renderHandBack]) {
        [self fitWindow];
    }
}
#endif

// A window that comes into view catches up at once.
- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
    [self refresh];
}

// The field's action saves it, and it goes as the field ends editing.
- (void)endEditing {
    [self.window makeFirstResponder:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self endEditing];
}

// Login Items may have changed in System Settings meanwhile.
- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self renderLaunch];
    [self fitWindow];
}

#pragma mark - The adapter

- (void)adapterClicked:(NSButton *)checkbox {
    BOOL on = checkbox.state == NSControlStateValueOn;
    if (!on && ![self.delegate settingsShouldTurnOffAdapter:self]) {
        checkbox.state = NSControlStateValueOn;
        return;
    }
    self.preferences.usesAdapter = on;
    [self.delegate settingsDidChangeAdapter:self];
}

#pragma mark - The setup file

- (void)reloadSetupNames {
    [self.setupPicker removeAllItems];
    NSArray<NSString *> *names = QLMSetupFileNames();
    if (names.count == 0) {
        [self.setupPicker addItemWithTitle:@"None in GLM's folder"];
        self.setupPicker.enabled = NO;
        return;
    }
    self.setupPicker.enabled = YES;
    [self.setupPicker addItemsWithTitles:names];
    NSString *chosen = self.preferences.setupFileName;
    if (chosen != nil && [names containsObject:chosen]) {
        [self.setupPicker selectItemWithTitle:chosen];
    } else {
        [self.setupPicker selectItemAtIndex:0];
    }
}

- (void)setupChosen:(NSPopUpButton *)picker {
    NSString *name = picker.titleOfSelectedItem;
    if (name == nil || [name isEqualToString:self.preferences.setupFileName]) {
        return;
    }
    self.preferences.setupFileName = name;
    [self.delegate settingsDidChooseSetupFile:self];
}

- (void)revealSetups:(id)sender {
    NSURL *directory = [NSURL fileURLWithPath:QLMSetupDirectory() isDirectory:YES];
    [NSWorkspace.sharedWorkspace openURL:directory];
}

// While the window is closed, showWindow: draws it.
- (void)showSetup:(QLMSetup *)setup error:(NSError *)error {
    self.setup = setup;
    self.setupError = error;
    if (self.window.visible) {
        [self renderSetup];
        [self fitWindow];
    }
}

#pragma mark - The volume range

// The fields and the steppers both send it. The formatter refuses a level
// above 0 dB first, so the preferences' refusal is a backstop.
- (void)rangeChanged:(NSControl *)control {
    double decibels = control.doubleValue;
    BOOL saved = control == self.ceilingField || control == self.ceilingStepper
        ? [self.preferences saveCeilingDecibels:decibels]
        : [self.preferences saveLowestDecibels:decibels];
    [self renderRange];
    if (!saved) {
        [self showRangeRefusal:QLMTypedLevelRefusal(decibels)];
        return;
    }
    [self.delegate settingsDidChangeVolumeRange:self];
}

// The formatter refused the text. The field takes back its saved value and
// keeps focus, and the note says why.
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error {
    double saved = control == self.ceilingField ? self.preferences.ceilingDecibels : self.preferences.lowestDecibels;
    NSText *editor = control.currentEditor;
    editor.string = [control.formatter stringForObjectValue:@(saved)] ?: @"";
    [editor selectAll:nil];
    [self showRangeRefusal:error];
    return NO;
}

// The note's row shows only with a refusal.
- (void)showRangeRefusal:(nullable NSString *)refusal {
    NSString *text = refusal ?: @"";
    if ([self.rangeNote.stringValue isEqualToString:text]) {
        return;
    }
    self.rangeNote.stringValue = text;
    [self.grid cellForView:self.rangeNote].row.hidden = refusal == nil;
    [self fitWindow];
}

#pragma mark - Launch

- (void)wakeClicked:(NSButton *)checkbox {
    self.preferences.wakesAtLaunch = checkbox.state == NSControlStateValueOn;
}

- (void)windowClicked:(NSButton *)checkbox {
    self.preferences.opensWindowAtLaunch = checkbox.state == NSControlStateValueOn;
}

- (void)loginClicked:(NSButton *)checkbox {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL done = checkbox.state == NSControlStateValueOn ? [service registerAndReturnError:&error] : [service unregisterAndReturnError:&error];
    self.loginError = done ? nil : error.localizedDescription;
    [self renderLaunch];
    [self fitWindow];
}

- (void)openLoginItems:(id)sender {
    [SMAppService openSystemSettingsLoginItems];
}

#pragma mark - The skin

- (void)buildSkin {
    self.skinPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.skinPicker.target = self;
    self.skinPicker.action = @selector(skinChosen:);
    self.skinNote = QLMNoteLabel(@"", QLMSettingsTextWidth);
    self.skinNote.selectable = YES;
}

- (NSStackView *)skinRow {
    NSButton *reveal = [NSButton buttonWithTitle:@"Show in Finder" target:self action:@selector(revealSkins:)];
    return [NSStackView stackViewWithViews:@[self.skinPicker, reveal]];
}

// The skin that shows is loaded again too, so a fixed one takes.
- (void)skinChosen:(NSPopUpButton *)picker {
    NSString *name = picker.titleOfSelectedItem;
    if (name == nil) {
        return;
    }
    // On success the delegate calls showSkin:refusal:.
    NSString *refusal = [self.delegate settings:self chooseSkinNamed:name];
    if (refusal != nil) {
        self.skinPickRefusal = refusal;
        [self renderSkin];
        [self fitWindow];
    }
}

// Only this button makes the user's folder.
- (void)revealSkins:(id)sender {
    NSURL *directory = [QLMSkinLibrary standardLibrary].userDirectory;
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL]) {
        NSBeep();
        return;
    }
    [NSWorkspace.sharedWorkspace openURL:directory];
}

- (void)showSkin:(QLMSkin *)skin refusal:(NSString *)refusal {
    self.skin = skin;
    self.skinRefusal = refusal;
    self.skinPickRefusal = nil;
    if (self.window.visible) {
        [self renderSkin];
        [self renderSetup];
        [self fitWindow];
    }
}

// Lists the user's folder again, so a skin added since shows.
- (void)renderSkin {
    QLMSkinLibrary *library = [QLMSkinLibrary standardLibrary];
    NSString *chosen = self.preferences.skinName;
    NSString *shownName = self.skin.name ?: QLMSkinDefaultName;

    [self.skinPicker removeAllItems];
    BOOL separated = NO;
    for (NSString *name in [library skinNames]) {
        if (!separated && ![library isBuiltIn:name]) {
            separated = YES;
            [self.skinPicker.menu addItem:NSMenuItem.separatorItem];
        }
        [self.skinPicker addItemWithTitle:name];
    }
    // A chosen skin whose folder is gone shows as the fallback.
    [self.skinPicker selectItemWithTitle:[self.skinPicker itemWithTitle:chosen] != nil ? chosen : shownName];

    self.skinNote.stringValue = QLMSkinNote(self.skinPickRefusal ?: self.skinRefusal, shownName, library.userDirectory);
}

#pragma mark - The on-screen display

// In QLMOSDPlacement's order.
static NSArray<NSString *> *QLMOSDPlacementTitles(void) {
    return @[@"Top left", @"Top center", @"Top right", @"Bottom left", @"Bottom center", @"Bottom right"];
}

- (void)buildOSD {
    self.osdCheckbox = [NSButton checkboxWithTitle:@"Show the OSD when the knob turns" target:self action:@selector(osdClicked:)];
    self.osdPlacementPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.osdPlacementPicker addItemsWithTitles:QLMOSDPlacementTitles()];
    self.osdPlacementPicker.target = self;
    self.osdPlacementPicker.action = @selector(osdPlacementChosen:);

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 1;
    formatter.maximumFractionDigits = 1;
    self.osdSecondsField = [self numberFieldWithFormatter:formatter action:@selector(osdSecondsChanged:)];
    self.osdSecondsStepper = [self stepperWithIncrement:QLMOSDSecondsStep action:@selector(osdSecondsChanged:)];
    self.osdSecondsStepper.minValue = QLMOSDSecondsMin;
    self.osdSecondsStepper.maxValue = QLMOSDSecondsMax;
}

- (NSStackView *)osdSecondsRow {
    NSStackView *row = [NSStackView stackViewWithViews:@[self.osdSecondsField, self.osdSecondsStepper, [NSTextField labelWithString:@"s"]]];
    row.spacing = 4;
    return row;
}

- (void)osdClicked:(NSButton *)checkbox {
    self.preferences.showsOSD = checkbox.state == NSControlStateValueOn;
    [self renderOSD];
    [self.delegate settingsDidChangeOSD:self];
}

- (void)osdPlacementChosen:(NSPopUpButton *)picker {
    self.preferences.osdPlacement = (QLMOSDPlacement)picker.indexOfSelectedItem;
    [self.delegate settingsDidChangeOSD:self];
}

// The preferences hold it to the range, on the half seconds. An emptied
// field would read as 0 s, so it keeps the old value.
- (void)osdSecondsChanged:(NSControl *)control {
    if (control != self.osdSecondsField || control.objectValue != nil) {
        self.preferences.osdSeconds = control.doubleValue;
    }
    [self renderOSD];
    [self.delegate settingsDidChangeOSD:self];
}

- (void)renderOSD {
    BOOL shows = self.preferences.showsOSD;
    NSTimeInterval seconds = self.preferences.osdSeconds;
    self.osdCheckbox.state = shows ? NSControlStateValueOn : NSControlStateValueOff;
    [self.osdPlacementPicker selectItemAtIndex:self.preferences.osdPlacement];
    self.osdSecondsField.doubleValue = seconds;
    self.osdSecondsStepper.doubleValue = seconds;
    self.osdPlacementPicker.enabled = shows;
    self.osdSecondsField.enabled = shows;
    self.osdSecondsStepper.enabled = shows;
}

#pragma mark - Drawing

// Returns whether the line's height changed.
- (BOOL)renderHandBack {
    QLMSnapshot *snapshot = self.monitorList.snapshot;
    NSString *text = QLMHandBackLine(snapshot);
    if ([self.handBackLevel.stringValue isEqualToString:text ?: @""] && self.handBackRow.hidden == (text == nil)) {
        return NO;
    }
    CGFloat height = self.handBackRow.hidden ? 0 : self.handBackLevel.fittingSize.height;
    self.handBackLevel.stringValue = text ?: @"";
    self.handBackRow.hidden = text == nil;
    return height != (self.handBackRow.hidden ? 0 : self.handBackLevel.fittingSize.height);
}

- (void)renderSetup {
    if (self.setup != nil) {
        NSArray<NSString *> *names = self.setup.groupNames;
        NSString *count = names.count == 1 ? @"1 group" : [NSString stringWithFormat:@"%lu groups", (unsigned long)names.count];
        self.setupNote.stringValue = [NSString stringWithFormat:@"%@: %@.", count, [names componentsJoinedByString:@", "]];
        NSUInteger buttons = QLMShownGroupButtons(QLMSkinGroupButtonCount(self.skin));
        if (names.count > buttons) {
            self.setupNote.stringValue = [self.setupNote.stringValue
                stringByAppendingFormat:@" The window shows the first %lu.", (unsigned long)buttons];
        }
    } else if (self.setupError != nil) {
        self.setupNote.stringValue = [NSString stringWithFormat:@"It does not read: %@", self.setupError.localizedDescription];
    } else {
        self.setupNote.stringValue = [NSString stringWithFormat:@"GLM saves setup files in %@.", QLMSetupDirectory().stringByAbbreviatingWithTildeInPath];
    }
}

- (void)renderRange {
    double lowest = self.preferences.lowestDecibels;
    double ceiling = self.preferences.ceilingDecibels;
    self.lowestField.doubleValue = lowest;
    self.lowestStepper.minValue = QLMVolumeDecibelsMin;
    self.lowestStepper.maxValue = ceiling - QLMVolumeRangeMinimumSpan;
    self.lowestStepper.doubleValue = lowest;
    self.ceilingField.doubleValue = ceiling;
    self.ceilingStepper.minValue = lowest + QLMVolumeRangeMinimumSpan;
    self.ceilingStepper.maxValue = QLMVolumeDecibelsMax;
    self.ceilingStepper.doubleValue = ceiling;
    [self showRangeRefusal:nil];
}

// Asks macOS for the login item's status, so only when the window shows.
- (void)renderLaunch {
    self.wakeCheckbox.state = self.preferences.wakesAtLaunch ? NSControlStateValueOn : NSControlStateValueOff;
    self.windowCheckbox.state = self.preferences.opensWindowAtLaunch ? NSControlStateValueOn : NSControlStateValueOff;

    SMAppServiceStatus status = SMAppService.mainAppService.status;
    self.loginCheckbox.state = status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval
        ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *note = self.loginError;
    if (note == nil && status == SMAppServiceStatusRequiresApproval) {
        note = @"macOS needs your approval. Allow qlm under Login Items in System Settings.";
    }
    self.loginNote.stringValue = note ?: @"";
    [self.grid cellForView:self.loginNote].row.hidden = note == nil;
    [self.grid cellForView:self.loginItemsButton].row.hidden = status != SMAppServiceStatusRequiresApproval;
}

@end
