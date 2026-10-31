#import "QLMTestSupport.h"

#import "QLMReplies.h"

// Sources: the hlm protocol spec, revision 13. Section 8 gives each reply's
// shape and section 8.1 the telemetry tags, with the example frames used here.
@interface QLMRepliesTests : XCTestCase
@end

@implementation QLMRepliesTests

- (void)testAckAndBusy {
    QLMMessage ack = QLMMakeMessage(QLMAddressReply, 0x09);
    XCTAssertTrue(QLMReplyIsAck(&ack));
    XCTAssertFalse(QLMReplyIsBusy(&ack));

    QLMMessage busy = QLMMakeMessage(QLMAddressReply, 0x09, 0x06);
    XCTAssertFalse(QLMReplyIsAck(&busy));
    XCTAssertTrue(QLMReplyIsBusy(&busy));
    QLMMessage busy7 = QLMMakeMessage(QLMAddressReply, 0x09, 0x07);
    XCTAssertTrue(QLMReplyIsBusy(&busy7));

    QLMMessage wrongAddress = QLMMakeMessage(0x02, 0x09);
    XCTAssertFalse(QLMReplyIsAck(&wrongAddress));
    QLMMessage notAReply = QLMMakeMessage(QLMAddressReply, 0x41);
    XCTAssertFalse(QLMReplyIsAck(&notAReply));
}

// Section 8: `09 [SessID]` after an assignment, `09 [ID1] [ID2] [ID3]` after a probe.
- (void)testSessionAckAndHardwareID {
    QLMMessage sessionAck = QLMMakeMessage(QLMAddressReply, 0x09, 0x05);
    uint8_t session = 0;
    XCTAssertTrue(QLMReplySessionAck(&sessionAck, &session));
    XCTAssertEqual(session, 0x05);

    QLMMessage idReply = QLMMakeMessage(QLMAddressReply, 0x09, 0xAA, 0xBB, 0xCC);
    uint8_t hardwareID[3] = {0, 0, 0};
    XCTAssertTrue(QLMReplyHardwareID(&idReply, hardwareID));
    QLMAssertBytes(hardwareID, 3, 0xAA, 0xBB, 0xCC);
    XCTAssertFalse(QLMReplySessionAck(&idReply, &session));
    XCTAssertFalse(QLMReplyHardwareID(&sessionAck, hardwareID));
}

// Section 8.1's two-way ON frame.
- (void)testTelemetryTwoWay {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x26, 0x81, 0x00, 0x24, 0x83, 0x00, 0x24, 0x42, 0xE2,
                                        0x43, 0xAF, 0x45, 0xCB, 0x47, 0x01, 0x84, 0x02, 0xB0);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&message, &t), QLMTelemetryOK);
    XCTAssertFalse(t.busy);
    XCTAssertEqual(t.temperature, 0x26);
    XCTAssertEqual(t.sensor81, 0x24);
    XCTAssertEqual(t.sensor83, 0x24);
    XCTAssertEqual(t.inputMeter, 0xE2);
    XCTAssertEqual(t.hfMeter, 0xAF);
    XCTAssertEqual(t.lfMeter, 0xCB);
    XCTAssertEqual(t.status, QLMTelemetryStatusOn);
    XCTAssertEqual(t.deviceClass, QLMTelemetryClassTwoWay);
    XCTAssertEqual(t.stateMetric, 0xB0);
    XCTAssertEqual(t.midMeter, QLMTelemetryAbsent);
    XCTAssertEqual(t.subMeter, QLMTelemetryAbsent);
    XCTAssertEqual(t.unknownTag, 0);
}

// Section 8.1's subwoofer ON frame: tag 46 present, 81 absent.
- (void)testTelemetrySubwoofer {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x26, 0x83, 0x00, 0x26, 0x42, 0x94, 0x46, 0x93, 0x43,
                                        0x80, 0x45, 0x92, 0x47, 0x01, 0x84, 0x01, 0x66);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&message, &t), QLMTelemetryOK);
    XCTAssertEqual(t.subMeter, 0x93);
    XCTAssertEqual(t.hfMeter, 0x80);
    XCTAssertEqual(t.sensor81, QLMTelemetryAbsent);
    XCTAssertEqual(t.deviceClass, QLMTelemetryClassSubwoofer);
}

// Section 8.1's OFF and standby frames: the audio tags are dropped and 47 is
// not 01. Section 8: a 06 or 07 before the 41 marks a busy monitor.
- (void)testTelemetryOffStandbyAndBusy {
    QLMMessage off = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x26, 0x47, 0x02, 0x84, 0x02, 0xF0);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&off, &t), QLMTelemetryOK);
    XCTAssertEqual(t.status, QLMTelemetryStatusStandby);
    XCTAssertEqual(t.inputMeter, QLMTelemetryAbsent);

    QLMMessage standby = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x1C, 0x47, 0x02, 0x84, 0x03, 0x8E);
    XCTAssertEqual(QLMReplyTelemetry(&standby, &t), QLMTelemetryOK);
    XCTAssertEqual(t.temperature, 0x1C);
    XCTAssertEqual(t.deviceClass, QLMTelemetryClassStandby);

    QLMMessage hlmStandby = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x21, 0x47, 0x03, 0x84, 0x03, 0xA0);
    XCTAssertEqual(QLMReplyTelemetry(&hlmStandby, &t), QLMTelemetryOK);
    XCTAssertEqual(t.status, 0x03);
    XCTAssertNotEqual(t.status, QLMTelemetryStatusOn);

    QLMMessage busy = QLMMakeMessage(QLMAddressReply, 0x09, 0x07, 0x41, 0x26, 0x47, 0x01, 0x84, 0x02, 0xB2);
    XCTAssertEqual(QLMReplyTelemetry(&busy, &t), QLMTelemetryOK);
    XCTAssertTrue(t.busy);
    XCTAssertEqual(t.status, QLMTelemetryStatusOn);
}

// A tag the spec does not list has no length byte, so the walk must stop
// there and keep what came before it.
- (void)testTelemetryStopsAtAnUnknownTag {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x26, 0x47, 0x01, 0x99, 0x00, 0x84, 0x02, 0xB0);
    QLMTelemetry t;
    XCTAssertEqual(QLMReplyTelemetry(&message, &t), QLMTelemetryErrorUnknownTag);
    XCTAssertEqual(t.unknownTag, 0x99);
    XCTAssertEqual(t.status, QLMTelemetryStatusOn);
    XCTAssertEqual(t.deviceClass, QLMTelemetryAbsent);
}

- (void)testTelemetryRejectsTruncatedAndForeignFrames {
    QLMTelemetry t;
    QLMMessage noValue = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x26, 0x84, 0x02);
    XCTAssertEqual(QLMReplyTelemetry(&noValue, &t), QLMTelemetryErrorTruncated);
    QLMMessage noTemperature = QLMMakeMessage(QLMAddressReply, 0x09, 0x41);
    XCTAssertEqual(QLMReplyTelemetry(&noTemperature, &t), QLMTelemetryErrorTruncated);
    QLMMessage ack = QLMMakeMessage(QLMAddressReply, 0x09);
    XCTAssertEqual(QLMReplyTelemetry(&ack, &t), QLMTelemetryErrorNotTelemetry);
    XCTAssertEqual(QLMReplyTelemetry(NULL, &t), QLMTelemetryErrorNotTelemetry);
}

// Section 8: the system info is NUL-terminated ASCII after the 09, and the
// serial is 15 ASCII characters with no NUL.
- (void)testTextReplies {
    QLMMessage info = QLMMakeMessage(QLMAddressReply, 0x09, 'c', '-', '1', ';', 'm', 'o', 'd', 'e', 'l', '-', '8', '3', '2',
                                     '0', 'A', 0x00);
    char text[32];
    XCTAssertTrue(QLMReplyText(&info, text, sizeof text));
    XCTAssertEqual(strcmp(text, "c-1;model-8320A"), 0);

    QLMMessage serial = QLMMakeMessage(QLMAddressReply, 0x09, '8', '3', '2', '0', 'a', 'p', 'm', '2', '1', '0', '0', '1', '2',
                                       '3', '4');
    XCTAssertTrue(QLMReplyText(&serial, text, sizeof text));
    XCTAssertEqual(strlen(text), 15u);
    XCTAssertEqual(strcmp(text, "8320apm21001234"), 0);

    QLMMessage busyText = QLMMakeMessage(QLMAddressReply, 0x09, 0x06, 'o', 'k', 0x00);
    XCTAssertTrue(QLMReplyText(&busyText, text, sizeof text));
    XCTAssertEqual(strcmp(text, "ok"), 0);

    char small[4];
    XCTAssertFalse(QLMReplyText(&serial, small, sizeof small));
    QLMMessage binary = QLMMakeMessage(QLMAddressReply, 0x09, 0x41, 0x1B);
    XCTAssertFalse(QLMReplyText(&binary, text, sizeof text));
    QLMMessage ack = QLMMakeMessage(QLMAddressReply, 0x09);
    XCTAssertFalse(QLMReplyText(&ack, text, sizeof text));
}

// Section 8 gives the system info two forms: semicolon-separated fields
// with model- and ver-, and space-delimited with the model first.
- (void)testSystemInfoParse {
    char model[16];
    char firmware[16];
    XCTAssertTrue(QLMSystemInfoParse("c-1;model-7350A;ver-1.14.7;hw-2;build-3733", model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqual(strcmp(model, "7350A"), 0);
    XCTAssertEqual(strcmp(firmware, "1.14.7"), 0);

    XCTAssertTrue(QLMSystemInfoParse("c-1;model-8320A", model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqual(strcmp(model, "8320A"), 0);
    XCTAssertEqual(strcmp(firmware, ""), 0);

    XCTAssertTrue(QLMSystemInfoParse("7350A 1 0000 0106 3733", model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqual(strcmp(model, "7350A"), 0);
    XCTAssertEqual(strcmp(firmware, ""), 0);

    XCTAssertFalse(QLMSystemInfoParse("c-1;ver-1.14.7", model, sizeof model, firmware, sizeof firmware));
    XCTAssertFalse(QLMSystemInfoParse("", model, sizeof model, firmware, sizeof firmware));
    char tiny[4];
    XCTAssertFalse(QLMSystemInfoParse("c-1;model-7350A", tiny, sizeof tiny, firmware, sizeof firmware));
}

// docs/adapter-status.md, "The reply's layout": startup-idle's first reply,
// the knob at -100.4 dB and no mic (7.29 s).
- (void)testAdapterStatusWithTheKnob {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x30, 0x36, 0xDF, 0xFF, 0xFF, 0xFC, 0x14);
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&message, &status), QLMAdapterStatusOK);
    XCTAssertTrue(status.knob);
    XCTAssertFalse(status.mic);
    XCTAssertTrue(status.hasKnobPosition);
    XCTAssertEqual(status.knobTenths, -1004);
    XCTAssertEqual(status.unknownTag, 0);
}

// The same, with the knob at the top stop and the mic in (knob-sweep,
// 20.17 s), and with neither (volume-sweep, from 25.44 s).
- (void)testAdapterStatusWithTheMicAndWithNeither {
    QLMMessage withMic = QLMMakeMessage(QLMAddressReply, 0x09, 0x32, 0x34, 0xDE, 0x00, 0x23, 0x10, 0x00, 0xDD, 0x00, 0x22, 0x00,
                                        0x01, 0x30, 0x36, 0xDF, 0x00, 0x00, 0x00, 0x00);
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&withMic, &status), QLMAdapterStatusOK);
    XCTAssertTrue(status.mic);
    XCTAssertTrue(status.knob);
    XCTAssertEqual(status.knobTenths, 0);
    XCTAssertTrue(status.hasMicDE);
    XCTAssertTrue(status.hasMicDD);
    XCTAssertEqual(status.micDE, 0x00231000u);
    XCTAssertEqual(status.micDD, 0x00220001u);

    QLMMessage neither = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x31);
    XCTAssertEqual(QLMReplyAdapterStatus(&neither, &status), QLMAdapterStatusOK);
    XCTAssertFalse(status.knob);
    XCTAssertFalse(status.hasKnobPosition);
    XCTAssertFalse(status.mic);
    XCTAssertFalse(status.hasMicDE);
    XCTAssertFalse(status.hasMicDD);
}

// Hand-built: the mic in with neither reading, a shape no capture has. The
// knob is startup-idle's, at -100.4 dB (7.29 s). A missing reading is not a 0.
- (void)testAdapterStatusWithTheMicAndNoReadings {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x32, 0x34, 0x30, 0x36, 0xDF, 0xFF, 0xFF, 0xFC, 0x14);
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&message, &status), QLMAdapterStatusOK);
    XCTAssertTrue(status.mic);
    XCTAssertFalse(status.hasMicDE);
    XCTAssertFalse(status.hasMicDD);
    XCTAssertEqual(status.knobTenths, -1004);
    XCTAssertFalse(QLMReplyIsAdapterStatus(&message));
}

// The tag rule steps over a tag it does not know, by its top two bits.
- (void)testAdapterStatusStepsOverAnUnknownTag {
    QLMMessage message = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x75, 0xDF, 0x30, 0x36, 0xDF, 0xFF, 0xFF, 0xFF, 0x9C);
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&message, &status), QLMAdapterStatusOK);
    XCTAssertEqual(status.unknownTag, 0x75);
    XCTAssertEqual(status.knobTenths, -100);

    QLMMessage truncated = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x30, 0x36, 0xDF, 0xFF, 0xFF);
    XCTAssertEqual(QLMReplyAdapterStatus(&truncated, &status), QLMAdapterStatusErrorTruncated);
    QLMMessage ack = QLMMakeMessage(QLMAddressReply, 0x09);
    XCTAssertEqual(QLMReplyAdapterStatus(&ack, &status), QLMAdapterStatusErrorNotStatus);
    QLMMessage fromMonitor = QLMMakeMessage(0x02, 0x09, 0x33, 0x31);
    XCTAssertEqual(QLMReplyAdapterStatus(&fromMonitor, &status), QLMAdapterStatusErrorNotStatus);
}

// docs/adapter-status.md's three shapes, and the mic without the knob, are
// a status. The walk reads a serial as one too, and so would a lease ack
// for session 33, but neither has a shape. QLMGoldenTests checks every reply.
- (void)testOnlyTheStatusShapesAreAStatus {
    QLMMessage knob = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x30, 0x36, 0xDF, 0xFF, 0xFF, 0xFC, 0x14);
    QLMMessage micAndKnob = QLMMakeMessage(QLMAddressReply, 0x09, 0x32, 0x34, 0xDE, 0x00, 0x23, 0x10, 0x00, 0xDD, 0x00, 0x22,
                                           0x00, 0x01, 0x30, 0x36, 0xDF, 0x00, 0x00, 0x00, 0x00);
    QLMMessage neither = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x31);
    QLMMessage micOnly = QLMMakeMessage(QLMAddressReply, 0x09, 0x32, 0x34, 0xDE, 0x00, 0x23, 0x10, 0x00, 0xDD, 0x00, 0x22, 0x00,
                                        0x01, 0x31);
    XCTAssertTrue(QLMReplyIsAdapterStatus(&knob));
    XCTAssertTrue(QLMReplyIsAdapterStatus(&micAndKnob));
    XCTAssertTrue(QLMReplyIsAdapterStatus(&neither));
    XCTAssertTrue(QLMReplyIsAdapterStatus(&micOnly));

    QLMMessage serial = QLMMakeMessage(QLMAddressReply, 0x09, 'H', '9', '9', '9', '9', '9', 'F', '0', '0', '0');
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&serial, &status), QLMAdapterStatusOK);
    XCTAssertFalse(QLMReplyIsAdapterStatus(&serial));
    QLMMessage lease = QLMMakeMessage(QLMAddressReply, 0x09, 0x33);
    XCTAssertFalse(QLMReplyIsAdapterStatus(&lease));
    QLMMessage trailing = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x31, 0x00);
    XCTAssertFalse(QLMReplyIsAdapterStatus(&trailing));
    QLMMessage truncated = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x30, 0x36, 0xDF, 0xFF, 0xFF);
    XCTAssertFalse(QLMReplyIsAdapterStatus(&truncated));
    QLMMessage fromMonitor = QLMMakeMessage(0x02, 0x09, 0x33, 0x31);
    XCTAssertFalse(QLMReplyIsAdapterStatus(&fromMonitor));
}

// startup-idle, 7.30 s: the adapter's system info, and its serial.
- (void)testOnlySystemInfoTextIsSystemInfo {
    QLMMessage info = QLMMakeMessage(QLMAddressReply, 0x09, 'c', '-', '0', ';', 'm', 'o', 'd', 'e', 'l', '-', 'G', 'L', 'M', 0x00);
    QLMMessage serial = QLMMakeMessage(QLMAddressReply, 0x09, 'H', '9', '9', '9', '9', '9', 'F', '0', '0', '0');
    QLMMessage status = QLMMakeMessage(QLMAddressReply, 0x09, 0x33, 0x31);
    XCTAssertTrue(QLMReplyIsSystemInfo(&info));
    XCTAssertFalse(QLMReplyIsSystemInfo(&serial));
    XCTAssertFalse(QLMReplyIsSystemInfo(&status));
}

@end
