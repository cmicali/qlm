#import <XCTest/XCTest.h>

#import "QLMFrameCoalescer.h"

// The windows draw a snapshot once a main-queue turn at most: only the
// newest, and nothing while none waits. The test hands out the turns.
@interface QLMFrameCoalescerTests : XCTestCase
@end

@implementation QLMFrameCoalescerTests {
    NSMutableArray<NSString *> *_applied;
    NSMutableArray<dispatch_block_t> *_frames;  // asked for, not yet fired
    QLMFrameCoalescer<NSString *> *_coalescer;
}

- (void)setUp {
    [super setUp];
    _applied = [NSMutableArray array];
    _frames = [NSMutableArray array];
    NSMutableArray<NSString *> *applied = _applied;
    NSMutableArray<dispatch_block_t> *frames = _frames;
    _coalescer = [[QLMFrameCoalescer alloc] initWithApply:^(NSString *value) {
        [applied addObject:value];
    }];
    _coalescer.requestFrame = ^(dispatch_block_t fire) {
        [frames addObject:fire];
    };
}

- (void)fireFrame {
    dispatch_block_t fire = _frames.firstObject;
    [_frames removeObjectAtIndex:0];
    fire();
}

- (void)testABurstAppliesOnlyTheNewestAtTheNextFrame {
    for (NSString *value in @[@"a", @"b", @"c"]) {
        [_coalescer submit:value];
    }
    XCTAssertEqual(_applied.count, 0u, @"nothing before the frame");
    XCTAssertEqual(_frames.count, 1u, @"one frame asked for");
    [self fireFrame];
    XCTAssertEqualObjects(_applied, @[@"c"]);
    XCTAssertFalse(_coalescer.pending);
}

- (void)testAtMostOneAppliesAFrame {
    [_coalescer submit:@"a"];
    [self fireFrame];
    [_coalescer submit:@"b"];
    [_coalescer submit:@"c"];
    XCTAssertEqualObjects(_applied, @[@"a"], @"the next waits for its own frame");
    XCTAssertEqual(_frames.count, 1u);
    [self fireFrame];
    XCTAssertEqualObjects(_applied, (@[@"a", @"c"]));
}

- (void)testNothingIsAskedForWhileNothingWaits {
    XCTAssertEqual(_frames.count, 0u);
    [_coalescer submit:@"a"];
    [self fireFrame];
    XCTAssertEqual(_frames.count, 0u, @"no frame asked for after the last");
    XCTAssertFalse(_coalescer.pending);
}

// A verb that reads the windows applies what waits at once. The frame then
// finds nothing.
- (void)testAFlushAppliesAtOnce {
    [_coalescer submit:@"a"];
    [_coalescer flush];
    XCTAssertEqualObjects(_applied, @[@"a"]);
    [self fireFrame];
    XCTAssertEqualObjects(_applied, @[@"a"]);
    [_coalescer flush];
    XCTAssertEqualObjects(_applied, @[@"a"]);
}

// By default the next main-queue turn applies it.
- (void)testTheMainQueuesNextTurnApplies {
    QLMFrameCoalescer<NSString *> *coalescer = [[QLMFrameCoalescer alloc] initWithApply:^(NSString *value) {
        [self->_applied addObject:value];
    }];
    [coalescer submit:@"a"];
    [coalescer submit:@"b"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (_applied.count == 0 && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertEqualObjects(_applied, @[@"b"]);
}

@end
