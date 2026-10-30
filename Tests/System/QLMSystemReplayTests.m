#import "QLMTestSupport.h"

#import "QLMReplayAdapter.h"
#import "QLMSystem.h"

// Sources: captures/startup-idle, where GLM finds the user's six monitors:
// two 8330A, two 8351B, a 7370A, and a 7350A, all on. System's discovery
// sends what GLM sent, in GLM's lease order, so the replay answers it.
@interface QLMSystemReplayTests : XCTestCase
@end

@implementation QLMSystemReplayTests

- (void)testDiscoversEveryMonitorInStartupIdle {
    NSError *error = nil;
    QLMCapture *capture = QLMReadCapture(@"startup-idle", &error);
    XCTAssertNotNil(capture, @"%@", error);
    QLMReplayAdapter *adapter = [[QLMReplayAdapter alloc] initWithCapture:capture];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.cycleInterval = 0.05;
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:adapter settings:settings];

    XCTestExpectation *expectation = [self expectationWithDescription:@"discovery"];
    __block QLMSnapshot *found = nil;
    [system setSnapshotHandler:^(QLMSnapshot *snapshot) {
        BOOL known = snapshot.monitors.count == 6 && snapshot.allIdentified;
        for (QLMMonitorState *monitor in snapshot.monitors) {
            known = known && monitor.deviceClass != QLMMonitorClassUnknown;
        }
        if (found == nil && known) {
            found = snapshot;
            [expectation fulfill];
        }
    } queue:dispatch_queue_create("qlm.tests.snapshots", DISPATCH_QUEUE_SERIAL)];
    [system start];
    [self waitForExpectations:@[expectation] timeout:10];
    [system stop];

    NSDictionary<NSString *, NSArray *> *expected = @{
        @"8330A": @[@"1.14.7.6281", @(QLMMonitorClassTwoWay)],
        @"8351B": @[@"1.24.07.6470", @(QLMMonitorClassTwoWay)],
        @"7370A": @[@"1.14.7.6281", @(QLMMonitorClassSubwoofer)],
        @"7350A": @[@"1.14.7.6281", @(QLMMonitorClassSubwoofer)],
    };
    NSCountedSet<NSString *> *models = [NSCountedSet set];
    for (QLMMonitorState *monitor in found.monitors) {
        NSArray *facts = expected[monitor.model];
        XCTAssertNotNil(facts, @"%@", monitor.model);
        [models addObject:monitor.model ?: @""];
        XCTAssertEqualObjects(monitor.firmwareVersion, facts[0]);
        XCTAssertEqual(monitor.deviceClass, [facts[1] integerValue]);
        XCTAssertTrue([monitor.serialNumber hasPrefix:monitor.model], @"%@", monitor.serialNumber);
        XCTAssertEqual(monitor.status, QLMMonitorStatusOn);
        XCTAssertGreaterThan(monitor.temperature, 0);
    }
    XCTAssertEqual([models countForObject:@"8330A"], 2u);
    XCTAssertEqual([models countForObject:@"8351B"], 2u);
    XCTAssertEqual([models countForObject:@"7370A"], 1u);
    XCTAssertEqual([models countForObject:@"7350A"], 1u);
}

@end
