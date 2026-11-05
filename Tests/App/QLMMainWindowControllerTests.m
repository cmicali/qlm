#import <XCTest/XCTest.h>

#import "QLMFakeBus.h"
#import "QLMMainMenu.h"
#import "QLMMainWindowController.h"
#import "QLMSkinView.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

// The Controls menu, as the main window's controller answers it. Source:
// docs/ui.md, The menu. It acts only while the main window is open and
// key, so no other of qlm's windows, and no closed window, takes its keys.
@interface QLMMainWindowControllerTests : XCTestCase <QLMMainMenuActions>
@end

// The controller's own, for what the test window can't reach: it never
// becomes key, so the menu never acts.
@interface QLMMainWindowController (QLMTesting)
@property (nonatomic, readonly, nullable) QLMSkinView *skinView;
- (BOOL)canStepVolumeBy:(int)steps;
- (void)render;
@end

@implementation QLMMainWindowControllerTests {
    NSUserDefaults *_defaults;
    QLMMainWindowController *_controller;
    NSMenu *_controls;
    QLMMonitorList *_monitors;
}

- (void)showMainWindow:(id)sender {
}

- (void)showMonitors:(id)sender {
}

- (void)showSettings:(id)sender {
}

- (void)setUp {
    [super setUp];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:NSStringFromClass([self class])];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    QLMPreferences *preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
    // Every control's own rule would enable it: two monitors on, a level
    // set, and a System. TRAP: the System is never started, so nothing
    // reaches a bus.
    QLMMonitorList *monitors = [[QLMMonitorList alloc] init];
    [monitors updateWithSnapshot:QLMMakeTwoMonitorSnapshot()];
    _monitors = monitors;
    QLMSkin *skin = QLMBuiltInSkin(@"modern");
    _controller = [[QLMMainWindowController alloc] initWithPreferences:preferences monitorList:monitors skin:skin];
    _controller.system = [[QLMSystem alloc] initWithAdapter:[QLMFakeBus demoBusWithSubwoofer:NO]
                                                   settings:[[QLMSystemSettings alloc] init]];
    NSMenu *bar = QLMMainMenu(self, _controller);
    _controls = _controller.controlsMenu;
    XCTAssertEqualObjects([bar itemWithTitle:@"Controls"].submenu, _controls);
    QLMSetup *setup = QLMReadFixtureSetup();
    [_controller showSetup:setup fileName:@"fixture.sam" error:nil];
}

- (void)tearDown {
    [_controller close];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    [super tearDown];
}

- (NSArray<NSMenuItem *> *)controlItems {
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    for (NSMenuItem *item in _controls.itemArray) {
        if (item.action != NULL) {
            [items addObject:item];
        }
    }
    return items;
}

- (void)assertEveryControlDisabled:(NSString *)when {
    for (NSMenuItem *item in [self controlItems]) {
        XCTAssertFalse([_controller validateMenuItem:item], @"%@ %@", item.title, when);
    }
}

// One item per group the window shows, by the file's names and its order,
// on Cmd-1 up. Each names its group by its place, so two of one name stay
// apart.
- (void)testTheMenuListsTheWindowsGroups {
    NSArray<NSMenuItem *> *items = [self controlItems];
    NSMutableArray<NSMenuItem *> *groups = [NSMutableArray array];
    for (NSMenuItem *item in items) {
        if (item.action == @selector(chooseGroup:)) {
            [groups addObject:item];
        }
    }
    NSUInteger shown = MIN(QLMReadFixtureSetup().groupNames.count, 6u);
    XCTAssertEqual(groups.count, shown);
    for (NSUInteger i = 0; i < groups.count; i++) {
        XCTAssertEqualObjects(groups[i].title, QLMReadFixtureSetup().groupNames[i]);
        XCTAssertEqualObjects(groups[i].representedObject, @(i));
        XCTAssertEqualObjects(groups[i].keyEquivalent, ([NSString stringWithFormat:@"%lu", (unsigned long)i + 1]));
    }
    // A new setup puts its own in their place.
    [_controller showSetup:nil fileName:nil error:nil];
    for (NSMenuItem *item in _controls.itemArray) {
        XCTAssertNotEqual(item.action, @selector(chooseGroup:));
    }
}

- (void)testTheControlsTakeNothingWhileTheWindowIsClosed {
    XCTAssertFalse(_controller.showing);
    XCTAssertGreaterThan([self controlItems].count, 5u);
    [self assertEveryControlDisabled:@"with the window closed"];
}

// Shown but not key, as while Settings or Monitors has the keys.
- (void)testTheControlsTakeNothingWhileAnotherWindowIsKey {
    NSWindow *window = _controller.window;
    [window setFrameOrigin:NSMakePoint(-20000, -20000)];
    [window orderFrontRegardless];
    XCTAssertTrue(_controller.showing);
    XCTAssertFalse(window.isKeyWindow);
    [self assertEveryControlDisabled:@"with the window shown, not key"];
}

// The menu's Volume Up and Down step only from a level the monitors have:
// not while the level waits for the knob's reading, before one is known, or
// while System is stopped. The knob refuses the step too, by the same rule.
- (void)testTheVolumeStepsOnlyFromAKnownLevel {
    (void)_controller.window;
    XCTAssertTrue([_controller canStepVolumeBy:1]);
    XCTAssertTrue([_controller canStepVolumeBy:-1]);
    NSArray<void (^)(QLMSnapshot *)> *changes = @[
        ^(QLMSnapshot *snapshot) {
            snapshot.levelAwaitsKnob = YES;
        },
        ^(QLMSnapshot *snapshot) {
            snapshot.volumeDecibels = nil;
        },
        ^(QLMSnapshot *snapshot) {
            snapshot.running = NO;
        },
    ];
    for (NSUInteger i = 0; i < changes.count; i++) {
        QLMSnapshot *snapshot = QLMMakeTwoMonitorSnapshot();
        changes[i](snapshot);
        [_monitors updateWithSnapshot:snapshot];
        XCTAssertFalse([_controller canStepVolumeBy:1], @"change %lu", (unsigned long)i);
        XCTAssertFalse([_controller canStepVolumeBy:-1], @"change %lu", (unsigned long)i);
        [_controller render];
        XCTAssertFalse([_controller.skinView.knob canStepBy:1], @"change %lu", (unsigned long)i);
    }
    [_monitors updateWithSnapshot:QLMMakeTwoMonitorSnapshot()];
    [_controller render];
    XCTAssertTrue([_controller.skinView.knob canStepBy:1]);
}

// A disabled item still shows the snapshot's state, so no stale check
// shows while another window has the keys.
- (void)testADisabledItemShowsTheSnapshotsState {
    QLMSnapshot *snapshot = QLMMakeTwoMonitorSnapshot();
    snapshot.allMuted = YES;
    snapshot.anyOn = NO;
    [_monitors updateWithSnapshot:snapshot];
    for (NSMenuItem *item in [self controlItems]) {
        XCTAssertFalse([_controller validateMenuItem:item], @"%@", item.title);
        if (item.action == @selector(toggleMute:)) {
            XCTAssertEqual(item.state, NSControlStateValueOn);
        }
        if (item.action == @selector(togglePower:)) {
            XCTAssertEqualObjects(item.title, @"Wake");
        }
    }
}

@end
