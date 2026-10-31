#import <XCTest/XCTest.h>

#import "QLMControl.h"
#import "QLMPreferences.h"
#import "QLMSystem.h"

// The app's preferences, over a defaults domain of the test's own.
@interface QLMPreferencesTests : XCTestCase
@end

@implementation QLMPreferencesTests {
    NSUserDefaults *_defaults;
    QLMPreferences *_preferences;
}

- (void)setUp {
    [super setUp];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:NSStringFromClass([self class])];
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    _preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
}

- (void)tearDown {
    [_defaults removePersistentDomainForName:NSStringFromClass([self class])];
    [super tearDown];
}

#pragma mark - The ceiling

// The default is qlmctl's highest without --allow-high-ceiling, in System
// and in the app.
- (void)testTheDefaultCeilingIsQlmctlsHighest {
    XCTAssertEqual([[QLMSystemSettings alloc] init].ceilingDecibels, QLMCeilingLimit);
    XCTAssertEqual(_preferences.ceilingDecibels, QLMCeilingLimit);
}

// A ceiling the user saved stays, above the default or below it.
- (void)testASavedCeilingStays {
    for (NSNumber *saved in @[@(-20), @(-45)]) {
        _preferences.ceilingDecibels = saved.doubleValue;
        QLMPreferences *relaunched = [[QLMPreferences alloc] initWithDefaults:_defaults];
        XCTAssertEqual(relaunched.ceilingDecibels, saved.doubleValue);
    }
}

@end
