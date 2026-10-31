#import <XCTest/XCTest.h>

#import "QLMFormat.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

// A running System's snapshot on the real adapter, with the knob and qlm's
// level as given. A nil knob was never read, or no knob is in.
static QLMSnapshot *QLMSnapshotWith(QLMHandBackKind kind, NSNumber *_Nullable knob, NSNumber *_Nullable volume) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.adapter.hasStatus = YES;
    snapshot.handBack = QLMMakeHandBack(kind, knob, volume);
    return snapshot;
}

// The same, with an adapter that is open but no use. busProblem is
// NoAdapter meanwhile.
static QLMSnapshot *QLMSnapshotWithProblem(QLMAdapterProblem problem, QLMHandBackKind kind, NSNumber *knob, NSNumber *volume) {
    QLMSnapshot *snapshot = QLMSnapshotWith(kind, knob, volume);
    snapshot.busProblem = QLMBusProblemNoAdapter;
    snapshot.adapterProblem = problem;
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
        QLMAdapterProblem adapterProblem = problem.integerValue;
        XCTAssertTrue(QLMStopMayRaiseLevel(QLMSnapshotWithProblem(adapterProblem, QLMHandBackLouder, @(-10), @(-50))), @"%@", problem);
        XCTAssertFalse(QLMStopMayRaiseLevel(QLMSnapshotWithProblem(adapterProblem, QLMHandBackKnobLevel, @(-60), @(-50))), @"%@", problem);
    }
}

// The knob is read before the level, as in qlmctl's note.
- (void)testTheTakeOverTextSaysWhy {
    XCTAssertEqualObjects(QLMTakeOverText(QLMSnapshotWith(QLMHandBackLouder, @(-10), @(-50))),
                          @"The knob reads −10.0 dB, above qlm's −50.0 dB. At the take-over, the level would rise 40.0 dB.");
    XCTAssertEqualObjects(QLMTakeOverText(QLMSnapshotWith(QLMHandBackKnobLevel, @(-60), @(-50))),
                          @"The knob reads −60.0 dB, at or below qlm's −50.0 dB. At the take-over, the level would not rise.");
    XCTAssertEqualObjects(QLMTakeOverText(QLMSnapshotWith(QLMHandBackUnknown, nil, nil)),
                          @"The level at the take-over is unknown, since no knob is in.");
    QLMSnapshot *unread = QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50));
    unread.adapter.hasStatus = NO;
    XCTAssertEqualObjects(QLMTakeOverText(unread), @"The level at the take-over is unknown, since qlm has not read the knob yet.");
    XCTAssertEqualObjects(QLMTakeOverText(QLMSnapshotWith(QLMHandBackUnknown, @(-10), nil)),
                          @"The level at the take-over is unknown, since qlm has set no level.");
}

// Settings' line says the same, from the adapter's first status on.
- (void)testSettingsLineSaysTheSame {
    XCTAssertEqualObjects(QLMHandBackLine(QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50))),
                          @"Now: the level at the take-over is unknown, since no knob is in.");
    QLMSnapshot *unread = QLMSnapshotWith(QLMHandBackUnknown, nil, @(-50));
    unread.adapter.hasStatus = NO;
    XCTAssertNil(QLMHandBackLine(unread));
    XCTAssertNil(QLMHandBackLine(nil));
}

#pragma mark - Names

// In qlm-app-first, the user couldn't tell the Left 8351B from the Right by
// serial. The setup file names each device, matched by hardware ID.
- (void)testAMonitorIsNamedAsTheSetupNamesIt {
    QLMSetup *setup = QLMReadFixtureSetup();
    QLMMonitorState *left = [[QLMMonitorState alloc] init];
    left.hardwareID = setup.devices[0].hardwareID;
    left.serialNumber = @"8351BP21002711";
    XCTAssertEqualObjects(QLMMonitorLabel(left, setup), @"Left");
    XCTAssertEqualObjects(QLMMonitorLabel(left, nil), @"8351BP21002711");

    const uint8_t unknown[3] = {0x01, 0x02, 0x03};
    QLMMonitorState *stranger = [[QLMMonitorState alloc] init];
    stranger.hardwareID = QLMBytes(unknown, sizeof unknown);
    XCTAssertNil(QLMMonitorLabel(stranger, setup));
    stranger.serialNumber = @"8320APM21001234";
    XCTAssertEqualObjects(QLMMonitorLabel(stranger, setup), @"8320APM21001234");
}

#pragma mark - The banner

// PR #49: read adapterProblem before busProblem, which is NoAdapter while
// it is set. Each says what to do, and what the take-over does.
- (void)testTheBannerShowsTheAdaptersProblem {
    QLMSnapshot *unresponsive = QLMSnapshotWithProblem(QLMAdapterProblemUnresponsive, QLMHandBackLouder, @(-10), @(-50));
    XCTAssertEqualObjects(QLMBusProblemTitle(unresponsive), @"The adapter stopped answering");
    NSString *detail = QLMBusProblemDetail(unresponsive);
    XCTAssertTrue([detail containsString:@"about 7 s"], @"%@", detail);
    XCTAssertTrue([detail containsString:QLMTakeOverText(unresponsive)], @"%@", detail);

    QLMSnapshot *lost = QLMSnapshotWithProblem(QLMAdapterProblemLostTrack, QLMHandBackKnobLevel, @(-60), @(-50));
    XCTAssertEqualObjects(QLMBusProblemTitle(lost), @"qlm lost track of the adapter");
    detail = QLMBusProblemDetail(lost);
    XCTAssertTrue([detail containsString:@"Unplug the adapter"], @"%@", detail);
    XCTAssertTrue([detail containsString:QLMTakeOverText(lost)], @"%@", detail);
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

#pragma mark - A typed level

// 0 dB is the monitors' full level. Settings once clamped a level above it,
// so 35, typed for −35, made the loudest ceiling.
- (void)testALevelAboveFullLevelIsRefused {
    XCTAssertEqualObjects(QLMTypedLevelRefusal(35), @"35 dB is above 0 dB, the monitors' full level.");
    XCTAssertEqualObjects(QLMTypedLevelRefusal(0.04), @"0.04 dB is above 0 dB, the monitors' full level.");
    XCTAssertNil(QLMTypedLevelRefusal(0));
    XCTAssertNil(QLMTypedLevelRefusal(-35));
}

// Settings' fields refuse what the rule refuses, and an empty field, which
// read as 0 dB. The preferences bound every level they take.
- (void)testTheLevelFieldsRefuseALevelAboveFullLevelAndAnEmptyField {
    QLMDecibelsFormatter *formatter = [[QLMDecibelsFormatter alloc] init];
    NSDictionary<NSString *, NSString *> *refused = @{
        @"35": QLMTypedLevelRefusal(35),
        @"+3": QLMTypedLevelRefusal(3),
        @"0.04": QLMTypedLevelRefusal(0.04),
        @"1e3": QLMTypedLevelRefusal(1000),
        @"": @"Type a level in dB.",
    };
    for (NSString *text in refused) {
        id value = nil;
        NSString *error = nil;
        XCTAssertFalse([formatter getObjectValue:&value forString:text errorDescription:&error], @"%@", text);
        XCTAssertNil(value, @"%@", text);
        XCTAssertEqualObjects(error, refused[text], @"%@", text);
    }
    XCTAssertFalse([formatter getObjectValue:NULL forString:@"abc" errorDescription:NULL]);

    NSDictionary<NSString *, NSNumber *> *taken = @{@"−35": @(-35), @"-35": @(-35), @"−35.5": @(-35.5), @"0": @0};
    for (NSString *text in taken) {
        id value = nil;
        XCTAssertTrue([formatter getObjectValue:&value forString:text errorDescription:NULL], @"%@", text);
        XCTAssertEqualObjects(value, taken[text], @"%@", text);
    }
}

@end
