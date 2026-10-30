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
    QLMReplayAdapter *_adapter;
}

- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("qlm.tests.replay", DISPATCH_QUEUE_SERIAL);
    NSError *error = nil;
    QLMCapture *capture = QLMReadCapture(@"startup-idle", &error);
    XCTAssertNotNil(capture, @"%@", error);
    _adapter = [[QLMReplayAdapter alloc] initWithCapture:capture];
    [_adapter startOnQueue:_queue];
}

// Sends on the adapter's queue and waits. Returns whether a reply came.
- (BOOL)send:(QLMMessage)message reply:(QLMMessage *)reply error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL answered = NO;
    __block NSError *failure = nil;
    dispatch_async(_queue, ^{
        [self->_adapter sendMessage:message replyHandler:^(const QLMMessage *received, NSError *sendError) {
            if (received != NULL) {
                answered = YES;
                if (reply != NULL) {
                    *reply = *received;
                }
            }
            failure = sendError;
            dispatch_semaphore_signal(done);
        }];
    });
    XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    if (error != NULL) {
        *error = failure;
    }
    return answered;
}

- (void)testAnswersDiscoveryAsTheCaptureDid {
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    for (uint8_t session = QLMAddressSessionFirst; session < QLMAddressSessionFirst + 6; session++) {
        QLMMessage reply;
        uint8_t hardwareID[3];
        XCTAssertTrue([self send:QLMCommandProbe() reply:&reply error:NULL]);
        XCTAssertTrue(QLMReplyHardwareID(&reply, hardwareID));
        [hardwareIDs addObject:[NSData dataWithBytes:hardwareID length:3]];

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
    XCTAssertTrue(_adapter.unmatchedMessages.count == 0);
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
    XCTAssertEqualObjects(_adapter.unmatchedMessages, @[[NSData dataWithBytes:record length:sizeof record]]);
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

static QLMCapture *QLMCaptureFromText(NSString *text, NSError **error) {
    return [[QLMCapture alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:error];
}

static NSString *QLMPadded(NSString *bytes) {
    NSMutableString *line = [bytes mutableCopy];
    NSUInteger count = [bytes componentsSeparatedByString:@" "].count;
    for (NSUInteger i = count; i < QLMReportLength; i++) {
        [line appendString:@" 00"];
    }
    return line;
}

- (void)testACaptureReadsExchanges {
    NSString *text = [NSString stringWithFormat:@"# a comment\n\n0.1 out %@\n0.2 in %@\n0.3 out %@\n",
                      QLMPadded(@"85 01 08 4D C6 7E"), QLMPadded(@"3F 01 09 5D E7 7E"), QLMPadded(@"85 FF 04 BC 84 7E")];
    NSError *error = nil;
    QLMCapture *capture = QLMCaptureFromText(text, &error);
    XCTAssertNotNil(capture, @"%@", error);
    XCTAssertEqualObjects(capture.comments, @[@"a comment"]);
    XCTAssertEqual(capture.reports.count, 3u);
    XCTAssertEqual(capture.exchanges.count, 2u);
    QLMMessage reply = capture.exchanges[0].reply;
    XCTAssertTrue(capture.exchanges[0].hasReply);
    XCTAssertTrue(QLMReplyIsAck(&reply));
    XCTAssertFalse(capture.exchanges[1].hasReply);
    XCTAssertEqualWithAccuracy(capture.exchanges[1].time, 0.3, 1e-9);
}

- (void)testACaptureRejectsWhatTheReportLayerRejects {
    NSArray<NSString *> *bad = @[
        [NSString stringWithFormat:@"0.1 in %@\n", QLMPadded(@"3F 01 09 5D E7 7E")],                                   // no request
        [NSString stringWithFormat:@"0.1 out %@\n", QLMPadded(@"85 01 08 4D C6 7F")],                                  // no flag
        [NSString stringWithFormat:@"0.1 out %@\n", QLMPadded(@"85 01 08 4D C7 7E")],                                  // CRC
        @"0.1 out 85 01 08 4D C6 7E\n",                                                                                // short
        [NSString stringWithFormat:@"0.1 sideways %@\n", QLMPadded(@"85 01 08 4D C6 7E")],                             // direction
        [NSString stringWithFormat:@"0.1 out %@\n0.2 in %@\n", QLMPadded(@"85 01 08 4D C6 7E"), QLMPadded(@"3F 01 09")], // cut off
    ];
    for (NSString *text in bad) {
        NSError *error = nil;
        XCTAssertNil(QLMCaptureFromText(text, &error), @"%@", text);
        XCTAssertEqual(error.code, QLMAdapterErrorCapture, @"%@", text);
        XCTAssertTrue([error.localizedDescription hasPrefix:@"Line "], @"%@", error.localizedDescription);
    }
}

@end
