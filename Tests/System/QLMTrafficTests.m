#import "QLMTestSupport.h"

#include "QLMCommands.h"
#import "QLMFakeBus.h"
#import "QLMSystem.h"
#import "QLMTraffic.h"

// The traffic System keeps for the traffic window: a ring of values from the
// adapter's tap, each reply paired with the request in flight, since the
// adapter keeps one (docs/protocol.md, Replies).
@interface QLMTrafficTests : XCTestCase
@end

@implementation QLMTrafficTests

- (void)testARecorderPairsEachReplyWithItsRequest {
    QLMTrafficRecorder *recorder = [[QLMTrafficRecorder alloc] initWithCapacity:8];
    QLMMessage poll = QLMCommandPoll(0x0B);
    const uint8_t hardwareID[3] = {1, 2, 3};
    QLMMessage reply = QLMMakeMessage(0x01, 0x09);
    QLMMessage volume = QLMCommandVolume(-40, -30);
    [recorder record:QLMTrafficRequest message:&poll hardwareID:hardwareID ceiling:-30];
    [recorder record:QLMTrafficReply message:&reply hardwareID:NULL ceiling:-20];
    [recorder record:QLMTrafficRequest message:&volume hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficStray message:&reply hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficRequest message:&poll hardwareID:hardwareID ceiling:-30];
    [recorder record:QLMTrafficTimeout message:NULL hardwareID:NULL ceiling:-30];

    NSArray<QLMTrafficEntry *> *entries = [recorder entriesAfter:0];
    XCTAssertEqual(entries.count, 6u);
    XCTAssertEqual(entries[1].answers, 1u);
    XCTAssertEqualObjects(entries[1].request, QLMAdapterRecord(&poll));
    XCTAssertEqualObjects(entries[1].hardwareID, QLMBytes(hardwareID, 3), @"a reply takes its request's monitor");
    XCTAssertEqual(entries[1].ceilingDecibels, -30, @"and its ceiling");
    XCTAssertFalse(entries[1].outgoing);
    XCTAssertTrue(entries[2].outgoing);
    XCTAssertEqual(entries[3].answers, 0u, @"a broadcast expects no reply, so a stray answers nothing");
    XCTAssertEqual(entries[5].answers, 5u);
    XCTAssertEqual(entries[5].bytes.length, 0u);
    XCTAssertEqual([recorder entriesAfter:4].count, 2u);
}

// A sync's wait goes on past its timeout, so its late reply still answers
// it (QLMReportLink.h). One the adapter did not take answers nothing.
- (void)testATimeoutLeavesItsRequestInFlight {
    QLMTrafficRecorder *recorder = [[QLMTrafficRecorder alloc] initWithCapacity:8];
    QLMMessage sync = QLMCommandPoll(QLMAddressAdapter);
    QLMMessage status = QLMMakeMessage(0x01, 0x09, 0x33, 0x31);
    [recorder record:QLMTrafficSync message:&sync hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficTimeout message:NULL hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficStray message:NULL hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficReply message:&status hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficNotTaken message:&sync hardwareID:NULL ceiling:-30];
    [recorder record:QLMTrafficStray message:&status hardwareID:NULL ceiling:-30];
    NSArray<QLMTrafficEntry *> *entries = [recorder entriesAfter:0];
    XCTAssertEqual(entries[1].answers, 1u);
    XCTAssertEqual(entries[2].answers, 0u, @"an unreadable stray ends no wait");
    XCTAssertEqual(entries[3].answers, 1u);
    XCTAssertEqual(entries[5].answers, 0u);
}

- (void)testTheRingKeepsTheLast {
    QLMTrafficRecorder *recorder = [[QLMTrafficRecorder alloc] initWithCapacity:4];
    QLMMessage poll = QLMCommandPoll(0x0B);
    for (int i = 0; i < 10; i++) {
        [recorder record:QLMTrafficRequest message:&poll hardwareID:NULL ceiling:-30];
    }
    NSArray<QLMTrafficEntry *> *entries = [recorder entriesAfter:0];
    XCTAssertEqual(entries.count, 4u);
    XCTAssertEqual(entries.firstObject.number, 7u);
    XCTAssertEqual(entries.lastObject.number, 10u);
    XCTAssertEqual(recorder.lastNumber, 10u);
}

// A System on a fake bus with a virtual clock, run for `seconds`, with a
// traffic handler or without. Returns every frame the bus took.
- (NSArray<NSData *> *)framesOfARun:(NSTimeInterval)seconds
                            watching:(BOOL)watching
                             entries:(NSMutableArray<QLMTrafficEntry *> *)entries {
    QLMVirtualClock *time = [[QLMVirtualClock alloc] init];
    QLMFakeBus *bus = [QLMFakeBus demoBusWithSubwoofer:YES];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = time;
    settings.ceilingDecibels = -30;
    QLMSystem *system = [[QLMSystem alloc] initWithAdapter:bus settings:settings];
    dispatch_queue_t queue = dispatch_queue_create("qlm.tests.traffic", DISPATCH_QUEUE_SERIAL);
    if (watching) {
        [system setTrafficHandler:^(NSArray<QLMTrafficEntry *> *batch) {
            [entries addObjectsFromArray:batch];
        } queue:queue];
    }
    [system setVolumeDecibels:-20];
    [system start];
    [time advanceBy:seconds];
    [system setMuted:YES forMonitorWithHardwareID:bus.monitors.firstObject.hardwareID];
    [time advanceBy:1];
    __block BOOL stopped = NO;
    [system stopWithCompletion:^{
        stopped = YES;
    }];
    XCTAssertTrue([time runUntil:^BOOL {
        return stopped;
    } within:10]);
    // The last batch waits up to 0.1 s.
    [time advanceBy:0.5];
    dispatch_sync(queue, ^{
    });
    return bus.sentMessages;
}

// Watching changes nothing System sends.
- (void)testWatchingSendsTheSameFrames {
    NSMutableArray<QLMTrafficEntry *> *entries = [NSMutableArray array];
    NSArray<NSData *> *watched = [self framesOfARun:3 watching:YES entries:entries];
    NSArray<NSData *> *unwatched = [self framesOfARun:3 watching:NO entries:[NSMutableArray array]];
    XCTAssertEqualObjects(watched, unwatched);
    XCTAssertGreaterThan(entries.count, 0u);
}

// Every frame the bus took is a request in the traffic, in order, as it
// went out. A frame to a session names the monitor that held it, and no
// volume frame passed the ceiling. The stop's hand-back sends the knob's
// level, the fake bus's bottom stop.
- (void)testTheTrafficIsWhatWentOut {
    NSMutableArray<QLMTrafficEntry *> *entries = [NSMutableArray array];
    NSArray<NSData *> *sent = [self framesOfARun:3 watching:YES entries:entries];
    NSMutableArray<NSData *> *requests = [NSMutableArray array];
    uint64_t number = 0;
    for (QLMTrafficEntry *entry in entries) {
        XCTAssertEqual(entry.number, ++number, @"in order, none twice");
        if (entry.kind == QLMTrafficRequest) {
            [requests addObject:entry.bytes];
            QLMMessage message = entry.message;
            if (message.payload[0] == 0x1F) {
                XCTAssertLessThanOrEqual(QLMVolumeWordOf(message), QLMVolumeWordOf(QLMCommandVolume(-30, -30)));
                XCTAssertEqual(entry.ceilingDecibels, -30);
            }
            if (message.payload[0] == 0x2B && message.address != QLMAddressAdapter) {
                XCTAssertNotNil(entry.hardwareID, @"%@", entry.bytes);
            }
        } else {
            XCTAssertNotEqual(entry.answers, 0u, @"the fake bus sends nothing unasked");
        }
    }
    XCTAssertEqualObjects(requests, sent);
}

@end
