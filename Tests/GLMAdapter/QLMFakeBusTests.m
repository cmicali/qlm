#import "QLMTestSupport.h"

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
    QLMVirtualClock *_time;
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
    _time = [[QLMVirtualClock alloc] init];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[_left, _sub]];
    [_bus startOnQueue:_queue clock:_time];
}

- (BOOL)send:(QLMMessage)message reply:(QLMMessage *)reply error:(NSError **)error {
    return [self qlm_send:message to:_bus queue:_queue clock:_time reply:reply error:error];
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

- (void)testRecordingCanBeTurnedOff {
    _bus.recordsSentMessages = NO;
    XCTAssertTrue([self send:QLMCommandProbe() reply:NULL error:NULL]);
    XCTAssertEqual(_bus.sentMessages.count, 0u);
}

- (void)testDemoBus {
    XCTAssertEqual([QLMFakeBus demoBusWithSubwoofer:NO].monitors.count, 2u);
    NSArray<QLMFakeMonitor *> *monitors = [QLMFakeBus demoBusWithSubwoofer:YES].monitors;
    XCTAssertEqual(monitors.count, 3u);
    XCTAssertEqual(monitors[2].deviceClass, QLMTelemetryClassSubwoofer);
    XCTAssertEqualObjects(monitors[2].serialNumber, @"7350apm21009999");
    XCTAssertEqual(monitors[1].temperature, 41);
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

// docs/adapter-status.md: the adapter at 01 answers its status poll with
// the knob's fields, and its identity queries with text, as in
// captures/startup-idle.
- (void)testTheAdapterAnswersAtItsOwnAddress {
    QLMMessage reply;
    QLMAdapterStatus status;
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:NULL]);
    XCTAssertEqual(QLMReplyAdapterStatus(&reply, &status), QLMAdapterStatusOK);
    XCTAssertTrue(status.knob);
    XCTAssertEqual(status.knobTenths, -1004);

    [_bus perform:^{
        self->_bus.knobTenths = nil;
    }];
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:NULL]);
    XCTAssertEqual(QLMReplyAdapterStatus(&reply, &status), QLMAdapterStatusOK);
    XCTAssertFalse(status.knob);

    // With the mic, the shape is startup-idle-mic's: 32 34 DE DD, then the knob.
    [_bus perform:^{
        self->_bus.knobTenths = @(-775);
        self->_bus.micDE = @(0x1BABFBA0);
        self->_bus.micDD = @(0x00224E4F);
    }];
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyIsAdapterStatus(&reply));
    XCTAssertEqual(QLMReplyAdapterStatus(&reply, &status), QLMAdapterStatusOK);
    XCTAssertTrue(status.mic);
    XCTAssertEqual(status.micDE, 0x1BABFBA0u);
    XCTAssertEqual(status.micDD, 0x00224E4Fu);
    XCTAssertEqual(status.knobTenths, -775);

    char text[QLMPayloadMax];
    char model[32];
    char firmware[32];
    XCTAssertTrue([self send:QLMCommandSystemInfo(QLMAddressAdapter) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertTrue(QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqualObjects(@(model), @"GLM Adapter");
    XCTAssertEqualObjects(@(firmware), @"1.4.0.6113");
    XCTAssertTrue([self send:QLMCommandSerialNumber(QLMAddressAdapter) reply:&reply error:NULL]);
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    XCTAssertEqualObjects(@(text), @"H00000F001");

    [_bus perform:^{
        self->_bus.adapterDropReplies = 1;
    }];
    XCTAssertFalse([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:NULL]);
    XCTAssertTrue([self send:QLMCommandPoll(QLMAddressAdapter) reply:&reply error:NULL]);
}

// While another host has the adapter, nothing goes out.
- (void)testABusyAdapterSendsNothing {
    _bus.busyReason = @"GLM is running.";
    NSError *error = nil;
    XCTAssertFalse([self send:QLMCommandProbe() reply:NULL error:&error]);
    XCTAssertEqual(error.code, QLMAdapterErrorBusy);
    XCTAssertEqualObjects(error.localizedDescription, @"GLM is running.");
    XCTAssertEqual(_bus.sentMessages.count, 0u);
}

// A monitor whose lease ack is lost still holds the lease.
- (void)testALostLeaseAckStillLeases {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    [_bus perform:^{
        self->_left.dropReplies = 1;
    }];
    XCTAssertFalse([self send:QLMCommandAssignSession(leftID, 0x02) reply:NULL error:NULL]);
    XCTAssertEqual(_left.session, 0x02);
    XCTAssertTrue([self send:QLMCommandPoll(0x02) reply:NULL error:NULL]);
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
