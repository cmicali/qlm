#import <XCTest/XCTest.h>

#import "QLMMonitorList.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

// The list keeps every monitor System drops, offline, until System runs on
// another bus.
@interface QLMMonitorListTests : XCTestCase
@end

@implementation QLMMonitorListTests

- (void)testADroppedMonitorStaysOffline {
    QLMMonitorList *list = [[QLMMonitorList alloc] init];
    QLMMonitorState *left = QLMMakeMonitor(0x11, 0x02, QLMMonitorStatusOn);
    QLMMonitorState *right = QLMMakeMonitor(0x11, 0x03, QLMMonitorStatusOn);
    [list updateWithSnapshot:QLMMakeRunningSnapshot(@[left, right])];
    [list updateWithSnapshot:QLMMakeRunningSnapshot(@[left])];
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
    [list updateWithSnapshot:QLMMakeRunningSnapshot(@[QLMMakeMonitor(0x11, 0x02, QLMMonitorStatusOn), QLMMakeMonitor(0x11, 0x03, QLMMonitorStatusOn)])];
    [list forgetMonitors];
    QLMMonitorState *real = QLMMakeMonitor(0x0F, 0x02, QLMMonitorStatusOn);
    [list updateWithSnapshot:QLMMakeRunningSnapshot(@[real])];
    XCTAssertEqual(list.entries.count, 1u);
    XCTAssertEqualObjects(list.entries.firstObject.state, real);
    XCTAssertEqual(list.dropped.count, 0u);
}

@end
