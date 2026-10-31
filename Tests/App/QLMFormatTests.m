#import <XCTest/XCTest.h>

#import "QLMFormat.h"
#import "QLMSnapshotInternal.h"

// A running System's snapshot on the real adapter, with the knob and qlm's
// level as given. A nil knob was never read, or no knob is in.
static QLMSnapshot *QLMSnapshotWith(QLMHandBackKind kind, NSNumber *_Nullable knob, NSNumber *_Nullable volume) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.adapter.hasStatus = YES;
    snapshot.handBack.kind = kind;
    snapshot.handBack.knobDecibels = knob;
    snapshot.handBack.volumeDecibels = volume;
    return snapshot;
}

// What the app says, and when it warns, about the adapter's take-over at a
// stop (docs/protocol.md, The hand-back).
@interface QLMFormatTests : XCTestCase
@end

@implementation QLMFormatTests

#pragma mark - A stop

// The app warns before any stop that may make the monitors louder. qlmctl
// warns when the level at the take-over is unknown too.
- (void)testAStopMayRaiseTheLevelWhenTheTakeOverIsLouderOrUnknown {
    XCTAssertTrue(QLMStopMayRaiseLevel(QLMSnapshotWith(QLMHandBackLouder, @(-10), @(-50))));
    XCTAssertTrue(QLMStopMayRaiseLevel(QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50))));
    XCTAssertTrue(QLMStopMayRaiseLevel(QLMSnapshotWith(QLMHandBackUnknown, @(-10), nil)));
    XCTAssertFalse(QLMStopMayRaiseLevel(QLMSnapshotWith(QLMHandBackKnobLevel, @(-60), @(-50))));
}

// While the adapter is refused or gone, qlm sent nothing, so a stop hands
// nothing back. Nor does a System already stopped.
- (void)testAStopWithoutTheBusRaisesNothing {
    for (NSNumber *problem in @[@(QLMBusProblemGLM), @(QLMBusProblemOtherHost), @(QLMBusProblemNoAdapter)]) {
        QLMSnapshot *refused = QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50));
        refused.busProblem = problem.integerValue;
        XCTAssertFalse(QLMStopMayRaiseLevel(refused), @"%@", problem);
    }
    QLMSnapshot *stopped = QLMSnapshotWith(QLMHandBackLouder, @(-10), @(-50));
    stopped.running = NO;
    XCTAssertFalse(QLMStopMayRaiseLevel(stopped));
}

// An adapter that stopped answering is still qlm's, and its take-over may
// be louder. PR #49 keeps its knob reading for this.
- (void)testAStopWithTheAdaptersProblemMayStillRaiseTheLevel {
    for (NSNumber *problem in @[@(QLMAdapterProblemUnresponsive), @(QLMAdapterProblemLostTrack)]) {
        QLMSnapshot *louder = QLMSnapshotWith(QLMHandBackLouder, @(-10), @(-50));
        louder.busProblem = QLMBusProblemNoAdapter;
        louder.adapterProblem = problem.integerValue;
        XCTAssertTrue(QLMStopMayRaiseLevel(louder), @"%@", problem);
        QLMSnapshot *quieter = QLMSnapshotWith(QLMHandBackKnobLevel, @(-60), @(-50));
        quieter.busProblem = QLMBusProblemNoAdapter;
        quieter.adapterProblem = problem.integerValue;
        XCTAssertFalse(QLMStopMayRaiseLevel(quieter), @"%@", problem);
    }
}

- (void)testTheRiseTextSaysWhy {
    XCTAssertEqualObjects(QLMStopRiseText(QLMSnapshotWith(QLMHandBackLouder, @(-10), @(-50))),
                          @"The knob reads −10.0 dB, above qlm's −50.0 dB. At the take-over, the level would rise 40.0 dB.");
    XCTAssertEqualObjects(QLMStopRiseText(QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50))),
                          @"No knob is in, so the level at the take-over is unknown.");
    QLMSnapshot *unread = QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50));
    unread.adapter.hasStatus = NO;
    XCTAssertEqualObjects(QLMStopRiseText(unread), @"qlm has not read the knob yet, so the level at the take-over is unknown.");
    XCTAssertEqualObjects(QLMStopRiseText(QLMSnapshotWith(QLMHandBackUnknown, @(-10), nil)),
                          @"qlm has set no level, so the level at the take-over is unknown.");
}

#pragma mark - The banner

// PR #49: read adapterProblem before busProblem, which is NoAdapter while
// it is set. Each says what to do, and what the take-over does.
- (void)testTheBannerShowsTheAdaptersProblem {
    QLMSnapshot *unresponsive = QLMSnapshotWith(QLMHandBackLouder, @(-10), @(-50));
    unresponsive.busProblem = QLMBusProblemNoAdapter;
    unresponsive.adapterProblem = QLMAdapterProblemUnresponsive;
    XCTAssertEqualObjects(QLMBusProblemTitle(unresponsive), @"The adapter stopped answering");
    NSString *detail = QLMBusProblemDetail(unresponsive);
    XCTAssertTrue([detail containsString:@"about 7 s"], @"%@", detail);
    XCTAssertTrue([detail containsString:QLMStopRiseText(unresponsive)], @"%@", detail);

    QLMSnapshot *lost = QLMSnapshotWith(QLMHandBackKnobLevel, @(-60), @(-50));
    lost.busProblem = QLMBusProblemNoAdapter;
    lost.adapterProblem = QLMAdapterProblemLostTrack;
    XCTAssertEqualObjects(QLMBusProblemTitle(lost), @"qlm lost track of the adapter");
    detail = QLMBusProblemDetail(lost);
    XCTAssertTrue([detail containsString:@"Unplug the adapter"], @"%@", detail);
    XCTAssertTrue([detail containsString:@"at or below qlm's"], @"%@", detail);
}

- (void)testTheBannerShowsTheBusProblemOtherwise {
    QLMSnapshot *snapshot = QLMSnapshotWith(QLMHandBackUnknown, nil, nil);
    XCTAssertNil(QLMBusProblemTitle(snapshot));
    XCTAssertNil(QLMBusProblemTitle(nil));
    snapshot.busProblem = QLMBusProblemNoAdapter;
    XCTAssertEqualObjects(QLMBusProblemTitle(snapshot), @"No adapter");
    XCTAssertEqualObjects(QLMBusProblemDetail(snapshot), @"Connect the GLM adapter by USB.");
    snapshot.busProblem = QLMBusProblemGLM;
    XCTAssertEqualObjects(QLMBusProblemTitle(snapshot), @"GLM has the adapter");
}

@end
