#import <XCTest/XCTest.h>

#import "QLMFormat.h"
#import "QLMSettingsTesting.h"
#import "QLMSettingsWindowController.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

static BOOL QLMTestSettingsSeen;

static BOOL QLMTestSettingsIsSeen(NSWindow *window) {
    return QLMTestSettingsSeen;
}

// Settings draws a snapshot only while it is seen, and catches up as it
// comes into view. Its live line changes with every step of the knob, and
// lays the window out again only when the line's height changes.
@interface QLMSettingsWindowControllerTests : XCTestCase
@end

@implementation QLMSettingsWindowControllerTests {
    NSUserDefaults *_defaults;
    QLMMonitorList *_list;
    QLMSettingsWindowController *_settings;
    BOOL (*_wasSeen)(NSWindow *);
}

- (void)setUp {
    [super setUp];
    _wasSeen = QLMSettingsWindowIsSeen;
    QLMSettingsWindowIsSeen = QLMTestSettingsIsSeen;
    QLMTestSettingsSeen = NO;
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:NSStringFromClass([self class])];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    _list = [[QLMMonitorList alloc] init];
    _settings = [[QLMSettingsWindowController alloc] initWithPreferences:[[QLMPreferences alloc] initWithDefaults:_defaults]
                                                             monitorList:_list];
}

- (void)tearDown {
    QLMSettingsWindowIsSeen = _wasSeen;
    [_settings close];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    [super tearDown];
}

- (void)showKnobAt:(double)knob {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    QLMAdapterState *adapter = [[QLMAdapterState alloc] init];
    adapter.hasStatus = YES;
    snapshot.adapter = adapter;
    snapshot.handBack = QLMMakeHandBack(QLMHandBackLouder, @(knob), @(-40));
    [_list updateWithSnapshot:snapshot];
}

- (NSString *)line {
    return [[_settings valueForKey:@"handBackLevel"] stringValue];
}

- (void)testItDrawsNothingWhileNotSeenAndCatchesUpInView {
    [self showKnobAt:-30];
    [_settings refresh];
    XCTAssertEqualObjects(self.line, @"", @"not seen");

    QLMTestSettingsSeen = YES;
    [(id<NSWindowDelegate>)_settings windowDidChangeOcclusionState:
        [NSNotification notificationWithName:NSWindowDidChangeOcclusionStateNotification object:_settings.window]];
    XCTAssertEqualObjects(self.line, QLMHandBackLine(_list.snapshot), @"caught up in view");

    [self showKnobAt:-31];
    [_settings refresh];
    XCTAssertEqualObjects(self.line, QLMHandBackLine(_list.snapshot));
}

// A step changes the line's text, not its height, so the window keeps its
// size and its layout.
- (void)testAStepKeepsTheLinesHeight {
    QLMTestSettingsSeen = YES;
    [self showKnobAt:-30];
    [_settings refresh];
    NSView *box = [_settings valueForKey:@"handBackBox"];
    [_settings.window layoutIfNeeded];
    CGFloat height = box.frame.size.height;
    XCTAssertGreaterThan(height, 0);
    [self showKnobAt:-29.5];
    [_settings refresh];
    XCTAssertFalse(_settings.window.contentView.needsLayout, @"a step lays nothing out");
    XCTAssertEqual(box.frame.size.height, height);
}

@end
