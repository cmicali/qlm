#import "QLMTestSupport.h"

#include "QLMCommands.h"
#include "QLMReplies.h"
#include "QLMReport.h"

// Sources: captures/startup-idle. Its first output report is the adapter poll
// `85 01 08 4D C6 7E`, zero-padded. Its reply to `01 39` is the adapter's
// system info, across two input reports. The no-answer frame `3F 01 7D 5E 53
// 97 7E` follows every probe no monitor answers.
@interface QLMReportTests : XCTestCase
@end

@implementation QLMReportTests

// The bytes, zero-padded to a whole report.
static void QLMFillReport(uint8_t report[QLMReportLength], const uint8_t *bytes, size_t length) {
    memset(report, 0, QLMReportLength);
    memcpy(report, bytes, length);
}

// `frame` points into a buffer that lasts until the next call.
static QLMReportStatus QLMUnpack(const uint8_t *bytes, size_t length, const uint8_t **frame, size_t *frameLength) {
    static uint8_t report[QLMReportLength];
    QLMFillReport(report, bytes, length);
    return QLMReportUnpackOutput(report, sizeof report, frame, frameLength);
}

static QLMReportStatus QLMRead(QLMReportAssembly *assembly, const uint8_t *bytes, size_t length, QLMMessage *reply) {
    uint8_t report[QLMReportLength];
    QLMFillReport(report, bytes, length);
    return QLMReportReadInput(assembly, report, sizeof report, reply);
}

- (void)testPacksTheAdapterPollAsCaptured {
    QLMMessage poll = QLMCommandPoll(QLMAddressReply);
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&poll, report), QLMReportOK);
    const uint8_t expected[] = {0x85, 0x01, 0x08, 0x4D, 0xC6, 0x7E};
    uint8_t padded[QLMReportLength];
    QLMFillReport(padded, expected, sizeof expected);
    XCTAssertEqualObjects(QLMBytes(report, sizeof report), QLMBytes(padded, sizeof padded));
}

// The probe, the lease, and every unicast, the adapter's own 01 included,
// get a reply. Other broadcasts get none. QLMGoldenTests checks the rule
// against every exchange in the captures.
- (void)testWhichMessagesExpectAReply {
    const uint8_t hardwareID[3] = {0x12, 0x2F, 0xAB};
    QLMMessage expecting[] = {QLMCommandProbe(), QLMCommandAssignSession(hardwareID, 0x02), QLMCommandPoll(0x02),
                              QLMCommandPoll(QLMAddressAdapter), QLMCommandSystemInfo(QLMAddressAdapter),
                              QLMCommandMute(QLMAddressAdapter, 0x00)};
    for (size_t i = 0; i < sizeof expecting / sizeof expecting[0]; i++) {
        XCTAssertTrue(QLMReportExpectsReply(&expecting[i]), @"%zu", i);
    }
    QLMMessage silent[] = {QLMCommandKeepAlive(), QLMCommandVolume(-20, -20), QLMCommandPower(QLMPowerStepWakeFirst)};
    for (size_t i = 0; i < sizeof silent / sizeof silent[0]; i++) {
        XCTAssertFalse(QLMReportExpectsReply(&silent[i]), @"%zu", i);
    }
    XCTAssertFalse(QLMReportExpectsReply(NULL));
}

- (void)testPacksAVolumeFrameAsCaptured {
    QLMMessage volume = QLMCommandVolumeWord(0x003107, QLMVolumeWordMax);
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&volume, report), QLMReportOK);
    QLMAssertBytes(report, 9, 0x88, 0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5A, 0x7E);
}

- (void)testRefusesWhatTheAllowlistRefuses {
    uint8_t report[QLMReportLength];
    QLMMessage commit = QLMMakeMessage(0x02, 0x15);
    XCTAssertEqual(QLMReportPackOutput(&commit, report), QLMReportErrorForbidden);
    QLMMessage generator = QLMMakeMessage(0x02, 0x05, 0x04, 0x00, 0x00, 0x00);
    XCTAssertEqual(QLMReportPackOutput(&generator, report), QLMReportErrorForbidden);
    const uint8_t zeros[QLMReportLength] = {0};
    XCTAssertEqualObjects(QLMBytes(report, sizeof report), QLMBytes(zeros, sizeof zeros));
}

// The longest builder, a PEQ band, still fits fully escaped. A longer
// payload of 7E bytes escapes past one report.
- (void)testRefusesAFrameLongerThanOneReport {
    uint8_t coefficients[20];
    memset(coefficients, QLMFrameFlag, sizeof coefficients);
    QLMMessage band = QLMCommandPEQ(0x02, 0x00, coefficients);
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&band, report), QLMReportOK);

    uint8_t payload[32];
    memset(payload, QLMFrameFlag, sizeof payload);
    payload[0] = 0x40;
    QLMMessage routing = QLMMessageMake(0x02, payload, sizeof payload);
    XCTAssertEqual(QLMReportPackOutput(&routing, report), QLMReportErrorLength);
}

- (void)testUnpacksAnOutputReport {
    const uint8_t bytes[] = {0x85, 0x01, 0x08, 0x4D, 0xC6, 0x7E};
    const uint8_t *frame = NULL;
    size_t length = 0;
    XCTAssertEqual(QLMUnpack(bytes, sizeof bytes, &frame, &length), QLMReportOK);
    QLMAssertBytes(frame, length, 0x01, 0x08, 0x4D, 0xC6, 0x7E);
}

- (void)testUnpackRejectsABadOutputReport {
    const uint8_t noPrefix[] = {0x05, 0x01, 0x08, 0x4D, 0xC6, 0x7E};
    XCTAssertEqual(QLMUnpack(noPrefix, sizeof noPrefix, NULL, NULL), QLMReportErrorPrefix);
    const uint8_t empty[] = {0x80};
    XCTAssertEqual(QLMUnpack(empty, sizeof empty, NULL, NULL), QLMReportErrorLength);
    const uint8_t tooLong[] = {0xC0};
    XCTAssertEqual(QLMUnpack(tooLong, sizeof tooLong, NULL, NULL), QLMReportErrorLength);
    const uint8_t padded[] = {0x85, 0x01, 0x08, 0x4D, 0xC6, 0x7E, 0x01};
    XCTAssertEqual(QLMUnpack(padded, sizeof padded, NULL, NULL), QLMReportErrorPadding);

    uint8_t report[QLMReportLength] = {0x85, 0x01, 0x08, 0x4D, 0xC6, 0x7E};
    XCTAssertEqual(QLMReportUnpackOutput(report, QLMReportLength - 1, NULL, NULL), QLMReportErrorLength);
}

- (void)testReadsTheAdapterSystemInfoAcrossTwoReports {
    const uint8_t first[] = {
        0x3F, 0x01, 0x09, 0x63, 0x2D, 0x30, 0x3B, 0x6D, 0x6F, 0x64, 0x65, 0x6C, 0x2D, 0x47, 0x4C, 0x4D,
        0x20, 0x41, 0x64, 0x61, 0x70, 0x74, 0x65, 0x72, 0x3B, 0x76, 0x65, 0x72, 0x2D, 0x31, 0x2E, 0x34,
        0x2E, 0x30, 0x2E, 0x36, 0x31, 0x31, 0x33, 0x3B, 0x68, 0x77, 0x2D, 0x30, 0x2E, 0x30, 0x2E, 0x32,
        0x30, 0x32, 0x3B, 0x62, 0x75, 0x69, 0x6C, 0x64, 0x2D, 0x32, 0x30, 0x32, 0x35, 0x2E, 0x30, 0x35,
    };
    const uint8_t second[] = {0x3F, 0x2E, 0x31, 0x39, 0x2E, 0x73, 0x20, 0x20, 0x00, 0x4D, 0x20, 0x7E};
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMMessage reply;
    XCTAssertEqual(QLMRead(&assembly, first, sizeof first, &reply), QLMReportPending);
    XCTAssertTrue(QLMReportAssemblyIsPending(&assembly));
    XCTAssertEqual(QLMRead(&assembly, second, sizeof second, &reply), QLMReportOK);
    XCTAssertFalse(QLMReportAssemblyIsPending(&assembly));
    XCTAssertEqual(assembly.length, (size_t)(63 + 11));

    char text[QLMPayloadMax];
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    char model[32];
    char firmware[32];
    XCTAssertTrue(QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqualObjects(@(model), @"GLM Adapter");
    XCTAssertEqualObjects(@(firmware), @"1.4.0.6113");
}

- (void)testReadsTheNoAnswerFrame {
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMMessage reply;
    const uint8_t noAnswer[] = {0x3F, 0x01, 0x7D, 0x5E, 0x53, 0x97, 0x7E};
    XCTAssertEqual(QLMRead(&assembly, noAnswer, sizeof noAnswer, &reply), QLMReportNoAnswer);
    XCTAssertTrue(QLMReplyIsNoAnswer(&reply));

    // The next report starts a new frame.
    const uint8_t ack[] = {0x3F, 0x01, 0x09, 0x5D, 0xE7, 0x7E};
    XCTAssertEqual(QLMRead(&assembly, ack, sizeof ack, &reply), QLMReportOK);
    XCTAssertTrue(QLMReplyIsAck(&reply));
}

- (void)testReadRejectsABadInputReport {
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMMessage reply;
    const uint8_t prefix[] = {0x3E, 0x01, 0x09, 0x5D, 0xE7, 0x7E};
    XCTAssertEqual(QLMRead(&assembly, prefix, sizeof prefix, &reply), QLMReportErrorPrefix);
    const uint8_t padded[] = {0x3F, 0x01, 0x09, 0x5D, 0xE7, 0x7E, 0x00, 0x01};
    XCTAssertEqual(QLMRead(&assembly, padded, sizeof padded, &reply), QLMReportErrorPadding);
    const uint8_t badCRC[] = {0x3F, 0x01, 0x09, 0x5D, 0xE8, 0x7E};
    XCTAssertEqual(QLMRead(&assembly, badCRC, sizeof badCRC, &reply), QLMReportErrorFrame);
    XCTAssertFalse(QLMReportAssemblyIsPending(&assembly));

    uint8_t report[QLMReportLength] = {0x3F};
    XCTAssertEqual(QLMReportReadInput(&assembly, report, QLMReportLength + 1, &reply), QLMReportErrorLength);
}

- (void)testReadStopsAfterThreeReportsWithNoFlag {
    uint8_t report[QLMReportLength];
    memset(report, 0x11, sizeof report);
    report[0] = QLMReportInputPrefix;
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMMessage reply;
    for (int i = 0; i < 3; i++) {
        XCTAssertEqual(QLMReportReadInput(&assembly, report, sizeof report, &reply), QLMReportPending);
    }
    XCTAssertEqual(QLMReportReadInput(&assembly, report, sizeof report, &reply), QLMReportErrorOverflow);
    XCTAssertFalse(QLMReportAssemblyIsPending(&assembly));
}

@end
