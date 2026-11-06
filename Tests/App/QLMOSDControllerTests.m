#import <XCTest/XCTest.h>

#import "QLMOSDController.h"
#import "QLMSkinLibrary.h"
#import "QLMSnapshotInternal.h"
#import "QLMTestSupport.h"

@interface QLMOSDController (QLMTesting)
- (void)fade;
@property (nonatomic) BOOL fading;
@end

// The OSD holds while the knob turns, then fades. A turn during the fade
// shows it again, and its hold ends in a fade too, not a cut.
@interface QLMOSDControllerTests : XCTestCase
@end

@implementation QLMOSDControllerTests {
    NSUserDefaults *_defaults;
    QLMOSDController *_osd;
}

- (void)setUp {
    [super setUp];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:NSStringFromClass([self class])];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    QLMPreferences *preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
    preferences.osdSeconds = QLMOSDSecondsMin;
    _osd = [[QLMOSDController alloc] initWithPreferences:preferences skin:QLMBuiltInSkin(@"modern")];
}

- (void)tearDown {
    [_osd hide];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    [super tearDown];
}

- (QLMSnapshot *)snapshotAt:(double)decibels {
    QLMSnapshot *snapshot = [[QLMSnapshot alloc] init];
    snapshot.running = YES;
    snapshot.volumeDecibels = @(decibels);
    return snapshot;
}

- (void)runFor:(NSTimeInterval)seconds {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (void)testATurnDuringTheFadeEndsInAFade {
    XCTAssertNil([_osd showSnapshot:[self snapshotAt:-40]]);
    [_osd fade];
    XCTAssertTrue(_osd.fading);
    XCTAssertNil([_osd showSnapshot:[self snapshotAt:-41]]);
    XCTAssertTrue(_osd.showing, @"shown again");
    [self runFor:QLMOSDSecondsMin + 0.1];
    XCTAssertTrue(_osd.fading, @"the hold ended in a fade");
}

// Each step of a turn moves the hold's end.
- (void)testATurnThatGoesOnHolds {
    XCTAssertNil([_osd showSnapshot:[self snapshotAt:-40]]);
    for (int i = 0; i < 4; i++) {
        [self runFor:QLMOSDSecondsMin / 2];
        XCTAssertNil([_osd showSnapshot:[self snapshotAt:-41 - i]]);
    }
    XCTAssertTrue(_osd.showing);
    XCTAssertFalse(_osd.fading);
}

@end
