#import "QLMTestSupport.h"

#include "QLMCommands.h"
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

    // No caller can lease one, or send to 7D or 7E.
    const uint8_t sessions[] = {0x7D, 0x7E, 0xF0};
    for (size_t i = 0; i < sizeof sessions; i++) {
        const uint8_t lease[] = {0x02, 0x11, 0x22, 0x33, sessions[i]};
        XCTAssertFalse(QLMFrameAllows(lease, sizeof lease), @"%02X", sessions[i]);
    }
    const uint8_t shortLease[] = {0x02, 0x11, 0x22, 0x33};
    XCTAssertFalse(QLMFrameAllows(shortLease, sizeof shortLease));
    uint8_t out[QLMFrameMax];
    size_t length = 0;
    QLMMessage toFlag = QLMMakeMessage(QLMFrameFlag, 0x08);
    XCTAssertEqual(QLMFrameEncode(&toFlag, out, sizeof out, &length), QLMFrameErrorForbidden);
    QLMMessage toEscape = QLMMakeMessage(QLMFrameEscape, 0x08);
    XCTAssertEqual(QLMFrameEncode(&toEscape, out, sizeof out, &length), QLMFrameErrorForbidden);
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

// docs/refused-frames.md, "Broadcast 2D 00 and 3D 00 00": GLM sends 2D only
// as 2D 00, and only as a broadcast, right before broadcast 3D 00 00
// (captures/mute-dim, 51.32 s). The allowlist takes exactly that.
- (void)testTheAllowlistTakes2D00OnlyAsABroadcast {
    const uint8_t preamble[] = {0x2D, 0x00};
    XCTAssertTrue(QLMFrameAllows(preamble, sizeof preamble));
    const uint8_t bare[] = {0x2D};
    XCTAssertFalse(QLMFrameAllows(bare, sizeof bare));
    const uint8_t other[] = {0x2D, 0x01};
    XCTAssertFalse(QLMFrameAllows(other, sizeof other));
    const uint8_t longer[] = {0x2D, 0x00, 0x00};
    XCTAssertFalse(QLMFrameAllows(longer, sizeof longer));

    uint8_t out[QLMFrameMax];
    size_t length = 0;
    QLMMessage broadcast = QLMMakeMessage(QLMAddressBroadcast, 0x2D, 0x00);
    XCTAssertEqual(QLMFrameEncode(&broadcast, out, sizeof out, &length), QLMFrameOK);
    const uint8_t addresses[] = {QLMAddressAdapter, QLMAddressSessionFirst, 0x0B, QLMAddressMulticast, QLMAddressSessionLast};
    for (size_t i = 0; i < sizeof addresses; i++) {
        QLMMessage unicast = QLMMakeMessage(addresses[i], 0x2D, 0x00);
        XCTAssertEqual(QLMFrameEncode(&unicast, out, sizeof out, &length), QLMFrameErrorForbidden, @"%02X", addresses[i]);
    }
    QLMMessage otherBroadcast = QLMMakeMessage(QLMAddressBroadcast, 0x2D, 0x01);
    XCTAssertEqual(QLMFrameEncode(&otherBroadcast, out, sizeof out, &length), QLMFrameErrorForbidden);
}

// docs/refused-frames.md, "3C, 3E, and 42, to the subwoofers": GLM sends
// each only to a subwoofer's session, and always with 00 00 (captures/
// startup-idle, 8.910, 8.912, and 8.921 s). The allowlist takes exactly that.
- (void)testTheAllowlistTakesTheSubwooferFramesOnlyAsZerosToASession {
    const uint8_t opcodes[] = {0x3C, 0x3E, 0x42};
    uint8_t out[QLMFrameMax];
    size_t length = 0;
    for (size_t i = 0; i < sizeof opcodes; i++) {
        const uint8_t zeros[] = {opcodes[i], 0x00, 0x00};
        XCTAssertTrue(QLMFrameAllows(zeros, sizeof zeros), @"%02X", opcodes[i]);
        const uint8_t bare[] = {opcodes[i]};
        XCTAssertFalse(QLMFrameAllows(bare, sizeof bare), @"%02X", opcodes[i]);
        const uint8_t shorter[] = {opcodes[i], 0x00};
        XCTAssertFalse(QLMFrameAllows(shorter, sizeof shorter), @"%02X", opcodes[i]);
        const uint8_t value[] = {opcodes[i], 0x00, 0x78};
        XCTAssertFalse(QLMFrameAllows(value, sizeof value), @"%02X", opcodes[i]);
        const uint8_t high[] = {opcodes[i], 0x01, 0x00};
        XCTAssertFalse(QLMFrameAllows(high, sizeof high), @"%02X", opcodes[i]);
        const uint8_t longer[] = {opcodes[i], 0x00, 0x00, 0x00};
        XCTAssertFalse(QLMFrameAllows(longer, sizeof longer), @"%02X", opcodes[i]);

        const uint8_t sessions[] = {QLMAddressSessionFirst, 0x05, 0x0B, QLMAddressSessionLast};
        for (size_t j = 0; j < sizeof sessions; j++) {
            QLMMessage unicast = QLMCommandSubwooferUnknown(sessions[j], opcodes[i]);
            XCTAssertEqual(QLMFrameEncode(&unicast, out, sizeof out, &length), QLMFrameOK, @"%02X to %02X", opcodes[i], sessions[j]);
        }
        const uint8_t others[] = {QLMAddressAdapter, QLMAddressMulticast, QLMAddressBroadcast};
        for (size_t j = 0; j < sizeof others; j++) {
            QLMMessage elsewhere = QLMCommandSubwooferUnknown(others[j], opcodes[i]);
            XCTAssertEqual(QLMFrameEncode(&elsewhere, out, sizeof out, &length), QLMFrameErrorForbidden, @"%02X to %02X", opcodes[i], others[j]);
        }
    }
    QLMMessage other = QLMCommandSubwooferUnknown(0x05, 0x43);
    XCTAssertEqual(QLMFrameEncode(&other, out, sizeof out, &length), QLMFrameErrorForbidden);
}

// docs/refused-frames.md, "43 00 02 and 4B 00 00 00 01, to the 8351B": GLM
// sends each only to an 8351B's session, and always with these bytes
// (captures/startup-idle, 8.650 and 8.725 s). The allowlist takes exactly
// those two payloads.
- (void)testTheAllowlistTakesTheThreeWayFramesOnlyAsCapturedToASession {
    uint8_t out[QLMFrameMax];
    size_t length = 0;
    const uint8_t frame43[] = {0x43, 0x00, 0x02};
    const uint8_t frame4B[] = {0x4B, 0x00, 0x00, 0x00, 0x01};
    XCTAssertTrue(QLMFrameAllows(frame43, sizeof frame43));
    XCTAssertTrue(QLMFrameAllows(frame4B, sizeof frame4B));
    const uint8_t refused[][6] = {
        {0x43}, {0x43, 0x00}, {0x43, 0x00, 0x00}, {0x43, 0x00, 0x01}, {0x43, 0x00, 0x03}, {0x43, 0x01, 0x02},
        {0x43, 0x00, 0x02, 0x00}, {0x4B}, {0x4B, 0x00, 0x00, 0x00}, {0x4B, 0x00, 0x00, 0x00, 0x00},
        {0x4B, 0x00, 0x00, 0x00, 0x02}, {0x4B, 0x01, 0x00, 0x00, 0x01}, {0x4B, 0x00, 0x00, 0x01, 0x01},
        {0x4B, 0x00, 0x00, 0x00, 0x01, 0x00},
    };
    const size_t lengths[] = {1, 2, 3, 3, 3, 3, 4, 1, 4, 5, 5, 5, 5, 6};
    for (size_t i = 0; i < sizeof lengths / sizeof lengths[0]; i++) {
        XCTAssertFalse(QLMFrameAllows(refused[i], lengths[i]), @"entry %zu", i);
    }

    const uint8_t opcodes[] = {0x43, 0x4B};
    const uint8_t values[] = {0x02, 0x01};
    for (size_t i = 0; i < sizeof opcodes; i++) {
        const uint8_t sessions[] = {QLMAddressSessionFirst, 0x03, 0x0C, QLMAddressSessionLast};
        for (size_t j = 0; j < sizeof sessions; j++) {
            QLMMessage unicast = QLMCommandThreeWayUnknown(sessions[j], opcodes[i], values[i]);
            XCTAssertEqual(QLMFrameEncode(&unicast, out, sizeof out, &length), QLMFrameOK, @"%02X to %02X", opcodes[i], sessions[j]);
        }
        const uint8_t others[] = {QLMAddressAdapter, QLMAddressMulticast, QLMAddressBroadcast};
        for (size_t j = 0; j < sizeof others; j++) {
            QLMMessage elsewhere = QLMCommandThreeWayUnknown(others[j], opcodes[i], values[i]);
            XCTAssertEqual(QLMFrameEncode(&elsewhere, out, sizeof out, &length), QLMFrameErrorForbidden, @"%02X to %02X", opcodes[i], others[j]);
        }
        QLMMessage otherValue = QLMCommandThreeWayUnknown(0x03, opcodes[i], values[i] + 1);
        XCTAssertEqual(QLMFrameEncode(&otherValue, out, sizeof out, &length), QLMFrameErrorForbidden, @"%02X", opcodes[i]);
    }
    QLMMessage built43 = QLMCommandThreeWayUnknown(0x03, 0x43, 0x02);
    XCTAssertEqualObjects(QLMBytes(built43.payload, built43.length), QLMBytes(frame43, sizeof frame43));
    QLMMessage built4B = QLMCommandThreeWayUnknown(0x03, 0x4B, 0x01);
    XCTAssertEqualObjects(QLMBytes(built4B.payload, built4B.length), QLMBytes(frame4B, sizeof frame4B));
    QLMMessage other = QLMCommandThreeWayUnknown(0x03, 0x44, 0x02);
    XCTAssertEqual(QLMFrameEncode(&other, out, sizeof out, &length), QLMFrameErrorForbidden);
}

// Section 7 and section 9's group apply: what qlm does send.
- (void)testTheAllowlistAcceptsWhatQLMSends {
    const uint8_t allowed[][5] = {
        {0x02, 0x11, 0x22, 0x33, 0x02}, {0x04}, {0x08}, {0x17, 0x01}, {0x19, 0x01}, {0x1F, 0x7F, 0xFF, 0xFF},
        {0x2B, 0x03}, {0x39}, {0x3A, 0x03, 0x02}, {0x3A, 0x03, 0x7F}, {0x3B, 0x00, 0x5A}, {0x3D, 0x00, 0x00},
        {0x40, 0x00, 0x01, 0x02}, {0xFE}, {0x10, 0x02, 0x00, 0x00}, {0x10, 0x01, 0x00, 0x7F}, {0x10, 0x01, 0x09, 0x00},
        {0x10, 0x0E, 0x00, 0x00},
    };
    const size_t lengths[] = {5, 1, 1, 2, 2, 4, 2, 1, 3, 3, 3, 3, 4, 1, 4, 4, 4, 4};
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
