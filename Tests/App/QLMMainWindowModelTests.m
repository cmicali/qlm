#import <XCTest/XCTest.h>

#import "QLMFormat.h"
#import "QLMMainWindowModel.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

static QLMMonitorState *QLMMonitor(uint8_t session, QLMMonitorStatus status) {
    const uint8_t hardwareID[3] = {0x11, 0x4B, session};
    QLMMonitorState *monitor = [[QLMMonitorState alloc] init];
    monitor.hardwareID = QLMBytes(hardwareID, sizeof hardwareID);
    monitor.session = session;
    monitor.status = status;
    return monitor;
}

// A running System that tracks two monitors, both on, at -40 dB under a
// -30 dB ceiling, sending -40 dB.
static QLMSnapshot *QLMRunning(void) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.monitors = @[QLMMonitor(0x02, QLMMonitorStatusOn), QLMMonitor(0x03, QLMMonitorStatusOn)];
    snapshot.anyOn = YES;
    snapshot.volumeDecibels = @(-40);
    snapshot.ceilingDecibels = -30;
    snapshot.handBack = QLMMakeHandBack(QLMHandBackKnobLevel, @(-60), @(-40));
    return snapshot;
}

// What the main window shows and enables. Sources: docs/ui.md's "The main
// window", and QLMPopoverController's rules, which the window mirrors.
@interface QLMMainWindowModelTests : XCTestCase
@end

@implementation QLMMainWindowModelTests {
    QLMMainWindowModel *_model;
    QLMMonitorList *_list;
}

- (void)setUp {
    [super setUp];
    _list = [[QLMMonitorList alloc] init];
    _model = [[QLMMainWindowModel alloc] init];
    _model.lowestDecibels = -60;
    _model.ceilingDecibels = -30;
    _model.setupFileName = @"Main.sam";
    _model.groupNames = @[@"Main", @"Nearfield", @"Full Range"];
    [self show:QLMRunning()];
}

- (void)show:(QLMSnapshot *)snapshot {
    [_list updateWithSnapshot:snapshot];
    _model.snapshot = snapshot;
    _model.entries = _list.entries;
}

#pragma mark - The status

- (void)testTheStatusCountsTheMonitorsOnline {
    XCTAssertEqualObjects(_model.statusText, @"2 ONLINE");
    XCTAssertTrue(_model.statusLit);
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.monitors = @[QLMMonitor(0x02, QLMMonitorStatusOn), QLMMonitor(0x03, QLMMonitorStatusStandby)];
    [self show:snapshot];
    XCTAssertEqualObjects(_model.statusText, @"1 ONLINE");
    XCTAssertTrue(_model.statusLit);
}

// The list keeps a dropped monitor, offline, so it no longer counts.
- (void)testTheLEDIsDimWithNoneOnline {
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.monitors = @[QLMMonitor(0x02, QLMMonitorStatusStandby)];
    [self show:snapshot];
    XCTAssertEqualObjects(_model.statusText, @"0 ONLINE");
    XCTAssertFalse(_model.statusLit);
}

- (void)testABusProblemReplacesTheCount {
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.busProblem = QLMBusProblemGLM;
    [self show:snapshot];
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
    XCTAssertEqual(QLMMainWindowMaxGroups, 6u);
}

- (void)testTheActiveGroupIsSelected {
    XCTAssertFalse([_model groupSelectedAtIndex:0]);
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.activeGroupName = @"Nearfield";
    [self show:snapshot];
    XCTAssertFalse([_model groupSelectedAtIndex:0]);
    XCTAssertTrue([_model groupSelectedAtIndex:1]);
    XCTAssertFalse([_model groupSelectedAtIndex:2]);
    XCTAssertFalse([_model groupSelectedAtIndex:6]);
}

// The popover picker's rule: no System, no monitors tracked, or an apply in
// flight.
- (void)testTheButtonsFollowThePickersRule {
    QLMSnapshot *stopped = QLMRunning();
    stopped.running = NO;
    [self show:stopped];
    XCTAssertFalse(_model.groupsEnabled);

    QLMSnapshot *none = QLMRunning();
    none.monitors = @[];
    [self show:none];
    XCTAssertFalse(_model.groupsEnabled);

    QLMSnapshot *applying = QLMRunning();
    applying.applying = YES;
    [self show:applying];
    XCTAssertTrue(_model.applying);
    XCTAssertFalse(_model.groupsEnabled);

    [self show:QLMRunning()];
    XCTAssertTrue(_model.groupsEnabled);
    _model.snapshot = nil;
    XCTAssertFalse(_model.groupsEnabled);
}

// While the window's own apply runs, every button is disabled and only the
// chosen one shows, in the blink's on phase.
- (void)testTheChosenGroupBlinksWhileItApplies {
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.activeGroupName = @"Main";
    [self show:snapshot];
    _model.applyingGroupName = @"Full Range";
    XCTAssertFalse(_model.groupsEnabled);
    _model.blinkOn = YES;
    XCTAssertFalse([_model groupSelectedAtIndex:0]);
    XCTAssertTrue([_model groupSelectedAtIndex:2]);
    _model.blinkOn = NO;
    XCTAssertFalse([_model groupSelectedAtIndex:0]);
    XCTAssertFalse([_model groupSelectedAtIndex:2]);
    _model.applyingGroupName = nil;
    XCTAssertTrue([_model groupSelectedAtIndex:0]);
    XCTAssertTrue(_model.groupsEnabled);
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
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.activeGroupName = @"Main";
    [self show:snapshot];
    XCTAssertEqualObjects(_model.caption, @"MAIN");
    XCTAssertEqualObjects(_model.levelText, @"−40.0");
    XCTAssertEqualObjects(_model.unitText, @"dB");
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT −40.0");
    XCTAssertEqualObjects(_model.maxText, @"MAX −30");
    XCTAssertFalse(_model.displayDisabled);
    XCTAssertEqualObjects(_model.displaySummary, @"Main. Level −40.0 dB. Output −40.0 dB. Ceiling −30.0 dB");
}

- (void)testNoGroupLeavesTheCaptionEmpty {
    XCTAssertEqualObjects(_model.caption, @"");
}

// The large number stays undimmed. OUTPUT is what goes out.
- (void)testDimLowersOnlyTheOutput {
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.dimmed = YES;
    snapshot.handBack = QLMMakeHandBack(QLMHandBackKnobLevel, @(-70), @(-60));
    [self show:snapshot];
    XCTAssertEqualObjects(_model.levelText, @"−40.0");
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT −60.0");
    XCTAssertTrue(_model.dimOn);
}

- (void)testMuteAllShowsMuted {
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.allMuted = YES;
    [self show:snapshot];
    XCTAssertEqualObjects(_model.levelText, @"−40.0");
    XCTAssertEqualObjects(_model.outputText, @"MUTED");
    XCTAssertTrue(_model.muteOn);
}

- (void)testAnEmDashWhileNoLevelIsSetOrItWaitsForTheKnob {
    QLMSnapshot *unset = QLMRunning();
    unset.volumeDecibels = nil;
    unset.handBack = QLMMakeHandBack(QLMHandBackUnknown, nil, nil);
    [self show:unset];
    XCTAssertEqualObjects(_model.levelText, QLMEmDash);
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT —");
    XCTAssertNil(_model.knobDecibels);

    QLMSnapshot *waits = QLMRunning();
    waits.levelAwaitsKnob = YES;
    [self show:waits];
    XCTAssertEqualObjects(_model.levelText, QLMEmDash);
    XCTAssertEqualObjects(_model.outputText, @"OUTPUT —");
}

// Before a level is set, the preferences say the ceiling, as in the popover.
- (void)testMaxIsTheCeiling {
    QLMSnapshot *unset = QLMRunning();
    unset.volumeDecibels = nil;
    unset.ceilingDecibels = -10;
    [self show:unset];
    XCTAssertEqualObjects(_model.maxText, @"MAX −30");
    QLMSnapshot *set = QLMRunning();
    set.ceilingDecibels = -20.5;
    [self show:set];
    XCTAssertEqualObjects(_model.maxText, @"MAX −20.5");
}

// The refusal stands until the next click. The bottom line names the group,
// and the summary, which the tooltip and VoiceOver read, says why.
- (void)testARefusalShowsInTheBottomLine {
    QLMSnapshot *snapshot = QLMRunning();
    snapshot.allMuted = YES;
    [self show:snapshot];
    _model.applyError = @"The 8351B's filter design rate is unverified.";
    _model.refusedGroupName = @"Full Range";
    XCTAssertEqualObjects(_model.outputText, @"FULL RANGE REFUSED");
    XCTAssertTrue([_model.displaySummary containsString:@"unverified"]);
}

- (void)testTheDisplayDimsWhileSystemIsStopped {
    QLMSnapshot *stopped = QLMRunning();
    stopped.running = NO;
    [self show:stopped];
    XCTAssertTrue(_model.displayDisabled);
    _model.snapshot = nil;
    XCTAssertTrue(_model.displayDisabled);
}

#pragma mark - Mute, dim, the knob, and power

- (void)testMuteAndDimAreTheirToggles {
    XCTAssertEqualObjects(_model.muteTitle, @"MUTE");
    XCTAssertEqualObjects(_model.dimTitle, @"DIM −20");
    XCTAssertFalse(_model.muteOn);
    XCTAssertFalse(_model.dimOn);
    XCTAssertTrue(_model.muteEnabled);
    XCTAssertTrue(_model.dimEnabled);

    // As the popover's: Mute needs a monitor, Dim a running System.
    QLMSnapshot *none = QLMRunning();
    none.monitors = @[];
    [self show:none];
    XCTAssertFalse(_model.muteEnabled);
    XCTAssertTrue(_model.dimEnabled);
    QLMSnapshot *stopped = QLMRunning();
    stopped.running = NO;
    [self show:stopped];
    XCTAssertFalse(_model.dimEnabled);
}

- (void)testTheKnobSpansTheSlidersRange {
    XCTAssertEqual(_model.knobMinimum, -60);
    XCTAssertEqual(_model.knobMaximum, -30);
    XCTAssertEqualObjects(_model.knobMinText, @"−60");
    XCTAssertEqualObjects(_model.knobMaxText, @"−30");
    _model.lowestDecibels = -70.5;
    XCTAssertEqualObjects(_model.knobMinText, @"−70.5");
    XCTAssertEqualObjects(_model.knobCaption, @"VOLUME");
    XCTAssertEqualObjects(_model.knobDecibels, @(-40));
    XCTAssertTrue(_model.knobEnabled);
    QLMSnapshot *stopped = QLMRunning();
    stopped.running = NO;
    [self show:stopped];
    XCTAssertFalse(_model.knobEnabled);
}

// Snapshots leave the knob alone for half a second after a turn.
- (void)testTheKnobHoldsAfterATurn {
    XCTAssertFalse(QLMKnobHolds(0, 1000));
    XCTAssertTrue(QLMKnobHolds(1000, 1000));
    XCTAssertTrue(QLMKnobHolds(1000, 1000.49));
    XCTAssertFalse(QLMKnobHolds(1000, 1000.5));
}

- (void)testThePowerButtonFollowsAnyOn {
    XCTAssertEqualObjects(_model.monitorsTitle, @"Monitors");
    XCTAssertEqualObjects(_model.powerTitle, @"Standby");
    XCTAssertFalse(_model.powerWakes);
    XCTAssertTrue(_model.powerEnabled);
    QLMSnapshot *asleep = QLMRunning();
    asleep.anyOn = NO;
    [self show:asleep];
    XCTAssertEqualObjects(_model.powerTitle, @"Wake");
    XCTAssertTrue(_model.powerWakes);
    QLMSnapshot *none = QLMRunning();
    none.monitors = @[];
    [self show:none];
    XCTAssertFalse(_model.powerEnabled);
}

@end
