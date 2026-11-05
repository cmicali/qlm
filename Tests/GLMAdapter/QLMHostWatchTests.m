#import <XCTest/XCTest.h>

#import "QLMHostWatch.h"
#import "QLMTestSupport.h"

// The HID adapter's watch for another host, with its events played by the
// test, a check that counts its runs, and the virtual clock. The adapter
// refuses on each host found, as it did on the per-second watch's.
@interface QLMHostWatchTests : XCTestCase
@end

@implementation QLMHostWatchTests {
    dispatch_queue_t _queue;
    QLMVirtualClock *_clock;
    QLMHostWatch *_watch;
    NSString *_host;  // what the check finds
    NSUInteger _checks;
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
        return strongSelf->_host;
    } found:^(NSString *host) {
        QLMHostWatchTests *strongSelf = weakSelf;
        [strongSelf->_found addObject:host ?: NSNull.null];
    }];
    dispatch_sync(_queue, ^{
        [self->_watch start];
    });
}

- (void)tearDown {
    dispatch_sync(_queue, ^{
        [self->_watch stop];
    });
    [super tearDown];
}

// With no event, nothing runs until the fallback's interval.
- (void)testNoEventRunsNoCheck {
    [_clock advanceBy:QLMHostWatchFallbackInterval - 1];
    XCTAssertEqual(_checks, 0u);
    [_clock advanceBy:1];
    XCTAssertEqual(_checks, 1u);
    XCTAssertEqualObjects(_found, @[NSNull.null]);
}

// GLM's launch checks at once, and the host it finds goes to the adapter,
// which refuses.
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

// IOKit's message on the adapter checks at once, and a holder found goes to
// the adapter. A message with no holder answers nil, so the adapter may
// open again.
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

// A stop ends the watch: no event and no fallback checks after it.
- (void)testAStopEndsTheChecks {
    dispatch_sync(_queue, ^{
        [self->_watch stop];
    });
    [_watch adapterChanged];
    [_watch appChangedAtPath:@"/Applications/GLMv5.app/Contents/MacOS/GLMv5"];
    [_clock advanceBy:2 * QLMHostWatchFallbackInterval];
    XCTAssertEqual(_checks, 0u);
}

@end
