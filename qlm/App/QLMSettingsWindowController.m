#import "QLMSettingsWindowController.h"

#import <ServiceManagement/ServiceManagement.h>

#include "QLMCommands.h"

static const CGFloat QLMSettingsTextWidth = 360;

static NSTextField *QLMNoteLabel(NSString *text) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    label.preferredMaxLayoutWidth = QLMSettingsTextWidth;
    return label;
}

@interface QLMSettingsWindowController ()
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) NSPopUpButton *setupPicker;
@property (nonatomic) NSTextField *setupNote;
@property (nonatomic) NSTextField *lowestField;
@property (nonatomic) NSStepper *lowestStepper;
@property (nonatomic) NSTextField *ceilingField;
@property (nonatomic) NSStepper *ceilingStepper;
@property (nonatomic) NSButton *wakeCheckbox;
@property (nonatomic) NSButton *loginCheckbox;
@property (nonatomic) NSTextField *loginNote;
@property (nonatomic) NSButton *loginItemsButton;
@property (nonatomic) NSGridView *grid;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, nullable) NSError *setupError;
@property (nonatomic, copy, nullable) NSString *loginError;
@end

@implementation QLMSettingsWindowController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 300)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"qlm Settings";
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        _preferences = preferences;
        [self buildContent];
        [window center];
    }
    return self;
}

- (void)buildContent {
    NSView *content = self.window.contentView;

    self.setupPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.setupPicker.target = self;
    self.setupPicker.action = @selector(setupChosen:);
    NSButton *reveal = [NSButton buttonWithTitle:@"Show in Finder" target:self action:@selector(revealSetups:)];
    NSStackView *setupRow = [NSStackView stackViewWithViews:@[self.setupPicker, reveal]];
    self.setupNote = QLMNoteLabel(@"");
    self.setupNote.selectable = YES;

    self.lowestField = [self decibelsField];
    self.lowestStepper = [self stepper];
    NSStackView *lowestRow = [NSStackView stackViewWithViews:@[self.lowestField, self.lowestStepper, [NSTextField labelWithString:@"dB, up to the ceiling"]]];
    lowestRow.spacing = 4;

    self.ceilingField = [self decibelsField];
    self.ceilingStepper = [self stepper];
    NSStackView *ceilingRow = [NSStackView stackViewWithViews:@[self.ceilingField, self.ceilingStepper, [NSTextField labelWithString:@"dB"]]];
    ceilingRow.spacing = 4;
    NSTextField *ceilingNote = QLMNoteLabel(
        @"No volume goes out above the ceiling. qlm's protocol layer caps every volume frame at it, "
        @"whether the level comes from the slider, the knob, dim, or a group. 0 dB is the monitors' full level. "
        @"A change reconnects to the monitors.");

    self.wakeCheckbox = [NSButton checkboxWithTitle:@"Wake the monitors" target:self action:@selector(wakeClicked:)];
    self.loginCheckbox = [NSButton checkboxWithTitle:@"Open qlm at login" target:self action:@selector(loginClicked:)];
    self.loginNote = QLMNoteLabel(@"");
    self.loginItemsButton = [NSButton buttonWithTitle:@"Open Login Items" target:self action:@selector(openLoginItems:)];
    self.loginItemsButton.controlSize = NSControlSizeSmall;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Setup file:"], setupRow],
        @[[NSGridCell emptyContentView], self.setupNote],
        @[[NSTextField labelWithString:@"Volume range:"], lowestRow],
        @[[NSTextField labelWithString:@"Ceiling:"], ceilingRow],
        @[[NSGridCell emptyContentView], ceilingNote],
        @[[NSTextField labelWithString:@"At launch:"], self.wakeCheckbox],
        @[[NSGridCell emptyContentView], self.loginCheckbox],
        @[[NSGridCell emptyContentView], self.loginNote],
        @[[NSGridCell emptyContentView], self.loginItemsButton],
    ]];
    grid.rowSpacing = 8;
    grid.columnSpacing = 8;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid rowAtIndex:1].topPadding = -4;
    [grid rowAtIndex:2].topPadding = 10;
    [grid rowAtIndex:4].topPadding = -4;
    [grid rowAtIndex:5].topPadding = 10;
    [grid rowAtIndex:7].topPadding = -4;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    self.grid = grid;
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

- (NSTextField *)decibelsField {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 1;
    formatter.maximumFractionDigits = 1;
    formatter.minusSign = @"−";
    formatter.lenient = YES;
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.formatter = formatter;
    field.alignment = NSTextAlignmentRight;
    field.target = self;
    field.action = @selector(decibelsEdited:);
    [field.widthAnchor constraintEqualToConstant:64].active = YES;
    return field;
}

- (NSStepper *)stepper {
    NSStepper *stepper = [[NSStepper alloc] init];
    stepper.increment = QLMVolumeDecibelsStep;
    stepper.autorepeat = YES;
    stepper.valueWraps = NO;
    stepper.target = self;
    stepper.action = @selector(stepped:);
    return stepper;
}

- (void)showWindow:(id)sender {
    [self reloadSetupNames];
    [self render];
    [self fitWindow];
    [super showWindow:sender];
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

- (void)showSetup:(QLMSetup *)setup error:(NSError *)error {
    self.setup = setup;
    self.setupError = error;
    [self render];
}

#pragma mark - The volume range

- (void)decibelsEdited:(NSTextField *)field {
    [self setDecibels:field.doubleValue forCeiling:field == self.ceilingField];
}

- (void)stepped:(NSStepper *)stepper {
    [self setDecibels:stepper.doubleValue forCeiling:stepper == self.ceilingStepper];
}

- (void)setDecibels:(double)decibels forCeiling:(BOOL)ceiling {
    if (ceiling) {
        self.preferences.ceilingDecibels = decibels;
    } else {
        self.preferences.lowestDecibels = decibels;
    }
    [self render];
    [self.delegate settingsDidChangeVolumeRange:self];
}

#pragma mark - Launch

- (void)wakeClicked:(NSButton *)checkbox {
    self.preferences.wakesAtLaunch = checkbox.state == NSControlStateValueOn;
}

- (void)loginClicked:(NSButton *)checkbox {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL done = checkbox.state == NSControlStateValueOn ? [service registerAndReturnError:&error] : [service unregisterAndReturnError:&error];
    self.loginError = done ? nil : error.localizedDescription;
    [self render];
}

- (void)openLoginItems:(id)sender {
    [SMAppService openSystemSettingsLoginItems];
}

#pragma mark - Drawing

- (void)render {
    if (self.setup != nil) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (QLMSetupGroup *group in self.setup.groups) {
            [names addObject:group.name];
        }
        NSString *count = self.setup.groups.count == 1 ? @"1 group" : [NSString stringWithFormat:@"%lu groups", (unsigned long)self.setup.groups.count];
        self.setupNote.stringValue = [NSString stringWithFormat:@"%@: %@.", count, [names componentsJoinedByString:@", "]];
    } else if (self.setupError != nil) {
        self.setupNote.stringValue = [NSString stringWithFormat:@"It does not read: %@", self.setupError.localizedDescription];
    } else {
        self.setupNote.stringValue = [NSString stringWithFormat:@"GLM saves setup files in %@.", QLMSetupDirectory().stringByAbbreviatingWithTildeInPath];
    }

    double lowest = self.preferences.lowestDecibels;
    double ceiling = self.preferences.ceilingDecibels;
    self.lowestField.doubleValue = lowest;
    self.lowestStepper.minValue = QLMVolumeDecibelsMin;
    self.lowestStepper.maxValue = ceiling - QLMVolumeRangeMinimumSpan;
    self.lowestStepper.doubleValue = lowest;
    self.ceilingField.doubleValue = ceiling;
    self.ceilingStepper.minValue = lowest + QLMVolumeRangeMinimumSpan;
    self.ceilingStepper.maxValue = 0;
    self.ceilingStepper.doubleValue = ceiling;

    self.wakeCheckbox.state = self.preferences.wakesAtLaunch ? NSControlStateValueOn : NSControlStateValueOff;

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
    if (self.window.visible) {
        [self fitWindow];
    }
}

@end
