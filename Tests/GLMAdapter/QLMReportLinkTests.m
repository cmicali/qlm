#import "QLMTestSupport.h"

#import "QLMReportLink.h"
#include "QLMCommands.h"
#include "QLMReplies.h"
#include "QLMReport.h"

// Sources: captures/startup-idle, report by report. The adapter's system
// info spans two input reports (7.30 s). Every probe and unicast gets one
// reply and every other broadcast none (QLMGoldenTests pins both), so GLM
// keeps one request in flight. Every reply starts 01 09, so none names its
// request. Only 01 08 gets a status shape, and only 39 system info
// (QLMGoldenTests again). The slowest reply in any capture took 11 ms.
@interface QLMReportLinkTests : XCTestCase
@end

@implementation QLMReportLinkTests {
    dispatch_queue_t _queue;
    QLMCaptureDevice *_device;
    NSUInteger _opening;  // reports written before the test's own
}

// A new link, which has sent nothing yet.
- (void)startDevice {
    NSError *error = nil;
    QLMCapture *capture = QLMReadCapture(@"startup-idle", &error);
    XCTAssertNotNil(capture, @"%@", error);
    _device = [[QLMCaptureDevice alloc] initWithCapture:capture];
    [_device startOnQueue:_queue];
    _device.link.replyTimeout = 0.05;
    _opening = 0;
}

// Each test starts in step, past its link's first sync. A test of an open
// starts another device.
- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("qlm.tests.link", DISPATCH_QUEUE_SERIAL);
    [self startDevice];
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:NULL error:NULL]);
    _opening = [self written].count;
}

- (BOOL)send:(QLMMessage)message reply:(QLMMessage *)reply error:(NSError **)error {
    return [self qlm_send:message to:_device queue:_queue reply:reply error:error];
}

// Every output report since the opening.
- (NSArray<NSData *> *)written {
    __block NSArray<NSData *> *written = nil;
    dispatch_sync(_queue, ^{
        written = self->_device.writtenReports;
    });
    return [written subarrayWithRange:NSMakeRange(_opening, written.count - _opening)];
}

- (NSUInteger)deliveredReplies {
    __block NSUInteger delivered = 0;
    QLMCaptureDevice *device = _device;
    dispatch_sync(_queue, ^{
        delivered = device.deliveredReplies;
    });
    return delivered;
}

static NSData *QLMReportFor(QLMMessage message) {
    uint8_t report[QLMReportLength];
    QLMReportPackOutput(&message, report);
    return QLMBytes(report, sizeof report);
}

// A reply GLM got in its opening: 0 a status, 1 the adapter's name, which
// qlm never asks for, and 3 the system info (startup-idle, 7.29 s).
static NSData *QLMGLMReply(NSUInteger exchange) {
    return QLMReadCapture(@"startup-idle", NULL).exchanges[exchange].replyFrame;
}

// Asks for the adapter's serial on a link that is out of step. The late
// replies, to another host's requests, come after the link's first write and
// before its reply, as when the adapter still held them at the open. Each
// answers nothing: the open's sync and then the query go out, and the query
// gets its own reply.
- (void)assertAnOpenDropsLateReplies:(NSArray<NSData *> *)frames {
    QLMReportLink *link = _device.link;
    __block NSString *serial = nil;
    XCTestExpectation *answered = [self expectationWithDescription:@"serial"];
    dispatch_async(_queue, ^{
        [link sendMessage:QLMCommandSerialNumber(QLMAddressAdapter) replyHandler:^(const QLMMessage *reply, NSError *error) {
            XCTAssertNil(error);
            char text[QLMPayloadMax];
            if (reply != NULL && QLMReplyText(reply, text, sizeof text)) {
                serial = @(text);
            }
            [answered fulfill];
        }];
        for (NSData *frame in frames) {
            for (NSData *input in [QLMCaptureDevice inputReportsForFrame:frame]) {
                [link receiveReport:input.bytes length:input.length];
            }
        }
    });
    [self waitForExpectations:@[answered] timeout:1];
    XCTAssertEqualObjects(serial, @"H99999F000");
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)), QLMReportFor(QLMCommandPoll(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandSerialNumber(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
    XCTAssertEqual(link.strayReplies, frames.count);
}

// Sends, then closes and reopens the device before the reply comes, as when
// GLM appears. The send fails with the close's error. Returns why the link
// lost track, or nil.
- (NSError *)sendThenReopen:(QLMMessage)message {
    QLMReportLink *link = _device.link;
    NSError *busy = QLMAdapterErrorMake(QLMAdapterErrorBusy, @"GLM is running.");
    XCTestExpectation *closed = [self expectationWithDescription:@"closed"];
    __block NSError *failure = nil;
    dispatch_async(_queue, ^{
        [link sendMessage:message replyHandler:^(const QLMMessage *reply, NSError *error) {
            XCTAssertTrue(reply == NULL);
            XCTAssertEqualObjects(error, busy);
            [closed fulfill];
        }];
        [link closeWithError:busy];
        [link reopen];
        failure = link.failure;
    });
    [self waitForExpectations:@[closed] timeout:1];
    return failure;
}

// GLM's last request before it quits is the adapter's status poll, so a
// reply late for GLM is likeliest a status. In qlm-first-discover, GLM quit
// at 14.5 s, and qlm's first report is at 24.9 s.
- (void)testGLMsLastRequestBeforeItQuitsIsAStatusPoll {
    NSData *poll = QLMReportFor(QLMCommandPoll(QLMAddressAdapter));
    XCTAssertEqualObjects(QLMReadCapture(@"quit-glm", NULL).exchanges.lastObject.outputReport, poll);
    QLMCaptureExchange *glmsLast = nil;
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"qlm-first-discover", NULL).exchanges) {
        if (exchange.time > 20) {
            break;
        }
        glmsLast = exchange;
    }
    XCTAssertEqualWithAccuracy(glmsLast.time, 14.45, 0.01);
    XCTAssertEqualObjects(glmsLast.outputReport, poll);
}

// An open syncs before its first request: the system info, then the status
// poll.
- (void)testAnOpenSyncsBeforeTheFirstRequest {
    [self startDevice];
    [self assertAnOpenDropsLateReplies:@[]];
    XCTAssertEqual(_device.link.timeouts, 0u);
}

// The system info drops a late status.
- (void)testALateStatusAnswersNothingAfterAnOpen {
    [self startDevice];
    [self assertAnOpenDropsLateReplies:@[QLMGLMReply(0)]];
}

// A late system info is taken for the first step's. The status poll then
// drops the first step's own.
- (void)testALateSystemInfoAnswersNothingAfterAnOpen {
    [self startDevice];
    [self assertAnOpenDropsLateReplies:@[QLMGLMReply(3)]];
}

- (void)testALateReplyOfAnotherShapeAnswersNothingAfterAnOpen {
    [self startDevice];
    [self assertAnOpenDropsLateReplies:@[QLMGLMReply(1)]];
}

// An earlier qlm whose status poll timed out, and that quit while the system
// info synced, leaves both replies late. Neither answers anything.
- (void)testALateStatusAndSystemInfoAnswerNothingAfterAnOpen {
    [self startDevice];
    [self assertAnOpenDropsLateReplies:@[QLMGLMReply(0), QLMGLMReply(3)]];
}

// GLM may have run while the device was closed, so a reopen syncs even when
// none of the link's own replies is late.
- (void)testAReopenInStepStillSyncs {
    QLMReportLink *link = _device.link;
    dispatch_sync(_queue, ^{
        [link closeWithError:QLMAdapterErrorMake(QLMAdapterErrorBusy, @"GLM is running.")];
        [link reopen];
    });
    [self assertAnOpenDropsLateReplies:@[QLMGLMReply(0)]];
    XCTAssertNil(link.failure);
}

// The device closes while the open's sync waits. The other host's reply may
// come ahead of the sync's, with either shape, so no sync is left.
- (void)testClosingDuringAnOpensSyncLosesTrack {
    [self startDevice];
    NSError *failure = [self sendThenReopen:QLMCommandSerialNumber(QLMAddressAdapter)];
    XCTAssertEqual(failure.code, QLMAdapterErrorDisconnected);
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandSerialNumber(QLMAddressAdapter) reply:NULL error:&error]);
    XCTAssertEqualObjects(error, failure);
    XCTAssertEqualObjects([self written], @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter))]);
}

- (void)testAssemblesAReplyAcrossTwoInputReports {
    QLMMessage reply;
    NSError *error = nil;
    XCTAssertTrue([self send:QLMCommandSystemInfo(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertNil(error);
    char text[QLMPayloadMax];
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertTrue(strncmp(text, "c-0;model-GLM Adapter;ver-1.4.0.6113;", 37) == 0, @"%s", text);
    XCTAssertEqualObjects([self written], @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter))]);
}

- (void)testABroadcastCompletesWithNoReply {
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandKeepAlive() reply:NULL error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual([self written].count, 1u);
}

// The seventh probe in startup-idle gets the adapter's no-answer frame.
- (void)testTheNoAnswerFrameIsNoReply {
    for (int i = 0; i < 6; i++) {
        XCTAssertTrue([self send:QLMCommandProbe() reply:NULL error:NULL]);
    }
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandProbe() reply:NULL error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(_device.link.timeouts, 0u);
}

// A reply that comes after its timeout must not answer the next request,
// however late. Replies are 01 09 and the payload, naming no request. Here
// the system info comes 120 ms after its request, past two 50 ms timeouts,
// and the serial query's reply queues behind it. The link syncs with the
// adapter's status poll, a shape no text has, and drops the late reply.
- (void)testALateReplyNeverAnswersTheNextRequest {
    QLMMessage reply;
    NSError *error = nil;
    _device.nextReplyDelay = 0.12;
    XCTAssertFalse([self send:QLMCommandSystemInfo(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorTimeout);

    XCTAssertTrue([self send:QLMCommandSerialNumber(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertNil(error);
    char text[QLMPayloadMax];
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertEqualObjects(@(text), @"H99999F000");
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)), QLMReportFor(QLMCommandPoll(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandSerialNumber(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
    XCTAssertEqual(_device.link.strayReplies, 1u);
    XCTAssertEqual(_device.link.timeouts, 1u);
}

// After a status poll times out, a late reply could be a status, so the
// sync is the adapter's system info.
- (void)testALateStatusIsSyncedWithTheSystemInfo {
    QLMMessage reply;
    NSError *error = nil;
    _device.nextReplyDelay = 0.12;
    XCTAssertFalse([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorTimeout);

    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue(QLMReplyIsAdapterStatus(&reply));
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandPoll(QLMAddressAdapter)), QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandPoll(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
    XCTAssertEqual(_device.link.strayReplies, 1u);
    XCTAssertEqual(_device.link.timeouts, 1u);
}

// With no late reply, the sync's own reply ends the hold. No monitor holds
// session 30 in startup-idle, so the poll to it gets no reply here.
- (void)testTheSyncsReplyEndsTheHold {
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandPoll(0x30) reply:NULL error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorTimeout);

    QLMMessage reply;
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue(QLMReplyIsAdapterStatus(&reply));
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandPoll(0x30)), QLMReportFor(QLMCommandPoll(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandPoll(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
    XCTAssertEqual(_device.link.strayReplies, 0u);
    XCTAssertEqual(_device.link.timeouts, 1u);
}

// Sends until the link takes the message. While the link stalls, a send
// fails at once and writes nothing.
- (BOOL)sendOnceInStep:(QLMMessage)message reply:(QLMMessage *)reply error:(NSError **)error {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    for (;;) {
        BOOL answered = [self send:message reply:reply error:error];
        if ((*error).code != QLMAdapterErrorDisconnected || [deadline timeIntervalSinceNow] < 0) {
            return answered;
        }
        [NSThread sleepForTimeInterval:0.005];
    }
}

// The system info comes 800 ms late, and the sync's reply queues behind it,
// past the sync's five timeouts. The link stalls rather than give up: the
// held request and every send fail at once, and none is written. Once the
// sync's reply comes, the link is in step, and the late reply has answered
// nothing.
// TRAP: the sync is overdue about 300 ms in, but CI's timers fire late. At
// 340 ms the late reply landed inside the sync's window there.
- (void)testAnOverdueSyncStallsTheLinkUntilItsReplyComes {
    QLMMessage reply;
    NSError *error = nil;
    _device.nextReplyDelay = 0.8;
    XCTAssertFalse([self send:QLMCommandSystemInfo(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorTimeout);
    XCTAssertFalse([self send:QLMCommandSerialNumber(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorDisconnected);
    XCTAssertEqualObjects(error.localizedDescription, @"The GLM adapter stopped answering.");

    XCTAssertTrue([self sendOnceInStep:QLMCommandSerialNumber(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertNil(error);
    char text[QLMPayloadMax];
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertEqualObjects(@(text), @"H99999F000");
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)), QLMReportFor(QLMCommandPoll(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandSerialNumber(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
    XCTAssertEqual(_device.link.strayReplies, 1u);
    XCTAssertEqual(_device.link.timeouts, 2u);
}

// The device closes with a request in flight, as when GLM appears, and
// opens again before the reply comes. The reply is a late system info now,
// so the open's sync starts with the status poll, and the late reply answers
// nothing.
- (void)testAReopenSyncsBeforeTheNextRequest {
    _device.nextReplyDelay = 0.12;
    QLMReportLink *link = _device.link;
    XCTAssertNil([self sendThenReopen:QLMCommandSystemInfo(QLMAddressAdapter)]);

    QLMMessage reply;
    NSError *error = nil;
    XCTAssertTrue([self send:QLMCommandSerialNumber(QLMAddressAdapter) reply:&reply error:&error]);
    XCTAssertNil(error);
    char text[QLMPayloadMax];
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertEqualObjects(@(text), @"H99999F000");
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)), QLMReportFor(QLMCommandPoll(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)),
                                QLMReportFor(QLMCommandSerialNumber(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
    XCTAssertEqual(link.strayReplies, 1u);
}

// The device closes while the sync waits, and opens again. A system info
// and a status reply may both still come, so no sync is left, and the link
// has lost track. It stays closed after the reopen, and the late replies
// answer nothing. The HID adapter then opens the adapter only once it
// arrives anew.
- (void)testClosingDuringASyncLosesTrack {
    NSError *error = nil;
    _device.nextReplyDelay = 0.12;
    NSUInteger before = [self deliveredReplies];
    XCTAssertFalse([self send:QLMCommandSystemInfo(QLMAddressAdapter) reply:NULL error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorTimeout);
    QLMReportLink *link = _device.link;
    __block NSError *failure = nil;
    dispatch_sync(_queue, ^{
        [link closeWithError:QLMAdapterErrorMake(QLMAdapterErrorBusy, @"GLM is running.")];
        [link reopen];
        failure = link.failure;
    });
    XCTAssertEqual(failure.code, QLMAdapterErrorDisconnected);
    XCTAssertEqualObjects(failure.localizedDescription,
                          @"qlm lost track of the GLM adapter's replies. Unplug the adapter and plug it back in.");

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([self deliveredReplies] < before + 2 && [deadline timeIntervalSinceNow] > 0) {
        [NSThread sleepForTimeInterval:0.005];
    }
    XCTAssertEqual([self deliveredReplies], before + 2);
    XCTAssertFalse([self send:QLMCommandSerialNumber(QLMAddressAdapter) reply:NULL error:&error]);
    XCTAssertEqualObjects(error, failure);
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter)), QLMReportFor(QLMCommandPoll(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
}

- (void)testRefusesWhatTheAllowlistRefusesAndWritesNothing {
    NSError *error = nil;
    QLMMessage generator = QLMMakeMessage(0x02, 0x05, 0x04, 0x00);
    XCTAssertFalse([self send:generator reply:NULL error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorForbidden);
    QLMMessage adapterQuery = QLMMakeMessage(QLMAddressAdapter, 0x22);
    XCTAssertFalse([self send:adapterQuery reply:NULL error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorForbidden);
    XCTAssertEqual([self written].count, 0u);
}

- (void)testCloseFailsTheRequestInFlightAndEveryLaterSend {
    _device.silent = YES;
    XCTestExpectation *failed = [self expectationWithDescription:@"in flight"];
    QLMReportLink *link = _device.link;
    NSError *closing = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"unplugged");
    dispatch_async(_queue, ^{
        [link sendMessage:QLMCommandPoll(QLMAddressAdapter) replyHandler:^(const QLMMessage *reply, NSError *error) {
            XCTAssertTrue(reply == NULL);
            XCTAssertEqualObjects(error, closing);
            [failed fulfill];
        }];
        [link closeWithError:closing];
    });
    [self waitForExpectations:@[failed] timeout:1];
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandProbe() reply:NULL error:&error]);
    XCTAssertEqualObjects(error, closing);
    XCTAssertEqual([self written].count, 1u);
}

// Input that does not read fails the request, and the link then syncs
// before the next one, since the real reply may still come.
- (void)testAReplyThatDoesNotReadFailsTheRequest {
    _device.silent = YES;
    XCTestExpectation *failed = [self expectationWithDescription:@"bad reply"];
    QLMReportLink *link = _device.link;
    dispatch_async(_queue, ^{
        [link sendMessage:QLMCommandPoll(QLMAddressAdapter) replyHandler:^(const QLMMessage *reply, NSError *error) {
            XCTAssertTrue(reply == NULL);
            XCTAssertEqual(error.code, QLMAdapterErrorBadReply);
            [failed fulfill];
        }];
        uint8_t bad[QLMReportLength] = {0x3E, 0x01, 0x09, 0x5D, 0xE7, 0x7E};
        [link receiveReport:bad length:sizeof bad];
    });
    [self waitForExpectations:@[failed] timeout:1];
    XCTAssertEqual(link.timeouts, 0u);
    NSArray<NSData *> *sent = @[QLMReportFor(QLMCommandPoll(QLMAddressAdapter)), QLMReportFor(QLMCommandSystemInfo(QLMAddressAdapter))];
    XCTAssertEqualObjects([self written], sent);
}

// Input with no request waiting is dropped, and the next request gets its own.
- (void)testStrayInputIsDropped {
    QLMReportLink *link = _device.link;
    dispatch_sync(_queue, ^{
        uint8_t ack[QLMReportLength] = {QLMReportInputPrefix, 0x01, 0x09, 0x5D, 0xE7, 0x7E};
        [link receiveReport:ack length:sizeof ack];
    });
    XCTAssertEqual(link.strayReplies, 1u);
    QLMMessage reply;
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:NULL]);
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&reply, &status), QLMAdapterStatusOK);
    XCTAssertEqual(status.knobTenths, -1004);
}

// The split the capture device makes is the adapter's: every reply in
// startup-idle splits back into the input reports it came in.
- (void)testInputReportsSplitAsTheAdapterSentThem {
    NSData *frame = QLMReadCapture(@"startup-idle", NULL).exchanges[3].replyFrame;  // 01 39
    NSArray<NSData *> *reports = [QLMCaptureDevice inputReportsForFrame:frame];
    XCTAssertEqual(reports.count, 2u);
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMMessage reply;
    XCTAssertEqual(QLMReportReadInput(&assembly, reports[0].bytes, QLMReportLength, &reply), QLMReportPending);
    XCTAssertEqual(QLMReportReadInput(&assembly, reports[1].bytes, QLMReportLength, &reply), QLMReportOK);
}

@end
