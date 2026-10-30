#import "QLMTestSupport.h"

#import "QLMReplayAdapter.h"
#include "QLMCommands.h"
#include "QLMReplies.h"
#include "QLMReport.h"

// Sources: captures/startup-idle. GLM leases six monitors, 02 to 07, each
// after a probe, then asks each for its system info. The probe after the
// sixth lease gets the no-answer frame.
@interface QLMReplayAdapterTests : XCTestCase
@end

@implementation QLMReplayAdapterTests {
    dispatch_queue_t _queue;
    QLMVirtualClock *_time;
    QLMReplayAdapter *_adapter;
}

- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("qlm.tests.replay", DISPATCH_QUEUE_SERIAL);
    NSError *error = nil;
    QLMCapture *capture = QLMReadCapture(@"startup-idle", &error);
    XCTAssertNotNil(capture, @"%@", error);
    _time = [[QLMVirtualClock alloc] init];
    _adapter = [[QLMReplayAdapter alloc] initWithCapture:capture];
    _adapter.clock = _time;
    [_adapter startOnQueue:_queue];
}

- (BOOL)send:(QLMMessage)message reply:(QLMMessage *)reply error:(NSError **)error {
    return [self qlm_send:message to:_adapter queue:_queue clock:_time reply:reply error:error];
}

- (void)testAnswersDiscoveryAsTheCaptureDid {
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    for (uint8_t session = QLMAddressSessionFirst; session < QLMAddressSessionFirst + 6; session++) {
        QLMMessage reply;
        uint8_t hardwareID[3];
        XCTAssertTrue([self send:QLMCommandProbe() reply:&reply error:NULL]);
        XCTAssertTrue(QLMReplyHardwareID(&reply, hardwareID));
        [hardwareIDs addObject:QLMBytes(hardwareID, sizeof hardwareID)];

        uint8_t acked = 0;
        XCTAssertTrue([self send:QLMCommandAssignSession(hardwareID, session) reply:&reply error:NULL]);
        XCTAssertTrue(QLMReplySessionAck(&reply, &acked));
        XCTAssertEqual(acked, session);
    }
    XCTAssertEqual(hardwareIDs.count, 6u);

    // The seventh probe's reply is the no-answer frame, which is no reply.
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandProbe() reply:NULL error:&error]);
    XCTAssertNil(error);

    QLMMessage reply;
    char text[QLMPayloadMax];
    char model[32];
    char firmware[32];
    XCTAssertTrue([self send:QLMCommandSystemInfo(0x03) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertTrue(QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqualObjects(@(model), @"8351B");
    XCTAssertEqual(_adapter.unmatchedMessages.count, 0u);
    XCTAssertEqual(_adapter.playedCount, 14u);
}

- (void)testPlaysEachExchangeOnce {
    QLMMessage first;
    QLMMessage second;
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressReply) reply:&first error:NULL]);
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressReply) reply:&second error:NULL]);
    XCTAssertEqual(_adapter.playedCount, 2u);
    XCTAssertEqual(first.payload[0], 0x09);
    XCTAssertEqual(second.payload[0], 0x09);
}

- (void)testABroadcastGetsNoReply {
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandKeepAlive() reply:NULL error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(_adapter.playedCount, 1u);
}

// GLM never polled 55, so nothing answers, as on a bus with no such lease.
- (void)testAMessageTheCaptureNeverSentGetsNoReply {
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandPoll(0x55) reply:NULL error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(_adapter.playedCount, 0u);
    const uint8_t record[] = {0x55, 0x08};
    XCTAssertEqualObjects(_adapter.unmatchedMessages, @[QLMBytes(record, sizeof record)]);
}

// GLM sent `05` to every monitor; the allowlist still refuses it here.
- (void)testRefusesWhatTheAllowlistRefuses {
    NSError *error = nil;
    QLMMessage generator = QLMMakeMessage(0x02, 0x05, 0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xEA, 0x00, 0x01, 0x90, 0x00, 0x02, 0xDA);
    XCTAssertFalse([self send:generator reply:NULL error:&error]);
    XCTAssertEqualObjects(error.domain, QLMAdapterErrorDomain);
    XCTAssertEqual(error.code, QLMAdapterErrorForbidden);
    XCTAssertEqual(_adapter.playedCount, 0u);
    XCTAssertEqual(_adapter.unmatchedMessages.count, 0u);
}

// One report line, its bytes padded with zeros to a whole report.
static NSString *QLMLine(NSString *start, NSString *bytes) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%@ %@", start, bytes];
    for (NSUInteger i = [bytes componentsSeparatedByString:@" "].count; i < QLMReportLength; i++) {
        [line appendString:@" 00"];
    }
    [line appendString:@"\n"];
    return line;
}

static QLMCapture *QLMCaptureFromText(NSString *text, NSError **error) {
    return [[QLMCapture alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:error];
}

- (void)testACaptureReadsExchanges {
    NSString *text = [@[@"# a comment\n\n", QLMLine(@"0.1 out", @"85 01 08 4D C6 7E"), QLMLine(@"0.2 in", @"3F 01 09 5D E7 7E"),
                        QLMLine(@"0.3 out", @"85 FF 04 BC 84 7E"), QLMLine(@"0.4 out", @"85 FF FE F2 D1 7E"),
                        QLMLine(@"0.5 in", @"3F 01 7D 5E 53 97 7E")] componentsJoinedByString:@""];
    NSError *error = nil;
    QLMCapture *capture = QLMCaptureFromText(text, &error);
    XCTAssertNotNil(capture, @"%@", error);
    XCTAssertEqualObjects(capture.comments, @[@"a comment"]);
    XCTAssertEqual(capture.exchanges.count, 3u);

    QLMCaptureExchange *poll = capture.exchanges[0];
    QLMMessage reply = poll.reply;
    XCTAssertTrue(poll.answered);
    XCTAssertTrue(QLMReplyIsAck(&reply));
    XCTAssertEqual(poll.message.address, QLMAddressReply);

    QLMCaptureExchange *keepAlive = capture.exchanges[1];
    XCTAssertNil(keepAlive.replyFrame);
    XCTAssertFalse(keepAlive.answered);
    XCTAssertEqualWithAccuracy(keepAlive.time, 0.3, 1e-9);

    QLMCaptureExchange *probe = capture.exchanges[2];
    XCTAssertNotNil(probe.replyFrame);
    XCTAssertFalse(probe.answered);
}

- (void)testACaptureRejectsWhatTheReportLayerRejects {
    NSArray<NSString *> *bad = @[
        QLMLine(@"0.1 in", @"3F 01 09 5D E7 7E"),                                               // no request
        QLMLine(@"0.1 out", @"85 01 08 4D C6 7F"),                                              // no flag
        QLMLine(@"0.1 out", @"85 01 08 4D C7 7E"),                                              // CRC
        @"0.1 out 85 01 08 4D C6 7E\n",                                                         // short
        QLMLine(@"0.1 sideways", @"85 01 08 4D C6 7E"),                                         // direction
        [QLMLine(@"0.1 out", @"85 01 08 4D C6 7E") stringByAppendingString:QLMLine(@"0.2 in", @"3F 01 09")], // cut off
    ];
    for (NSString *text in bad) {
        NSError *error = nil;
        XCTAssertNil(QLMCaptureFromText(text, &error), @"%@", text);
        XCTAssertEqual(error.code, QLMAdapterErrorCapture, @"%@", text);
        XCTAssertTrue([error.localizedDescription hasPrefix:@"Line "], @"%@", error.localizedDescription);
    }
}

@end
