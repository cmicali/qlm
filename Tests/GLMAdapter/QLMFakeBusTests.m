#import <XCTest/XCTest.h>

#import "QLMFakeBus.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the hlm protocol spec, revision 13, section 9, for the discovery
// sequence the fake bus plays back, section 8 for each reply's shape, and
// section 7 for the power and DSP frames.
@interface QLMFakeBusTests : XCTestCase
@end

@implementation QLMFakeBusTests {
    dispatch_queue_t _queue;
    QLMFakeMonitor *_left;
    QLMFakeMonitor *_sub;
    QLMFakeBus *_bus;
}

- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("qlm.tests.bus", DISPATCH_QUEUE_SERIAL);
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t subID[3] = {0x44, 0x55, 0x66};
    _left = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:leftID length:3] serialNumber:@"8320apm21001234"
                                            systemInfo:@"c-1;model-8320A" deviceClass:QLMTelemetryClassTwoWay];
    _sub = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:subID length:3] serialNumber:@"7350apm21005678"
                                           systemInfo:@"c-1;model-7350A" deviceClass:QLMTelemetryClassSubwoofer];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _sub]];
    [_bus startOnQueue:_queue];
}

// Sends on the bus's queue and waits. Returns whether a monitor answered.
- (BOOL)send:(QLMMessage)message reply:(QLMMessage *)reply error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL answered = NO;
    __block NSError *failure = nil;
    dispatch_async(_queue, ^{
        [self->_bus sendMessage:message replyHandler:^(const QLMMessage *received, NSError *sendError) {
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

- (void)testDiscoveryFollowsSection9 {
    QLMMessage reply;
    uint8_t hardwareID[3];
    XCTAssertTrue([self send:QLMCommandProbe() reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyHardwareID(&reply, hardwareID));
    XCTAssertEqual(memcmp(hardwareID, _left.hardwareID.bytes, 3), 0);

    uint8_t session = 0;
    XCTAssertTrue([self send:QLMCommandAssignSession(hardwareID, 0x02) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplySessionAck(&reply, &session));
    XCTAssertEqual(session, 0x02);
    XCTAssertEqual(_left.session, 0x02);

    XCTAssertTrue([self send:QLMCommandProbe() reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyHardwareID(&reply, hardwareID));
    XCTAssertEqual(memcmp(hardwareID, _sub.hardwareID.bytes, 3), 0);
    XCTAssertTrue([self send:QLMCommandAssignSession(hardwareID, 0x03) reply:&reply error:NULL]);

    // Every monitor holds a lease, so the probe goes unanswered.
    XCTAssertFalse([self send:QLMCommandProbe() reply:&reply error:NULL]);
}

- (void)testRepliesBySession {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t subID[3] = {0x44, 0x55, 0x66};
    XCTAssertTrue([self send:QLMCommandAssignSession(leftID, 0x02) reply:NULL error:NULL]);
    XCTAssertTrue([self send:QLMCommandAssignSession(subID, 0x03) reply:NULL error:NULL]);

    QLMMessage reply;
    QLMTelemetry telemetry;
    XCTAssertTrue([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);
    XCTAssertEqual(QLMReplyTelemetry(&reply, &telemetry), QLMTelemetryOK);
    XCTAssertEqual(telemetry.status, QLMTelemetryStatusOn);
    XCTAssertEqual(telemetry.deviceClass, QLMTelemetryClassTwoWay);
    XCTAssertEqual(telemetry.temperature, 38);

    XCTAssertTrue([self send:QLMCommandPoll(0x03) reply:&reply error:NULL]);
    XCTAssertEqual(QLMReplyTelemetry(&reply, &telemetry), QLMTelemetryOK);
    XCTAssertEqual(telemetry.deviceClass, QLMTelemetryClassSubwoofer);
    XCTAssertEqual(telemetry.subMeter, 0x80);

    char text[QLMPayloadMax];
    XCTAssertTrue([self send:QLMCommandSerialNumber(0x02) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertEqual(strcmp(text, "8320apm21001234"), 0);
    XCTAssertTrue([self send:QLMCommandSystemInfo(0x03) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertEqual(strcmp(text, "c-1;model-7350A"), 0);

    XCTAssertTrue([self send:QLMCommandMute(0x02, QLMMuteValueMuted) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyIsAck(&reply));
    XCTAssertEqual(_left.muteValue, QLMMuteValueMuted);

    // No lease at 04, and broadcasts get no reply.
    XCTAssertFalse([self send:QLMCommandPoll(0x04) reply:&reply error:NULL]);
    XCTAssertFalse([self send:QLMCommandKeepAlive() reply:&reply error:NULL]);
    XCTAssertFalse([self send:QLMCommandVolume(-20, -20) reply:&reply error:NULL]);
}

- (void)testStandbyDroppedRepliesAndAbsence {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    XCTAssertTrue([self send:QLMCommandAssignSession(leftID, 0x02) reply:NULL error:NULL]);

    [_bus perform:^{
        self->_left.on = NO;
    }];
    QLMMessage reply;
    QLMTelemetry telemetry;
    XCTAssertTrue([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);
    XCTAssertEqual(QLMReplyTelemetry(&reply, &telemetry), QLMTelemetryOK);
    XCTAssertEqual(telemetry.status, QLMTelemetryStatusStandby);
    XCTAssertEqual(telemetry.deviceClass, QLMTelemetryClassStandby);

    [_bus perform:^{
        self->_left.dropReplies = 2;
    }];
    XCTAssertFalse([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);
    XCTAssertFalse([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);
    XCTAssertTrue([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);

    [_bus perform:^{
        self->_left.present = NO;
    }];
    XCTAssertFalse([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);
}

- (void)testTheAllowlistAndDisconnectionFail {
    QLMMessage commit = QLMCommandPoll(0x02);
    commit.payload[0] = 0x15;
    NSError *error = nil;
    XCTAssertFalse([self send:commit reply:NULL error:&error]);
    XCTAssertEqualObjects(error.domain, QLMAdapterErrorDomain);
    XCTAssertEqual(error.code, QLMAdapterErrorForbidden);

    _bus.disconnected = YES;
    XCTAssertFalse([self send:QLMCommandProbe() reply:NULL error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorDisconnected);
}

- (void)testRecordsEverySend {
    XCTAssertTrue([self send:QLMCommandProbe() reply:NULL error:NULL]);
    XCTAssertFalse([self send:QLMCommandKeepAlive() reply:NULL error:NULL]);
    NSArray<NSData *> *sent = _bus.sentMessages;
    XCTAssertEqual(sent.count, 2u);
    const uint8_t probe[] = {0xFF, 0xFE};
    XCTAssertEqualObjects(sent[0], [NSData dataWithBytes:probe length:sizeof probe]);
    const uint8_t keepAlive[] = {0xFF, 0x04};
    XCTAssertEqualObjects(sent[1], [NSData dataWithBytes:keepAlive length:sizeof keepAlive]);
}

// Section 7, 3A 03, and section 9, "System Power": 03 02 prepares, 03 00
// powers off, and 03 7F and 03 01 wake. Broadcasts get no reply. The fake
// keeps each lease across the change.
- (void)testPowerBroadcastsChangeEveryMonitor {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    XCTAssertTrue([self send:QLMCommandAssignSession(leftID, 0x02) reply:NULL error:NULL]);

    XCTAssertFalse([self send:QLMCommandPower(QLMPowerStepStandbyPrepare) reply:NULL error:NULL]);
    XCTAssertTrue(_left.on);
    XCTAssertTrue(_sub.on);
    XCTAssertFalse([self send:QLMCommandPower(QLMPowerStepPowerOff) reply:NULL error:NULL]);
    XCTAssertFalse(_left.on);
    XCTAssertFalse(_sub.on);
    XCTAssertEqual(_left.session, 0x02);

    QLMMessage reply;
    QLMTelemetry telemetry;
    XCTAssertTrue([self send:QLMCommandPoll(0x02) reply:&reply error:NULL]);
    XCTAssertEqual(QLMReplyTelemetry(&reply, &telemetry), QLMTelemetryOK);
    XCTAssertEqual(telemetry.status, QLMTelemetryStatusStandby);

    XCTAssertFalse([self send:QLMCommandPower(QLMPowerStepWakeFirst) reply:NULL error:NULL]);
    XCTAssertTrue(_left.on);
    XCTAssertTrue(_sub.on);
    XCTAssertFalse([self send:QLMCommandPower(QLMPowerStepPowerOff) reply:NULL error:NULL]);
    XCTAssertFalse([self send:QLMCommandPower(QLMPowerStepWakeSecond) reply:NULL error:NULL]);
    XCTAssertTrue(_left.on);
}

// Section 9's enumeration: each DSP frame is acked on its own.
- (void)testDSPFramesAreAcked {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    XCTAssertTrue([self send:QLMCommandAssignSession(leftID, 0x02) reply:NULL error:NULL]);
    QLMMessage reply;
    XCTAssertTrue([self send:QLMCommandPrepare(0x02) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyIsAck(&reply));
    XCTAssertTrue([self send:QLMCommandRouting(0x02, 0x00, 0x01, 0x00, 0x00) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyIsAck(&reply));
    XCTAssertTrue([self send:QLMCommandInputSync(0x02) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyIsAck(&reply));
}

@end
