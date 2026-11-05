#import <XCTest/XCTest.h>

#import <IOKit/hid/IOHIDKeys.h>

#import "QLMHIDAdapterInternal.h"
#import "QLMHostWatch.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"

static NSString *const QLMGLMHost = @"GLM is running (pid 4242, /Applications/GLMv5.app/Contents/MacOS/GLMv5). Quit GLM first.";

// Counts each try to open the adapter, which needs IOKit's service.
@interface QLMCountingHIDAdapter : QLMHIDAdapter
@property (nonatomic) QLMVirtualClock *clock;
@property (nonatomic) NSMutableArray<NSNumber *> *openTimes;
@end

@implementation QLMCountingHIDAdapter
- (void)openIfFree {
    [self.openTimes addObject:@(self.clock.now)];
}
@end

// The HID adapter's glue to its host watch, with stand-ins for IOKit and
// the checks. TRAP: its matching finds nothing, so no test reaches the
// real adapter, which may be plugged in.
@interface QLMHIDAdapterTests : XCTestCase
@end

@implementation QLMHIDAdapterTests {
    dispatch_queue_t _queue;
    QLMVirtualClock *_clock;
    QLMCountingHIDAdapter *_adapter;
    NSString *_host;
    NSUInteger _hostChecks;
    NSUInteger _clientChecks;
    NSMutableArray<NSString *> *_events;
    void (^_launched)(NSString *executablePath);
}

- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("QLMHIDAdapterTests", DISPATCH_QUEUE_SERIAL);
    _clock = [[QLMVirtualClock alloc] init];
    _events = [NSMutableArray array];
    QLMCountingHIDAdapter *adapter = [[QLMCountingHIDAdapter alloc] init];
    adapter.clock = _clock;
    adapter.openTimes = [NSMutableArray array];
    __weak QLMHIDAdapterTests *weakSelf = self;
    adapter.makeMatching = ^CFMutableDictionaryRef {
        return IOServiceMatching("QLMNoSuchService");
    };
    adapter.open = ^IOReturn(IOHIDDeviceRef device, IOOptionBits options) {
        return kIOReturnSuccess;
    };
    adapter.attach = ^NSString *(IOHIDDeviceRef device) {
        return @"the stand-in, seized";
    };
    adapter.close = ^(IOHIDDeviceRef device, BOOL removed) {
        QLMHIDAdapterTests *strongSelf = weakSelf;
        [strongSelf->_events addObject:removed ? @"cancel" : @"close"];
        CFRelease(device);
    };
    adapter.hostCheck = ^NSString * {
        QLMHIDAdapterTests *strongSelf = weakSelf;
        strongSelf->_hostChecks += 1;
        return strongSelf->_host;
    };
    adapter.clientCheck = ^NSString * {
        QLMHIDAdapterTests *strongSelf = weakSelf;
        strongSelf->_clientChecks += 1;
        return nil;
    };
    adapter.launchWatch = ^dispatch_block_t(void (^changed)(NSString *executablePath)) {
        QLMHIDAdapterTests *strongSelf = weakSelf;
        [strongSelf->_events addObject:@"watch launches"];
        strongSelf->_launched = changed;
        return ^{
            [weakSelf addEvent:@"end launch watch"];
        };
    };
    _adapter = adapter;
    [self onQueue:^{
        [adapter startOnQueue:self->_queue clock:self->_clock];
    }];
    // The start's own try, which finds no service.
    XCTAssertEqual(adapter.openTimes.count, 1u);
    [adapter.openTimes removeAllObjects];
}

- (void)tearDown {
    [self onQueue:^{
        [self->_adapter stop];
    }];
    [_clock settle];
    [super tearDown];
}

- (void)addEvent:(NSString *)event {
    [_events addObject:event];
}

- (void)onQueue:(dispatch_block_t)block {
    dispatch_sync(_queue, block);
}

// The adapter's start runs no check: its matching finds no adapter.
- (void)testAStartChecksNothing {
    [_clock settle];
    XCTAssertEqual(_hostChecks, 0u);
    XCTAssertEqual(_clientChecks, 0u);
    XCTAssertEqual(_adapter.openTimes.count, 0u);
}

// A host found closes the device at once, and every send fails as busy,
// naming the host.
- (void)testAHostFoundClosesTheDevice {
    __block NSError *refusal = nil;
    [self onQueue:^{
        refusal = [self->_adapter openDevice:(IOHIDDeviceRef)CFBridgingRetain([[NSObject alloc] init])];
    }];
    XCTAssertNil(refusal);
    XCTAssertTrue(_adapter.seized);
    [self onQueue:^{
        [self->_adapter finishCheck:QLMGLMHost];
    }];
    XCTAssertFalse(_adapter.seized);
    XCTAssertEqualObjects(_events, (@[@"watch launches", @"close"]));

    __block NSError *sent = nil;
    __block BOOL answered = NO;
    [self onQueue:^{
        [self->_adapter sendMessage:QLMCommandPoll(QLMAddressAdapter) replyHandler:^(const QLMMessage *reply, NSError *error) {
            sent = error;
            answered = YES;
        }];
    }];
    [self onQueue:^{
    }];
    XCTAssertTrue(answered);
    XCTAssertEqual(sent.code, QLMAdapterErrorBusy);
    XCTAssertEqualObjects(sent.localizedDescription, QLMGLMHost);
}

// IOKit's interest message runs the full check, and its host refuses.
- (void)testAnInterestMessageChecks {
    _host = QLMGLMHost;
    [self onQueue:^{
        [self->_adapter adapterChanged];
    }];
    [_clock settle];
    XCTAssertEqual(_hostChecks, 1u);
    XCTAssertEqual(_adapter.openTimes.count, 0u);
}

// The launch watch starts with the adapter and ends with its stop. GLM's
// launch runs the full check, and another app's runs none.
- (void)testTheLaunchWatchFollowsTheAdapter {
    XCTAssertEqualObjects(_events, @[@"watch launches"]);
    _launched(@"/Applications/Logic Pro.app/Contents/MacOS/Logic Pro");
    [_clock settle];
    XCTAssertEqual(_hostChecks, 0u);
    _launched(@"/Applications/GLMv5.app/Contents/MacOS/GLMv5");
    [_clock settle];
    XCTAssertEqual(_hostChecks, 1u);
    [self onQueue:^{
        [self->_adapter stop];
    }];
    XCTAssertEqualObjects(_events, (@[@"watch launches", @"end launch watch"]));
}

// Each second the client check runs, and only it. A check that finds no host
// opens the adapter if it is free.
- (void)testTheClientCheckRunsEachSecondAndReopens {
    [_clock advanceBy:3 * QLMHostWatchClientInterval];
    XCTAssertEqual(_clientChecks, 3u);
    XCTAssertEqual(_hostChecks, 0u);
    XCTAssertEqual(_adapter.openTimes.count, 3u);
}

// TRAP: qlm's own open and close send interest messages, so answers with no
// host could reopen in a loop. A reopen comes at most once a second after
// the last, and one held back comes on time.
- (void)testAReopenWaitsASecondAfterTheLast {
    [self onQueue:^{
        [self->_adapter finishCheck:nil];
        [self->_adapter finishCheck:nil];
        [self->_adapter finishCheck:nil];
    }];
    XCTAssertEqualObjects(_adapter.openTimes, @[@0]);
    [_clock advanceBy:0.5];
    [self onQueue:^{
        [self->_adapter finishCheck:nil];
    }];
    [_clock advanceBy:0.4];
    XCTAssertEqualObjects(_adapter.openTimes, @[@0]);
    [_clock advanceBy:0.1];
    XCTAssertEqual(_adapter.openTimes.count, 2u);
    XCTAssertEqualWithAccuracy(_adapter.openTimes[1].doubleValue, 1, 1e-9);
    [_clock advanceBy:2.5];
    for (NSUInteger i = 1; i < _adapter.openTimes.count; i++) {
        XCTAssertGreaterThanOrEqual(_adapter.openTimes[i].doubleValue - _adapter.openTimes[i - 1].doubleValue, 1 - 1e-9);
    }
}

@end
