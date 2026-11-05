#import <XCTest/XCTest.h>

#import "QLMFormat.h"
#import "QLMMainWindowModel.h"
#import "QLMSkinLayout.h"
#import "QLMSnapshotInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"

static NSError *QLMApplyError(QLMSystemError code, BOOL refused) {
    return [NSError errorWithDomain:QLMSystemErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: @"The reason.", QLMSystemErrorRefusedKey: @(refused)}];
}

// What the main window shows and enables. Sources: docs/ui.md's "The main
// window", and QLMPopoverController's rules, which the window mirrors.
@interface QLMMainWindowModelTests : XCTestCase
@end

@implementation QLMMainWindowModelTests {
    QLMMainWindowModel *_model;
}

- (void)setUp {
    [super setUp];
    _model = [[QLMMainWindowModel alloc] init];
    _model.lowestDecibels = -60;
    _model.ceilingDecibels = -30;
    _model.setupFileName = @"Main.sam";
    _model.groupNames = @[@"Main", @"Nearfield", @"Full Range"];
    [self showRunningWith:nil];
}

// A running System that tracks two monitors, both on, at -40 dB under a
// -30 dB ceiling, sending -40 dB, as `change` then leaves it.
- (void)showRunningWith:(nullable void (^)(QLMSnapshot *snapshot))change {
    QLMSnapshot *snapshot = QLMMakeRunningSnapshot(@[QLMMakeMonitor(0x11, 0x02, QLMMonitorStatusOn),
                                                     QLMMakeMonitor(0x11, 0x03, QLMMonitorStatusOn)]);
    snapshot.anyOn = YES;
    snapshot.volumeDecibels = @(-40);
    snapshot.ceilingDecibels = -30;
    snapshot.handBack = QLMMakeHandBack(QLMHandBackKnobLevel, @(-60), @(-40));
    if (change != nil) {
        change(snapshot);
    }
    _model.snapshot = snapshot;
}

- (void)showStopped {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.running = NO;
    }];
}

- (void)showNoMonitors {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.monitors = @[];
    }];
}

#pragma mark - The status

- (void)testTheStatusCountsTheMonitorsOnline {
    XCTAssertEqualObjects(_model.statusText, @"2 ONLINE");
    XCTAssertTrue(_model.statusLit);
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.monitors = @[QLMMakeMonitor(0x11, 0x02, QLMMonitorStatusOn), QLMMakeMonitor(0x11, 0x03, QLMMonitorStatusStandby)];
    }];
    XCTAssertEqualObjects(_model.statusText, @"1 ONLINE");
    XCTAssertTrue(_model.statusLit);
}

// A monitor System calls offline is not online, though its last poll said on.
- (void)testTheLEDIsDimWithNoneOnline {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        QLMMonitorState *offline = QLMMakeMonitor(0x11, 0x03, QLMMonitorStatusOn);
        offline.offline = YES;
        snapshot.monitors = @[QLMMakeMonitor(0x11, 0x02, QLMMonitorStatusStandby), offline];
    }];
    XCTAssertEqualObjects(_model.statusText, @"0 ONLINE");
    XCTAssertFalse(_model.statusLit);
}

- (void)testABusProblemReplacesTheCount {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.busProblem = QLMBusProblemGLM;
    }];
    XCTAssertEqualObjects(_model.busProblem, @"GLM has the adapter");
    XCTAssertEqualObjects(_model.statusText, @"GLM HAS THE ADAPTER");
}

#pragma mark - The groups

- (void)testOneButtonPerGroupInTheFilesOrder {
    XCTAssertEqualObjects(_model.groupTitles, (@[@"MAIN", @"NEARFIELD", @"FULL RANGE"]));
    XCTAssertEqualObjects(_model.groupPrefixes, (@[@"A", @"B", @"C"]));
    XCTAssertEqualObjects(_model.shownGroupNames, (@[@"Main", @"Nearfield", @"Full Range"]));
    XCTAssertNil(_model.groupsMessage);
    XCTAssertTrue(_model.groupsEnabled);
}

- (void)testSixGroupsShowAtMost {
    _model.groupNames = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8"];
    XCTAssertEqualObjects(_model.shownGroupNames, (@[@"1", @"2", @"3", @"4", @"5", @"6"]));
    XCTAssertEqualObjects(_model.groupPrefixes, (@[@"A", @"B", @"C", @"D", @"E", @"F"]));
}

// A skin with fewer cells shows fewer groups, so no group lacks a button.
- (void)testASmallerGridShowsFewerGroups {
    _model.groupNames = @[@"1", @"2", @"3", @"4", @"5", @"6"];
    _model.groupCapacity = 4;
    XCTAssertEqualObjects(_model.shownGroupNames, (@[@"1", @"2", @"3", @"4"]));
    XCTAssertEqual(_model.groupTitles.count, 4u);
    _model.groupCapacity = 9;
    XCTAssertEqual(_model.shownGroupNames.count, 6u);
    XCTAssertEqual(QLMShownGroupButtons(9), 6u);
    XCTAssertEqual(QLMShownGroupButtons(4), 4u);
}

- (void)testTheActiveGroupIsSelected {
    XCTAssertEqual(_model.selectedGroupIndex, (NSUInteger)NSNotFound);
    XCTAssertEqual(_model.chosenGroupIndex, (NSUInteger)NSNotFound);
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.activeGroupName = @"Nearfield";
    }];
    XCTAssertEqual(_model.selectedGroupIndex, 1u);
    XCTAssertEqual(_model.chosenGroupIndex, 1u);
}

// The popover picker's rule: no System, no monitors tracked, or an apply in
// flight.
- (void)testTheButtonsFollowThePickersRule {
    [self showStopped];
    XCTAssertFalse(_model.groupsEnabled);
    [self showNoMonitors];
    XCTAssertFalse(_model.groupsEnabled);
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.applying = YES;
    }];
    XCTAssertTrue(_model.applying);
    XCTAssertFalse(_model.groupsEnabled);
    [self showRunningWith:nil];
    XCTAssertTrue(_model.groupsEnabled);
    _model.applyPending = YES;
    XCTAssertFalse(_model.groupsEnabled);
    _model.applyPending = NO;
    _model.snapshot = nil;
    XCTAssertFalse(_model.groupsEnabled);
}

// What the window's group verb answers, and what a click does nothing on.
- (void)testAButtonSaysWhyItTakesNoClick {
    XCTAssertNil([_model refusalToClickGroupNamed:@"Nearfield"]);
    XCTAssertEqualObjects([_model refusalToClickGroupNamed:@"Cinema"],
                          @"no group button reads Cinema. They read: Main, Nearfield, Full Range");
    _model.applyPending = YES;
    XCTAssertEqualObjects([_model refusalToClickGroupNamed:@"Main"], @"the group buttons are disabled while an apply runs");
    _model.applyPending = NO;
    [self showNoMonitors];
    XCTAssertEqualObjects([_model refusalToClickGroupNamed:@"Main"], @"the group buttons are disabled until System tracks a monitor");
    _model.groupNames = nil;
    XCTAssertEqualObjects([_model refusalToClickGroupNamed:@"Main"], @"no group buttons show: Reading Main.sam…");
}

// While an apply runs, whoever started it, the applying group's button
// blinks. VoiceOver reads it as chosen throughout.
- (void)testTheApplyingGroupBlinks {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.activeGroupName = @"Main";
        snapshot.applying = YES;
        snapshot.applyingGroupName = @"Full Range";
    }];
    XCTAssertEqualObjects(_model.applyingGroupName, @"Full Range");
    for (NSNumber *blink in @[@YES, @NO]) {
        _model.blinkOn = blink.boolValue;
        XCTAssertEqual(_model.selectedGroupIndex, blink.boolValue ? 2u : (NSUInteger)NSNotFound);
        XCTAssertEqual(_model.chosenGroupIndex, 2u);
    }
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.activeGroupName = @"Main";
    }];
    XCTAssertNil(_model.applyingGroupName);
    XCTAssertEqual(_model.selectedGroupIndex, 0u);
    XCTAssertTrue(_model.groupsEnabled);
}

// Between the click and System's first snapshot of the apply, the click's
// group blinks.
- (void)testAPendingClickBlinksItsGroup {
    _model.clickedGroupName = @"Nearfield";
    XCTAssertNil(_model.applyingGroupName);
    _model.applyPending = YES;
    _model.blinkOn = YES;
    XCTAssertEqualObjects(_model.applyingGroupName, @"Nearfield");
    XCTAssertEqual(_model.selectedGroupIndex, 1u);
}

// With no groups, the grid's place names the file, or its error.
- (void)testWithNoGroupsTheMessageSaysWhy {
    _model.groupNames = nil;
    XCTAssertFalse(_model.groupsEnabled);
    XCTAssertEqualObjects(_model.groupTitles, @[]);
    XCTAssertEqualObjects(_model.groupsMessage, @"Reading Main.sam…");
    _model.setupError = @"Main.sam is not a GLM setup file.";
    XCTAssertEqualObjects(_model.groupsMessage, @"Main.sam is not a GLM setup file.");
    _model.setupError = nil;
    _model.setupFileName = nil;
    XCTAssertEqualObjects(_model.groupsMessage, @"No setup file in GLM's folder");
    _model.setupFileName = @"Empty.sam";
    _model.groupNames = @[];
    XCTAssertEqualObjects(_model.groupsMessage, @"Empty.sam has no groups");
}

#pragma mark - The display

- (void)testTheDisplayShowsTheThreeLevels {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.activeGroupName = @"Main";
    }];
    XCTAssertEqualObjects(_model.caption, @"MAIN");
    XCTAssertEqualObjects(_model.levelText, @"−40.0");
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT −40.0");
    XCTAssertEqualObjects(_model.maxText, @"MAX −30");
    XCTAssertFalse(_model.displayDisabled);
}

- (void)testNoGroupLeavesTheCaptionEmpty {
    XCTAssertEqualObjects(_model.caption, @"");
}

// The large number stays undimmed. OUTPUT is what goes out.
- (void)testDimLowersOnlyTheOutput {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.dimmed = YES;
        snapshot.handBack = QLMMakeHandBack(QLMHandBackKnobLevel, @(-70), @(-60));
    }];
    XCTAssertEqualObjects(_model.levelText, @"−40.0");
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT −60.0");
    XCTAssertTrue(_model.dimOn);
}

- (void)testMuteAllShowsMuted {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.allMuted = YES;
    }];
    XCTAssertEqualObjects(_model.levelText, @"−40.0");
    XCTAssertEqualObjects(_model.outputText, @"MUTED");
    XCTAssertTrue(_model.muteOn);
}

- (void)testAnEmDashWhileNoLevelIsSetOrItWaitsForTheKnob {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.volumeDecibels = nil;
        snapshot.handBack = QLMMakeHandBack(QLMHandBackUnknown, nil, nil);
    }];
    XCTAssertEqualObjects(_model.levelText, QLMEmDash);
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT —");
    XCTAssertNil(_model.knobDecibels);

    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.levelAwaitsKnob = YES;
    }];
    XCTAssertEqualObjects(_model.levelText, QLMEmDash);
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT —");
    // The knob points at no level the display hides.
    XCTAssertNil(_model.knobDecibels);
}

// Before a level is set, the preferences say the ceiling, as in the popover.
- (void)testMaxIsTheCeiling {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.volumeDecibels = nil;
        snapshot.ceilingDecibels = -10;
    }];
    XCTAssertEqualObjects(_model.maxText, @"MAX −30");
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.ceilingDecibels = -20.5;
    }];
    XCTAssertEqualObjects(_model.maxText, @"MAX −20.5");
}

// The error stands until the next click. The bottom line names the clicked
// group, and says whether System sent anything, by QLMSystemErrorRefused.
// The tooltip says why.
- (void)testAnApplyErrorSaysRefusedOrFailed {
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.allMuted = YES;
    }];
    _model.clickedGroupName = @"Full Range";
    _model.applyError = QLMApplyError(QLMSystemErrorUnverifiedRate, YES);
    XCTAssertEqualObjects(_model.outputText, @"FULL RANGE REFUSED");
    _model.applyError = QLMApplyError(QLMSystemErrorNotRunning, YES);
    XCTAssertEqualObjects(_model.outputText, @"FULL RANGE REFUSED");
    _model.applyError = QLMApplyError(QLMSystemErrorNotRunning, NO);
    XCTAssertEqualObjects(_model.outputText, @"FULL RANGE FAILED");
    _model.applyError = QLMApplyError(QLMSystemErrorSendFailed, NO);
    XCTAssertEqualObjects(_model.outputText, @"FULL RANGE FAILED");
    _model.applyError = nil;
    XCTAssertEqualObjects(_model.outputText, @"MUTED");
}

// The status dims with it.
- (void)testTheDisplayDimsWhileSystemIsStopped {
    XCTAssertTrue(_model.statusEnabled);
    [self showStopped];
    XCTAssertTrue(_model.displayDisabled);
    XCTAssertFalse(_model.statusEnabled);
    _model.snapshot = nil;
    XCTAssertTrue(_model.displayDisabled);
    XCTAssertFalse(_model.statusEnabled);
}

#pragma mark - Mute, dim, the knob, and power

// As the popover's: Mute needs a monitor, Dim a running System.
- (void)testMuteAndDimAreTheirToggles {
    XCTAssertFalse(_model.muteOn);
    XCTAssertFalse(_model.dimOn);
    XCTAssertTrue(_model.muteEnabled);
    XCTAssertTrue(_model.dimEnabled);
    [self showNoMonitors];
    XCTAssertFalse(_model.muteEnabled);
    XCTAssertTrue(_model.dimEnabled);
    [self showStopped];
    XCTAssertFalse(_model.dimEnabled);
}

- (void)testTheKnobSpansTheSlidersRange {
    XCTAssertEqualObjects(_model.knobMinText, @"−60");
    XCTAssertEqualObjects(_model.knobMaxText, @"−30");
    _model.lowestDecibels = -70.5;
    XCTAssertEqualObjects(_model.knobMinText, @"−70.5");
    XCTAssertEqualObjects(_model.knobDecibels, @(-40));
    XCTAssertTrue(_model.knobEnabled);
    [self showStopped];
    XCTAssertFalse(_model.knobEnabled);
}

- (void)testThePowerButtonFollowsAnyOn {
    XCTAssertEqualObjects(_model.powerTitle, @"Standby");
    XCTAssertFalse(_model.powerWakes);
    XCTAssertTrue(_model.powerEnabled);
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.anyOn = NO;
    }];
    XCTAssertEqualObjects(_model.powerTitle, @"Wake");
    XCTAssertTrue(_model.powerWakes);
    [self showNoMonitors];
    XCTAssertFalse(_model.powerEnabled);
}

#pragma mark - The menu

// The menu's Volume Up and Down step the knob as its arrow keys do: one
// 0.5 dB step, inside the range, so never past the ceiling. They take
// nothing while the knob takes nothing, before a level is known, or at an
// end.
- (void)testTheMenusVolumeStepsTheKnob {
    XCTAssertEqualObjects([_model levelSteppedFrom:-40 by:1], @(-39.5));
    XCTAssertEqualObjects([_model levelSteppedFrom:-40 by:-1], @(-40.5));
    XCTAssertEqualObjects([_model levelSteppedFrom:-40.2 by:1], @(-39.5));
    XCTAssertEqualObjects([_model levelSteppedFrom:-30.5 by:1], @(-30));
    XCTAssertNil([_model levelSteppedFrom:-30 by:1]);
    XCTAssertNil([_model levelSteppedFrom:-60 by:-1]);
    XCTAssertEqualObjects([_model levelSteppedFrom:-60 by:1], @(-59.5));

    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.levelAwaitsKnob = YES;
    }];
    XCTAssertNil([_model levelSteppedFrom:-40 by:1]);
    [self showRunningWith:^(QLMSnapshot *snapshot) {
        snapshot.volumeDecibels = nil;
    }];
    XCTAssertNil([_model levelSteppedFrom:-40 by:1]);
    [self showStopped];
    XCTAssertNil([_model levelSteppedFrom:-40 by:-1]);
}

@end
