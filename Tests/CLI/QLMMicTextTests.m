#import <XCTest/XCTest.h>

#import "QLMMicText.h"
#import "QLMReplayAdapter.h"
#import "QLMSnapshotInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"

// The mic as qlmctl's info and poll print it, from System on a replay. The
// readings' meaning is unconfirmed (docs/adapter-status.md), so they print as
// raw counts.
@interface QLMMicTextTests : XCTestCase
@end

@implementation QLMMicTextTests

// The adapter's state after GLM's first 01 08 in the scenario.
- (QLMAdapterState *)adapterAfterFirstPollOf:(NSString *)scenario {
    QLMVirtualClock *time = [[QLMVirtualClock alloc] init];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = time;
    settings.discoversMonitors = NO;
    settings.adapterPollInterval = 0;
    settings.adapterPollsPerRound = 1;
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:[[QLMReplayAdapter alloc] initWithCapture:QLMReadCapture(scenario, NULL)]
                                                  settings:settings];
    [system start];
    XCTAssertTrue([time runUntil:^BOOL {
        return system.snapshot.adapter.hasStatus;
    } within:60]);
    QLMAdapterState *adapter = system.snapshot.adapter;
    __block BOOL stopped = NO;
    [system stopWithCompletion:^{
        stopped = YES;
    }];
    XCTAssertTrue([time runUntil:^BOOL {
        return stopped;
    } within:60]);
    return adapter;
}

// captures/startup-idle-mic, 7.31 s: DE 1B AB FB A0, DD 00 22 4E 4F.
- (void)testPrintsTheReadingsWithTheMicIn {
    XCTAssertEqualObjects(QLMMicText([self adapterAfterFirstPollOf:@"startup-idle-mic"]), @"in, DE 464255904, DD 2248271");
}

// captures/startup-idle, 7.31 s: 33.
- (void)testPrintsNoneWithoutTheMic {
    XCTAssertEqualObjects(QLMMicText([self adapterAfterFirstPollOf:@"startup-idle"]), @"none");
}

- (void)testPrintsAQuestionMarkBeforeAStatus {
    XCTAssertEqualObjects(QLMMicText([[QLMAdapterState alloc] init]), @"?");
}

@end
