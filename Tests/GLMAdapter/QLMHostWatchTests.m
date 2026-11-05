#import <XCTest/XCTest.h>

#import "QLMHostWatch.h"
#import "QLMTestSupport.h"

// The HID adapter's watch for another host, with its events played by the
// test, checks that count their runs, and the virtual clock.
@interface QLMHostWatchTests : XCTestCase
@end

@implementation QLMHostWatchTests {
    dispatch_queue_t _queue;
    QLMVirtualClock *_clock;
    QLMHostWatch *_watch;
    NSString *_host;  // what the full check finds
    NSUInteger _checks;
    NSUInteger _clientChecks;
    void (^_duringCheck)(void);  // runs inside the next full check
    NSMutableArray *_found;  // each answer, NSNull for none
}

- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("QLMHostWatchTests", DISPATCH_QUEUE_SERIAL);
    _clock = [[QLMVirtualClock alloc] init];
    _found = [NSMutableArray array];
    __weak QLMHostWatchTests *weakSelf = self;
    _watch = [[QLMHostWatch alloc] initWithQueue:_queue clock:_clock check:^NSString * {
        QLMHostWatchTests *strongSelf = weakSelf;
        strongSelf->_checks += 1;
        void (^during)(void) = strongSelf->_duringCheck;
        strongSelf->_duringCheck = nil;
        if (during != nil) {
            during();
        }
        return strongSelf->_host;
    } clientCheck:^NSString * {
        QLMHostWatchTests *strongSelf = weakSelf;
        strongSelf->_clientChecks += 1;
        return nil;
    } found:^(NSString *host) {
        QLMHostWatchTests *strongSelf = weakSelf;
        [strongSelf->_found addObject:host ?: NSNull.null];
    }];
    [self onQueue:^{
        [self->_watch start];
    }];
}

- (void)tearDown {
    [self onQueue:^{
        [self->_watch stop];
    }];
    [super tearDown];
}

- (void)onQueue:(dispatch_block_t)block {
    dispatch_sync(_queue, block);
}

// With no event, only the client check runs, once a second, and the full
// check waits for the fallback, at each of its ticks.
- (void)testNoEventRunsOnlyTheClientCheck {
    [_clock advanceBy:QLMHostWatchFallbackInterval - 1];
    XCTAssertEqual(_checks, 0u);
    XCTAssertEqual(_clientChecks, (NSUInteger)(QLMHostWatchFallbackInterval - 1));
    [_clock advanceBy:1];
    XCTAssertEqual(_checks, 1u);
    [_clock advanceBy:2 * QLMHostWatchFallbackInterval];
    XCTAssertEqual(_checks, 3u);
}

// GLM's launch runs the full check at once, and the host it finds goes to
// the adapter, which refuses.
- (void)testAGLMLaunchChecks {
    _host = @"GLM is running (pid 4242, /Applications/GLMv5.app/Contents/MacOS/GLMv5). Quit GLM first.";
    [_watch appChangedAtPath:@"/Applications/GLMv5.app/Contents/MacOS/GLMv5"];
    [_clock settle];
    XCTAssertEqual(_checks, 1u);
    XCTAssertEqualObjects(_found, @[_host]);
}

// Another app's launch runs no check.
- (void)testAnotherLaunchChecksNothing {
    _host = @"GLM is running.";
    [_watch appChangedAtPath:@"/Applications/Logic Pro.app/Contents/MacOS/Logic Pro"];
    [_watch appChangedAtPath:@"/usr/local/bin/qlmctl"];
    [_clock settle];
    XCTAssertEqual(_checks, 0u);
    XCTAssertEqual(_found.count, 0u);
}

// IOKit's message on the adapter runs the full check at once, and a holder
// found goes to the adapter. One with no holder answers nil, so the adapter
// may open again.
- (void)testAnAdapterEventChecks {
    _host = @"MIDIServer (pid 906) holds the GLM adapter.";
    [_watch adapterChanged];
    [_clock settle];
    XCTAssertEqualObjects(_found, @[_host]);
    _host = nil;
    [_watch adapterChanged];
    [_clock settle];
    XCTAssertEqualObjects(_found, (@[@"MIDIServer (pid 906) holds the GLM adapter.", NSNull.null]));
    XCTAssertEqual(_checks, 2u);
}

// Events during a check may come after it read the state, so they run one
// more full check after it, however many came.
- (void)testEventsDuringACheckRunOneMore {
    __weak QLMHostWatch *watch = _watch;
    _duringCheck = ^{
        [watch adapterChanged];
        [watch adapterChanged];
        [watch appChangedAtPath:@"/Applications/GLMv5.app/Contents/MacOS/GLMv5"];
    };
    [_watch adapterChanged];
    [_clock settle];
    XCTAssertEqual(_checks, 2u);
    XCTAssertEqual(_found.count, 2u);
}

// A check in flight as the watch stops gives no answer.
- (void)testACheckInFlightAcrossAStopIsDropped {
    _host = @"GLM is running.";
    __weak QLMHostWatchTests *weakSelf = self;
    _duringCheck = ^{
        QLMHostWatchTests *strongSelf = weakSelf;
        [strongSelf onQueue:^{
            [strongSelf->_watch stop];
        }];
    };
    [_watch adapterChanged];
    [_clock settle];
    XCTAssertEqual(_checks, 1u);
    XCTAssertEqual(_found.count, 0u);
}

// A stop ends the watch: no event and no timer checks after it.
- (void)testAStopEndsTheChecks {
    [self onQueue:^{
        [self->_watch stop];
    }];
    [_watch adapterChanged];
    [_watch appChangedAtPath:@"/Applications/GLMv5.app/Contents/MacOS/GLMv5"];
    [_clock advanceBy:2 * QLMHostWatchFallbackInterval];
    XCTAssertEqual(_checks, 0u);
    XCTAssertEqual(_clientChecks, 0u);
}

@end
