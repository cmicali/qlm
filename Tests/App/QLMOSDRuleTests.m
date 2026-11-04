#import <XCTest/XCTest.h>

#import "QLMOSDRule.h"
#import "QLMSnapshotInternal.h"

// When the OSD shows, on a clock of the test's own. Source: docs/ui.md's
// "The OSD", and the snapshot's volumeFromKnob, which System sets only
// when it followed the knob.
@interface QLMOSDRuleTests : XCTestCase
@end

@implementation QLMOSDRuleTests {
    NSTimeInterval _now;
    QLMOSDRule *_rule;
}

- (void)setUp {
    [super setUp];
    _now = 100;
    __weak QLMOSDRuleTests *weakSelf = self;
    _rule = [[QLMOSDRule alloc] initWithNow:^NSTimeInterval {
        QLMOSDRuleTests *strongSelf = weakSelf;
        return strongSelf != nil ? strongSelf->_now : 0;
    }];
}

static QLMSnapshot *QLMLevel(double decibels, BOOL fromKnob) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.volumeDecibels = @(decibels);
    snapshot.volumeFromKnob = fromKnob;
    return snapshot;
}

// The app's level at launch, then a turn.
- (void)launchAt:(double)decibels {
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(decibels, NO)]);
}

#pragma mark - The rule

// A launch's first snapshot only sets the level to compare with, whatever
// it carries: a relaunch keeps the flag from before.
- (void)testTheFirstSnapshotNeverShows {
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-40, YES)]);
    XCTAssertFalse(_rule.showing);
}

- (void)testATurnShowsItForTheSeconds {
    [self launchAt:-40];
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-38.5, YES)]);
    XCTAssertTrue(_rule.showing);
    XCTAssertEqual(_rule.hidesAt, 102);
    _now = 101.9;
    XCTAssertTrue(_rule.showing);
    _now = 102;
    XCTAssertFalse(_rule.showing);
}

// A turn that goes on keeps it up: each show restarts the timer.
- (void)testASecondTurnRestartsTheTimer {
    [self launchAt:-40];
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-39.5, YES)]);
    _now = 101.5;
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-39, YES)]);
    XCTAssertEqual(_rule.hidesAt, 103.5);
    _now = 103;
    XCTAssertTrue(_rule.showing);
    _now = 103.5;
    XCTAssertFalse(_rule.showing);
}

// Every other snapshot of the same level, telemetry among them, leaves it
// alone, flag or not.
- (void)testTheSameLevelNeverShows {
    [self launchAt:-40];
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-38, YES)]);
    _now = 101;
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-38, YES)]);
    XCTAssertEqual(_rule.hidesAt, 102);
    _now = 103;
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-38, YES)]);
    XCTAssertFalse(_rule.showing);
}

// The slider, the window's knob, qlmctl volume, a ceiling, and a start or
// gap that lowered the level all clear the flag.
- (void)testALevelNotFromTheKnobNeverShows {
    [self launchAt:-40];
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-50, NO)]);
    XCTAssertFalse(_rule.showing);
    // A turn back to a level shown before still shows: it differs from the
    // snapshot before.
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-40, YES)]);
}

- (void)testNoLevelNeverShows {
    [self launchAt:-40];
    QLMSnapshot *none = QLMLevel(0, YES);
    none.volumeDecibels = nil;
    XCTAssertFalse([_rule showsSnapshot:none]);
}

// Off in Settings, a turn shows nothing. Turned off while it shows, it
// hides. Turned on again, the next turn shows, and not the one before.
- (void)testOffShowsNothing {
    [self launchAt:-40];
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-39, YES)]);
    _rule.enabled = NO;
    XCTAssertFalse(_rule.showing);
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-38, YES)]);
    XCTAssertFalse(_rule.showing);
    _rule.enabled = YES;
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-38, YES)]);
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-37, YES)]);
}

- (void)testTheSecondsComeFromTheSetting {
    _rule.seconds = 0.5;
    [self launchAt:-40];
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-39, YES)]);
    XCTAssertEqual(_rule.hidesAt, 100.5);
}

// While it shows, mute all or dim shows it again, so the subtitle follows.
// While it is hidden, neither shows it.
- (void)testMuteOrDimWhileShowingShowsAgain {
    [self launchAt:-40];
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-39, YES)]);
    _now = 101;
    QLMSnapshot *muted = QLMLevel(-39, YES);
    muted.allMuted = YES;
    XCTAssertTrue([_rule showsSnapshot:muted]);
    XCTAssertEqual(_rule.hidesAt, 103);
    _now = 104;
    QLMSnapshot *dimmed = QLMLevel(-39, YES);
    dimmed.allMuted = YES;
    dimmed.dimmed = YES;
    XCTAssertFalse([_rule showsSnapshot:dimmed]);
    XCTAssertFalse(_rule.showing);
}

- (void)testAHideEndsItAtOnce {
    [_rule show];
    XCTAssertTrue(_rule.showing);
    [_rule hide];
    XCTAssertFalse(_rule.showing);
}

#pragma mark - What it shows

- (void)testTheTitleIsTheActiveGroup {
    QLMSnapshot *snapshot = QLMLevel(-40, YES);
    XCTAssertEqualObjects(QLMOSDTitle(snapshot), @"Monitors");
    snapshot.activeGroupName = @"Main";
    XCTAssertEqualObjects(QLMOSDTitle(snapshot), @"Main");
}

// docs/ui.md's open questions: MUTED or DIM in the subtitle's place.
- (void)testTheSubtitleSaysMutedOrDim {
    QLMSnapshot *snapshot = QLMLevel(-40, YES);
    XCTAssertEqualObjects(QLMOSDSubtitle(snapshot), @"qlm · Output level");
    snapshot.dimmed = YES;
    XCTAssertEqualObjects(QLMOSDSubtitle(snapshot), @"DIM");
    snapshot.allMuted = YES;
    XCTAssertEqualObjects(QLMOSDSubtitle(snapshot), @"MUTED");
}

- (void)testTheBarIsTheLevelsPlaceInTheRange {
    XCTAssertEqual(QLMOSDFraction(-60, -60, -30), 0);
    XCTAssertEqual(QLMOSDFraction(-45, -60, -30), 0.5);
    XCTAssertEqual(QLMOSDFraction(-30, -60, -30), 1);
    XCTAssertEqual(QLMOSDFraction(-80, -60, -30), 0);
    XCTAssertEqual(QLMOSDFraction(-20, -60, -30), 1);
    XCTAssertEqual(QLMOSDFraction(NAN, -60, -30), 0);
}

// A screen whose visible frame starts above the Dock, at 0, 40.
- (void)testTheSixPlaces {
    CGRect visible = CGRectMake(0, 40, 1440, 835);
    CGSize size = CGSizeMake(480, 150);
    NSDictionary<NSNumber *, NSValue *> *expected = @{
        @(QLMOSDPlacementTopLeft): [NSValue valueWithRect:NSMakeRect(24, 701, 480, 150)],
        @(QLMOSDPlacementTopCenter): [NSValue valueWithRect:NSMakeRect(480, 701, 480, 150)],
        @(QLMOSDPlacementTopRight): [NSValue valueWithRect:NSMakeRect(936, 701, 480, 150)],
        @(QLMOSDPlacementBottomLeft): [NSValue valueWithRect:NSMakeRect(24, 64, 480, 150)],
        @(QLMOSDPlacementBottomCenter): [NSValue valueWithRect:NSMakeRect(480, 64, 480, 150)],
        @(QLMOSDPlacementBottomRight): [NSValue valueWithRect:NSMakeRect(936, 64, 480, 150)],
    };
    for (NSNumber *placement in expected) {
        CGRect frame = QLMOSDFrame(visible, size, (QLMOSDPlacement)placement.integerValue);
        XCTAssertTrue(NSEqualRects(frame, expected[placement].rectValue), @"%@: %@", placement, NSStringFromRect(frame));
    }
}

@end
