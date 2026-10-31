#import <XCTest/XCTest.h>

#import "QLMMonitorList.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

static QLMMonitorState *QLMMonitorWithID(uint8_t first, uint8_t session) {
    const uint8_t hardwareID[3] = {first, 0x4B, session};
    QLMMonitorState *monitor = [[QLMMonitorState alloc] init];
    monitor.hardwareID = QLMBytes(hardwareID, sizeof hardwareID);
    monitor.session = session;
    monitor.status = QLMMonitorStatusOn;
    return monitor;
}

static QLMSnapshot *QLMRunningWith(NSArray<QLMMonitorState *> *monitors) {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.monitors = monitors;
    return snapshot;
}

// The list keeps every monitor System drops, offline, until System runs on
// another bus.
@interface QLMMonitorListTests : XCTestCase
@end

@implementation QLMMonitorListTests

- (void)testADroppedMonitorStaysOffline {
    QLMMonitorList *list = [[QLMMonitorList alloc] init];
    QLMMonitorState *left = QLMMonitorWithID(0x11, 0x02);
    QLMMonitorState *right = QLMMonitorWithID(0x11, 0x03);
    [list updateWithSnapshot:QLMRunningWith(@[left, right])];
    [list updateWithSnapshot:QLMRunningWith(@[left])];
    XCTAssertEqual(list.entries.count, 2u);
    XCTAssertEqual(list.entries[1].presence, QLMMonitorPresenceOffline);
    XCTAssertEqualObjects(list.dropped, @[right]);
}

// In qlm-app-first, the fake bus's three monitors stayed in the list as
// offline once the adapter setting went on (captures/qlm-app-first/notes.md,
// Surprises). A new bus's list starts empty, and drops none of the old
// bus's monitors.
- (void)testAnotherBusForgetsTheMonitorsSeen {
    QLMMonitorList *list = [[QLMMonitorList alloc] init];
    [list updateWithSnapshot:QLMRunningWith(@[QLMMonitorWithID(0x11, 0x02), QLMMonitorWithID(0x11, 0x03)])];
    [list forgetMonitors];
    QLMMonitorState *real = QLMMonitorWithID(0x0F, 0x02);
    [list updateWithSnapshot:QLMRunningWith(@[real])];
    XCTAssertEqual(list.entries.count, 1u);
    XCTAssertEqualObjects(list.entries.firstObject.state, real);
    XCTAssertEqual(list.dropped.count, 0u);
}

@end
