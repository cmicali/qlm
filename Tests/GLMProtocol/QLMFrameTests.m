#import "QLMTestSupport.h"

#import "QLMFrame.h"

// Sources: the hlm protocol spec, revision 13. Section 1 gives the framing and
// the escaping, section 2 the CRC's place and byte order, section 3 the
// addresses, and section 7 the keep-alive frame `FF 04 BC 84 7E`.
@interface QLMFrameTests : XCTestCase
@end

@implementation QLMFrameTests

- (void)testEncodesTheKeepAliveFromSection7 {
    QLMMessage message = QLMMakeMessage(QLMAddressBroadcast, 0x04);
    uint8_t out[QLMFrameMax];
    size_t length = 0;
    XCTAssertEqual(QLMFrameEncode(&message, out, sizeof out, &length), QLMFrameOK);
    QLMAssertBytes(out, length, 0xFF, 0x04, 0xBC, 0x84, 0x7E);
}

// Section 8.1 gives this standby frame with its CRC `B2 B3`.
- (void)testDecodesTheStandbyTelemetryFromSection8 {
    const uint8_t bytes[] = {0x01, 0x09, 0x41, 0x21, 0x47, 0x03, 0x84, 0x03, 0xA0, 0xB2, 0xB3, 0x7E};
    QLMMessage message;
    XCTAssertEqual(QLMFrameDecode(bytes, sizeof bytes, &message), QLMFrameOK);
    XCTAssertEqual(message.address, QLMAddressReply);
    QLMAssertBytes(message.payload, message.length, 0x09, 0x41, 0x21, 0x47, 0x03, 0x84, 0x03, 0xA0);
}

// Section 1: 7E becomes 7D 5E and 7D becomes 7D 5D, after the CRC is
// computed over the bare bytes. A volume word carries both here.
- (void)testEscapesThePayloadAndRoundTrips {
    QLMMessage message = QLMMakeMessage(QLMAddressBroadcast, 0x1F, 0x7E, 0x7D, 0x00);
    uint8_t out[QLMFrameMax];
    size_t length = 0;
    XCTAssertEqual(QLMFrameEncode(&message, out, sizeof out, &length), QLMFrameOK);
    XCTAssertEqual(length, 10u);
    QLMAssertBytes(out, 6, 0xFF, 0x1F, 0x7D, 0x5E, 0x7D, 0x5D);
    XCTAssertEqual(out[length - 1], QLMFrameFlag);

    QLMMessage decoded;
    XCTAssertEqual(QLMFrameDecode(out, length, &decoded), QLMFrameOK);
    XCTAssertEqual(decoded.address, message.address);
    QLMAssertBytes(decoded.payload, decoded.length, 0x1F, 0x7E, 0x7D, 0x00);
}

// Section 2: the CRC bytes are escaped too when they land on 7E or 7D. The
// payload here is chosen so the CRC's high byte is 7E.
- (void)testEscapesTheCRC {
    // Search for a one-byte mute value whose frame CRC contains 7E or 7D.
    bool found = false;
    for (unsigned value = 0; value < 256 && !found; value++) {
        QLMMessage message = QLMMakeMessage(0x02, 0x2B, (uint8_t)value);
        uint8_t out[QLMFrameMax];
        size_t length = 0;
        XCTAssertEqual(QLMFrameEncode(&message, out, sizeof out, &length), QLMFrameOK);
        if (length == 7) {
            found = true;
            XCTAssertEqual(out[3], QLMFrameEscape);
            QLMMessage decoded;
            XCTAssertEqual(QLMFrameDecode(out, length, &decoded), QLMFrameOK);
            QLMAssertBytes(decoded.payload, decoded.length, 0x2B, (uint8_t)value);
        }
    }
    XCTAssertTrue(found);
}

- (void)testRejectsACorruptFrame {
    QLMMessage message;
    const uint8_t badCRC[] = {0xFF, 0x04, 0xBC, 0x85, 0x7E};
    XCTAssertEqual(QLMFrameDecode(badCRC, sizeof badCRC, &message), QLMFrameErrorCRC);
    const uint8_t noFlag[] = {0xFF, 0x04, 0xBC, 0x84};
    XCTAssertEqual(QLMFrameDecode(noFlag, sizeof noFlag, &message), QLMFrameErrorFlag);
    const uint8_t flagInside[] = {0xFF, 0x7E, 0x04, 0xBC, 0x84, 0x7E};
    XCTAssertEqual(QLMFrameDecode(flagInside, sizeof flagInside, &message), QLMFrameErrorFlag);
    const uint8_t badEscape[] = {0xFF, 0x7D, 0x04, 0xBC, 0x84, 0x7E};
    XCTAssertEqual(QLMFrameDecode(badEscape, sizeof badEscape, &message), QLMFrameErrorEscape);
    const uint8_t tooShort[] = {0xFF, 0xBC, 0x84, 0x7E};
    XCTAssertEqual(QLMFrameDecode(tooShort, sizeof tooShort, &message), QLMFrameErrorLength);
}

// Section 3 gives sessions 02 to FE and the adapter's multicast F0. No
// capture has an address above 19, so whether the adapter escapes an address
// of 7D or 7E is unknown. qlm leases neither.
- (void)testLeasesNoAddressThatNeedsEscapingOrIsTheMulticast {
    NSUInteger leasable = 0;
    for (unsigned address = 0; address <= 0xFF; address++) {
        BOOL expected = address >= 0x02 && address <= 0xFE && address != 0x7D && address != 0x7E && address != 0xF0;
        XCTAssertEqual(QLMAddressIsLeasable((uint8_t)address), expected, @"%02X", address);
        leasable += expected ? 1 : 0;
    }
    XCTAssertEqual(leasable, 250u);
}

- (void)testRefusesABufferThatIsTooSmall {
    QLMMessage message = QLMMakeMessage(QLMAddressBroadcast, 0x04);
    uint8_t out[4];
    size_t length = 99;
    XCTAssertEqual(QLMFrameEncode(&message, out, sizeof out, &length), QLMFrameErrorLength);
    XCTAssertEqual(length, 0u);
}

// The Safety rules in AGENTS.md: never the flash commit (15), the test
// signals (05), or the standalone settings (3A 01, 3A 02, 3A 06). Section 9's
// store sequence also sends the startup level (10 01 05), which qlm never
// writes either.
- (void)testTheAllowlistRefusesWhatQLMNeverSends {
    const uint8_t commit[] = {0x15, 0x33, 0x00};
    XCTAssertFalse(QLMFrameAllows(commit, sizeof commit));
    const uint8_t pink[] = {0x05, 0x04, 0x80};
    XCTAssertFalse(QLMFrameAllows(pink, sizeof pink));
    const uint8_t sleepDelay[] = {0x3A, 0x01, 0x00, 0x00, 0x00, 0x0A};
    XCTAssertFalse(QLMFrameAllows(sleepDelay, sizeof sleepDelay));
    const uint8_t sensitivity[] = {0x3A, 0x02, 0xFF, 0xFF, 0xFF, 0xB5};
    XCTAssertFalse(QLMFrameAllows(sensitivity, sizeof sensitivity));
    const uint8_t led[] = {0x3A, 0x06, 0x00};
    XCTAssertFalse(QLMFrameAllows(led, sizeof led));
    const uint8_t startupLevel[] = {0x10, 0x01, 0x05, 0x00, 0x67, 0x9F};
    XCTAssertFalse(QLMFrameAllows(startupLevel, sizeof startupLevel));
    const uint8_t unknown[] = {0x2D, 0x00, 0x40};
    XCTAssertFalse(QLMFrameAllows(unknown, sizeof unknown));
    XCTAssertFalse(QLMFrameAllows(NULL, 0));

    // The encoder is where the list bites.
    QLMMessage message = QLMMakeMessage(0x02, 0x15, 0x33, 0x00);
    uint8_t out[QLMFrameMax];
    size_t length = 0;
    XCTAssertEqual(QLMFrameEncode(&message, out, sizeof out, &length), QLMFrameErrorForbidden);
    XCTAssertEqual(length, 0u);
}

// Section 7 and section 9's group apply: what qlm does send.
- (void)testTheAllowlistAcceptsWhatQLMSends {
    const uint8_t allowed[][4] = {
        {0x02, 0x11, 0x22, 0x33}, {0x04}, {0x08}, {0x17, 0x01}, {0x19, 0x01}, {0x1F, 0x7F, 0xFF, 0xFF},
        {0x2B, 0x03}, {0x39}, {0x3A, 0x03, 0x02}, {0x3A, 0x03, 0x7F}, {0x3B, 0x00, 0x5A}, {0x3D, 0x00, 0x00},
        {0x40, 0x00, 0x01, 0x02}, {0xFE}, {0x10, 0x02, 0x00, 0x00}, {0x10, 0x01, 0x00, 0x7F}, {0x10, 0x01, 0x09, 0x00},
        {0x10, 0x0E, 0x00, 0x00},
    };
    const size_t lengths[] = {4, 1, 1, 2, 2, 4, 2, 1, 3, 3, 3, 3, 4, 1, 4, 4, 4, 4};
    for (size_t i = 0; i < sizeof lengths / sizeof lengths[0]; i++) {
        XCTAssertTrue(QLMFrameAllows(allowed[i], lengths[i]), @"entry %zu", i);
    }
    const uint8_t bare3A[] = {0x3A};
    XCTAssertFalse(QLMFrameAllows(bare3A, sizeof bare3A));
    const uint8_t bare10[] = {0x10, 0x01};
    XCTAssertFalse(QLMFrameAllows(bare10, sizeof bare10));
}

// Decode is for captures, which hold every opcode GLM sends.
- (void)testDecodeDoesNotConsultTheAllowlist {
    QLMMessage message;
    const uint8_t commit[] = {0x02, 0x15, 0x33, 0x00, 0xB0, 0xB8, 0x7E};
    QLMFrameStatus status = QLMFrameDecode(commit, sizeof commit, &message);
    XCTAssertNotEqual(status, QLMFrameErrorForbidden);
}

@end
