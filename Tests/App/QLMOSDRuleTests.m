#import <XCTest/XCTest.h>

#import "QLMOSDRule.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

// When the OSD shows. Source: docs/ui.md's "The OSD", and the snapshot's
// volumeFromKnob, which System sets only when it followed the knob.
@interface QLMOSDRuleTests : XCTestCase
@end

@implementation QLMOSDRuleTests {
    QLMOSDRule *_rule;
}

- (void)setUp {
    [super setUp];
    _rule = [[QLMOSDRule alloc] init];
}

static QLMSnapshot *QLMLevel(double decibels, BOOL fromKnob) {
    QLMSnapshot *snapshot = QLMMakeRunningSnapshot(@[]);
    snapshot.volumeDecibels = @(decibels);
    snapshot.volumeFromKnob = fromKnob;
    return snapshot;
}

- (BOOL)shows:(QLMSnapshot *)snapshot {
    return [_rule showsSnapshot:snapshot whileShowing:NO];
}

// The app's level at launch.
- (void)launchAt:(double)decibels {
    XCTAssertFalse([self shows:QLMLevel(decibels, NO)]);
}

// A launch's first snapshot only sets the level to compare with, whatever
// it carries: a relaunch keeps the flag from before.
- (void)testTheFirstSnapshotNeverShows {
    XCTAssertFalse([self shows:QLMLevel(-40, YES)]);
}

// Each turn shows, so a turn that goes on keeps it up.
- (void)testEachTurnShows {
    [self launchAt:-40];
    XCTAssertTrue([self shows:QLMLevel(-39.5, YES)]);
    XCTAssertTrue([_rule showsSnapshot:QLMLevel(-39, YES) whileShowing:YES]);
}

// Every other snapshot of the same level, telemetry among them, leaves it
// alone, flag or not.
- (void)testTheSameLevelNeverShows {
    [self launchAt:-40];
    XCTAssertTrue([self shows:QLMLevel(-38, YES)]);
    XCTAssertFalse([_rule showsSnapshot:QLMLevel(-38, YES) whileShowing:YES]);
    XCTAssertFalse([self shows:QLMLevel(-38, YES)]);
}

// The slider, the window's knob, qlmctl volume, a ceiling, and a start or
// gap that lowered the level all clear the flag.
- (void)testALevelNotFromTheKnobNeverShows {
    [self launchAt:-40];
    XCTAssertFalse([self shows:QLMLevel(-50, NO)]);
    // A turn back to a level shown before still shows: it differs from the
    // snapshot before.
    XCTAssertTrue([self shows:QLMLevel(-40, YES)]);
}

- (void)testNoLevelNeverShows {
    [self launchAt:-40];
    QLMSnapshot *none = QLMLevel(0, YES);
    none.volumeDecibels = nil;
    XCTAssertFalse([self shows:none]);
}

// Off in Settings, a turn shows nothing. Turned on again, the next turn
// shows, and not the one before.
- (void)testOffShowsNothing {
    [self launchAt:-40];
    _rule.enabled = NO;
    XCTAssertFalse([self shows:QLMLevel(-38, YES)]);
    _rule.enabled = YES;
    XCTAssertFalse([self shows:QLMLevel(-38, YES)]);
    XCTAssertTrue([self shows:QLMLevel(-37, YES)]);
}

// A show with no turn, as the osd verb's: off, or no level, shows nothing.
- (void)testAShowWithNoTurnSaysWhyNot {
    XCTAssertNil([_rule refusalToShowSnapshot:QLMLevel(-40, NO)]);
    QLMSnapshot *none = QLMLevel(0, NO);
    none.volumeDecibels = nil;
    XCTAssertEqualObjects([_rule refusalToShowSnapshot:none], @"no level yet");
    XCTAssertEqualObjects([_rule refusalToShowSnapshot:nil], @"no level yet");
    _rule.enabled = NO;
    XCTAssertEqualObjects([_rule refusalToShowSnapshot:QLMLevel(-40, NO)], @"the OSD is off in Settings");
}

// While it shows, mute all or dim shows it again, so the subtitle follows.
// While it is hidden, neither shows it.
- (void)testMuteOrDimShowsOnlyWhileShowing {
    [self launchAt:-40];
    QLMSnapshot *muted = QLMLevel(-40, YES);
    muted.allMuted = YES;
    XCTAssertTrue([_rule showsSnapshot:muted whileShowing:YES]);
    QLMSnapshot *dimmed = QLMLevel(-40, YES);
    dimmed.allMuted = YES;
    dimmed.dimmed = YES;
    XCTAssertFalse([self shows:dimmed]);
}

// The first table's visible frame starts above the Dock, at 0, 40. The
// second's starts right of a Dock on the left, at x 80. The third is a
// screen left of and below the primary one, with a negative origin.
- (void)testTheSixPlaces {
    CGSize size = CGSizeMake(480, 150);
    NSArray<NSArray *> *screens = @[
        @[[NSValue valueWithRect:NSMakeRect(0, 40, 1440, 835)], @[
            [NSValue valueWithRect:NSMakeRect(24, 701, 480, 150)], [NSValue valueWithRect:NSMakeRect(480, 701, 480, 150)],
            [NSValue valueWithRect:NSMakeRect(936, 701, 480, 150)], [NSValue valueWithRect:NSMakeRect(24, 64, 480, 150)],
            [NSValue valueWithRect:NSMakeRect(480, 64, 480, 150)], [NSValue valueWithRect:NSMakeRect(936, 64, 480, 150)],
        ]],
        @[[NSValue valueWithRect:NSMakeRect(80, 0, 1360, 875)], @[
            [NSValue valueWithRect:NSMakeRect(104, 701, 480, 150)], [NSValue valueWithRect:NSMakeRect(520, 701, 480, 150)],
            [NSValue valueWithRect:NSMakeRect(936, 701, 480, 150)], [NSValue valueWithRect:NSMakeRect(104, 24, 480, 150)],
            [NSValue valueWithRect:NSMakeRect(520, 24, 480, 150)], [NSValue valueWithRect:NSMakeRect(936, 24, 480, 150)],
        ]],
        @[[NSValue valueWithRect:NSMakeRect(-1920, -1080, 1920, 1050)], @[
            [NSValue valueWithRect:NSMakeRect(-1896, -204, 480, 150)], [NSValue valueWithRect:NSMakeRect(-1200, -204, 480, 150)],
            [NSValue valueWithRect:NSMakeRect(-504, -204, 480, 150)], [NSValue valueWithRect:NSMakeRect(-1896, -1056, 480, 150)],
            [NSValue valueWithRect:NSMakeRect(-1200, -1056, 480, 150)], [NSValue valueWithRect:NSMakeRect(-504, -1056, 480, 150)],
        ]],
    ];
    for (NSArray *screen in screens) {
        NSRect visible = [screen[0] rectValue];
        NSArray<NSValue *> *expected = screen[1];
        for (QLMOSDPlacement placement = QLMOSDPlacementTopLeft; placement <= QLMOSDPlacementBottomRight; placement++) {
            CGRect frame = QLMOSDFrame(visible, size, placement);
            NSRect want = expected[(NSUInteger)placement].rectValue;
            XCTAssertTrue(NSEqualRects(frame, want), @"%@ %ld: %@", NSStringFromRect(visible), (long)placement, NSStringFromRect(frame));
        }
    }
}

@end
