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

static void QLMFillReport(uint8_t report[QLMReportLength], const uint8_t *bytes, size_t length) {
    memset(report, 0, QLMReportLength);
    memcpy(report, bytes, length);
}

- (void)testPacksTheAdapterPollAsCaptured {
    QLMMessage poll = QLMCommandPoll(QLMAddressReply);
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&poll, report), QLMReportOK);
    QLMAssertBytes(report, 6, 0x85, 0x01, 0x08, 0x4D, 0xC6, 0x7E);
    for (size_t i = 6; i < QLMReportLength; i++) {
        XCTAssertEqual(report[i], 0);
    }
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
    for (size_t i = 0; i < QLMReportLength; i++) {
        XCTAssertEqual(report[i], 0);
    }
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
    uint8_t report[QLMReportLength];
    QLMFillReport(report, bytes, sizeof bytes);
    const uint8_t *frame = NULL;
    size_t length = 0;
    XCTAssertEqual(QLMReportUnpackOutput(report, sizeof report, &frame, &length), QLMReportOK);
    QLMAssertBytes(frame, length, 0x01, 0x08, 0x4D, 0xC6, 0x7E);
}

- (void)testUnpackRejectsABadOutputReport {
    uint8_t report[QLMReportLength];
    const uint8_t noPrefix[] = {0x05, 0x01, 0x08, 0x4D, 0xC6, 0x7E};
    QLMFillReport(report, noPrefix, sizeof noPrefix);
    XCTAssertEqual(QLMReportUnpackOutput(report, sizeof report, NULL, NULL), QLMReportErrorPrefix);

    const uint8_t empty[] = {0x80};
    QLMFillReport(report, empty, sizeof empty);
    XCTAssertEqual(QLMReportUnpackOutput(report, sizeof report, NULL, NULL), QLMReportErrorLength);

    const uint8_t tooLong[] = {0xC0};
    QLMFillReport(report, tooLong, sizeof tooLong);
    XCTAssertEqual(QLMReportUnpackOutput(report, sizeof report, NULL, NULL), QLMReportErrorLength);

    const uint8_t padded[] = {0x85, 0x01, 0x08, 0x4D, 0xC6, 0x7E, 0x01};
    QLMFillReport(report, padded, sizeof padded);
    XCTAssertEqual(QLMReportUnpackOutput(report, sizeof report, NULL, NULL), QLMReportErrorPadding);

    XCTAssertEqual(QLMReportUnpackOutput(report, QLMReportLength - 1, NULL, NULL), QLMReportErrorLength);
}

- (void)testAssemblesTheAdapterSystemInfoAcrossTwoReports {
    const uint8_t first[] = {
        0x3F, 0x01, 0x09, 0x63, 0x2D, 0x30, 0x3B, 0x6D, 0x6F, 0x64, 0x65, 0x6C, 0x2D, 0x47, 0x4C, 0x4D,
        0x20, 0x41, 0x64, 0x61, 0x70, 0x74, 0x65, 0x72, 0x3B, 0x76, 0x65, 0x72, 0x2D, 0x31, 0x2E, 0x34,
        0x2E, 0x30, 0x2E, 0x36, 0x31, 0x31, 0x33, 0x3B, 0x68, 0x77, 0x2D, 0x30, 0x2E, 0x30, 0x2E, 0x32,
        0x30, 0x32, 0x3B, 0x62, 0x75, 0x69, 0x6C, 0x64, 0x2D, 0x32, 0x30, 0x32, 0x35, 0x2E, 0x30, 0x35,
    };
    const uint8_t second[] = {0x3F, 0x2E, 0x31, 0x39, 0x2E, 0x73, 0x20, 0x20, 0x00, 0x4D, 0x20, 0x7E};
    uint8_t report[QLMReportLength];
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);

    QLMFillReport(report, first, sizeof first);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportPending);
    QLMFillReport(report, second, sizeof second);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportOK);
    XCTAssertEqual(assembly.length, (size_t)(63 + 11));

    QLMMessage reply;
    XCTAssertEqual(QLMFrameDecode(assembly.frame, assembly.length, &reply), QLMFrameOK);
    char text[QLMPayloadMax];
    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text));
    char model[32];
    char firmware[32];
    XCTAssertTrue(QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware));
    XCTAssertEqualObjects(@(model), @"GLM Adapter");
    XCTAssertEqualObjects(@(firmware), @"1.4.0.6113");
}

- (void)testAssemblesTheNoAnswerFrame {
    const uint8_t bytes[] = {0x3F, 0x01, 0x7D, 0x5E, 0x53, 0x97, 0x7E};
    uint8_t report[QLMReportLength];
    QLMFillReport(report, bytes, sizeof bytes);
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportOK);
    QLMMessage reply;
    XCTAssertEqual(QLMFrameDecode(assembly.frame, assembly.length, &reply), QLMFrameOK);
    XCTAssertTrue(QLMReplyIsNoAnswer(&reply));
    XCTAssertFalse(QLMReplyIsAck(&reply));

    // The next report starts a new frame.
    const uint8_t ack[] = {0x3F, 0x01, 0x09, 0x5D, 0xE7, 0x7E};
    QLMFillReport(report, ack, sizeof ack);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportOK);
    XCTAssertEqual(QLMFrameDecode(assembly.frame, assembly.length, &reply), QLMFrameOK);
    XCTAssertTrue(QLMReplyIsAck(&reply));
    XCTAssertFalse(QLMReplyIsNoAnswer(&reply));
}

- (void)testAssemblyRejectsABadInputReport {
    uint8_t report[QLMReportLength];
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);

    const uint8_t prefix[] = {0x3E, 0x01, 0x09, 0x5D, 0xE7, 0x7E};
    QLMFillReport(report, prefix, sizeof prefix);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportErrorPrefix);

    const uint8_t padded[] = {0x3F, 0x01, 0x09, 0x5D, 0xE7, 0x7E, 0x00, 0x01};
    QLMFillReport(report, padded, sizeof padded);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportErrorPadding);
    XCTAssertEqual(assembly.length, 0u);

    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, QLMReportLength + 1), QLMReportErrorLength);
}

- (void)testAssemblyStopsAfterThreeReportsWithNoFlag {
    uint8_t report[QLMReportLength];
    memset(report, 0x11, sizeof report);
    report[0] = QLMReportInputPrefix;
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportPending);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportPending);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportPending);
    XCTAssertEqual(QLMReportAssemblyAdd(&assembly, report, sizeof report), QLMReportErrorOverflow);
    XCTAssertEqual(assembly.length, 0u);
}

@end
