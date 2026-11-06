#import <XCTest/XCTest.h>

#import "QLMReadoutThrottle.h"

// The owner's rule: a number readout changes at most four times a second.
// The first change shows at once, and the last always shows within 250 ms.
// A change marked at once, as to MUTED, shows at once. On a clock the test
// turns.
@interface QLMReadoutThrottleTests : XCTestCase
@end

@implementation QLMReadoutThrottleTests {
    NSTimeInterval _now;
    NSMutableArray<NSString *> *_shown;
    NSMutableArray<NSNumber *> *_shownAt;
    NSMutableArray<NSArray *> *_timers;  // [fire time, block]
    QLMReadoutThrottle *_throttle;
}

- (void)setUp {
    [super setUp];
    _now = 100;
    _shown = [NSMutableArray array];
    _shownAt = [NSMutableArray array];
    _timers = [NSMutableArray array];
    __weak QLMReadoutThrottleTests *weakSelf = self;
    _throttle = [[QLMReadoutThrottle alloc] initWithShow:^(NSString *text) {
        QLMReadoutThrottleTests *strongSelf = weakSelf;
        [strongSelf->_shown addObject:text];
        [strongSelf->_shownAt addObject:@(strongSelf->_now)];
    }];
    _throttle.now = ^NSTimeInterval {
        QLMReadoutThrottleTests *strongSelf = weakSelf;
        return strongSelf != nil ? strongSelf->_now : 0;
    };
    _throttle.schedule = ^(NSTimeInterval delay, dispatch_block_t block) {
        QLMReadoutThrottleTests *strongSelf = weakSelf;
        [strongSelf->_timers addObject:@[@(strongSelf->_now + delay), block]];
    };
}

// Moves the clock, firing each timer due on the way.
- (void)advanceTo:(NSTimeInterval)time {
    for (;;) {
        NSArray *due = nil;
        for (NSArray *timer in _timers) {
            if ([timer[0] doubleValue] <= time && (due == nil || [timer[0] doubleValue] < [due[0] doubleValue])) {
                due = timer;
            }
        }
        if (due == nil) {
            break;
        }
        [_timers removeObject:due];
        _now = [due[0] doubleValue];
        ((dispatch_block_t)due[1])();
    }
    _now = time;
}

- (void)testTheFirstChangeShowsAtOnce {
    [_throttle showText:@"−40.0" atOnce:NO];
    XCTAssertEqualObjects(_shown, @[@"−40.0"]);
    [self advanceTo:101];
    [_throttle showText:@"−41.0" atOnce:NO];
    XCTAssertEqualObjects(_shown, (@[@"−40.0", @"−41.0"]), @"after a quiet interval, at once");
    XCTAssertEqual(_timers.count, 0u, @"nothing scheduled while nothing waits");
}

// A turn at 20 steps a second for 2 s shows at most 4 times a second, and
// its last level within 250 ms of the last step.
- (void)testATurnShowsFourTimesASecondAndItsLastLevel {
    NSString *last = nil;
    for (int i = 0; i < 40; i++) {
        [self advanceTo:100 + i * 0.05];
        last = [NSString stringWithFormat:@"−%d.0", 40 + i];
        [_throttle showText:last atOnce:NO];
    }
    NSTimeInterval lastStep = _now;
    [self advanceTo:lastStep + 1];
    XCTAssertEqualObjects(_shown.firstObject, @"−40.0");
    XCTAssertEqualObjects(_shown.lastObject, last);
    XCTAssertLessThanOrEqual([_shownAt.lastObject doubleValue] - lastStep, 0.25 + 1e-9);
    for (NSUInteger i = 1; i < _shownAt.count; i++) {
        XCTAssertGreaterThanOrEqual(_shownAt[i].doubleValue - _shownAt[i - 1].doubleValue, 0.25 - 1e-9, @"show %lu", (unsigned long)i);
    }
    XCTAssertLessThanOrEqual(_shown.count, 10u);
    XCTAssertEqual(_timers.count, 0u);
}

// Muted, or dimmed, shows at once, and a level waiting from before never
// shows over it.
- (void)testAChangeMarkedAtOnceShowsAtOnce {
    [_throttle showText:@"OUTPUT −40.0" atOnce:NO];
    [self advanceTo:100.05];
    [_throttle showText:@"OUTPUT −41.0" atOnce:NO];
    XCTAssertEqual(_shown.count, 1u, @"the level waits its turn");
    [self advanceTo:100.1];
    [_throttle showText:@"MUTED" atOnce:YES];
    XCTAssertEqualObjects(_shown.lastObject, @"MUTED");
    [self advanceTo:101];
    XCTAssertEqualObjects(_shown, (@[@"OUTPUT −40.0", @"MUTED"]));
    [_throttle showText:@"OUTPUT −61.0" atOnce:YES];
    XCTAssertEqualObjects(_shown.lastObject, @"OUTPUT −61.0");
}

// A level that comes back to the one shown cancels what waits.
- (void)testAReturnToTheShownTextShowsNothing {
    [_throttle showText:@"−40.0" atOnce:NO];
    [_throttle showText:@"−41.0" atOnce:NO];
    [_throttle showText:@"−40.0" atOnce:NO];
    [self advanceTo:101];
    XCTAssertEqualObjects(_shown, @[@"−40.0"]);
}

- (void)testAFlushShowsAtOnce {
    [_throttle showText:@"−40.0" atOnce:NO];
    [_throttle showText:@"−41.0" atOnce:NO];
    [_throttle flush];
    XCTAssertEqualObjects(_shown.lastObject, @"−41.0");
    [self advanceTo:101];
    XCTAssertEqual(_shown.count, 2u, @"nothing left to show");
}

@end
