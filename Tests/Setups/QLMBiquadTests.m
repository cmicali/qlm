#import <XCTest/XCTest.h>

#include "QLMBiquad.h"

// Sources: the hlm protocol spec, revision 13. Section 5 gives the bypass
// bytes and the slot rates, Appendix A.2 the sign flip, A.3 the RBJ forms
// with Q 0.3 and 0.5 for the shelves, and A.4 the zero-gain bypass.
@interface QLMBiquadTests : XCTestCase
@end

@implementation QLMBiquadTests

- (void)testZeroGainIsTheBypassFromSection5 {
    QLMBiquad peak = QLMBiquadPeak(1000, 0, 1, 48000);
    XCTAssertTrue(QLMBiquadIsBypass(&peak));
    QLMBiquad low = QLMBiquadLowShelf(100, 0, 48000);
    XCTAssertTrue(QLMBiquadIsBypass(&low));
    uint8_t packed[QLMBiquadPackedSize];
    QLMBiquadPack(&peak, packed);
    const uint8_t expected[QLMBiquadPackedSize] = {0x00, 0x00, 0x80, 0x3F};
    XCTAssertEqual(memcmp(packed, expected, sizeof expected), 0);

    // A near-zero gain is not bypassed.
    QLMBiquad nearly = QLMBiquadPeak(1000, -3.1e-5, 1, 48000);
    XCTAssertFalse(QLMBiquadIsBypass(&nearly));
}

// A peak reaches its gain at its frequency and is flat at DC and Nyquist.
- (void)testPeakShape {
    QLMBiquad peak = QLMBiquadPeak(1000, 6, 1, 48000);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&peak, 1000, 48000), pow(10, 6.0 / 20), 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&peak, 0, 48000), 1, 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&peak, 24000, 48000), 1, 1e-9);
    QLMBiquad cut = QLMBiquadPeak(84.29, -7.42, 2.55, 48000);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&cut, 84.29, 48000), pow(10, -7.42 / 20), 1e-9);
}

// A shelf reaches its gain on its side, unity on the other, and half its
// decibels at its frequency.
- (void)testShelfShapes {
    QLMBiquad low = QLMBiquadLowShelf(100, 4, 48000);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&low, 0, 48000), pow(10, 4.0 / 20), 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&low, 24000, 48000), 1, 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&low, 100, 48000), pow(10, 4.0 / 40), 1e-9);

    QLMBiquad high = QLMBiquadHighShelf(500.67, -0.27, 48000);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&high, 24000, 48000), pow(10, -0.27 / 20), 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&high, 0, 48000), 1, 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&high, 500.67, 48000), pow(10, -0.27 / 40), 1e-9);
}

// Section 5: a 12 kHz design read at 48 kHz lands four times higher.
- (void)testTheRateMovesTheFilter {
    QLMBiquad sub = QLMBiquadPeak(40, -6, 10, 12000);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&sub, 40, 12000), pow(10, -6.0 / 20), 1e-9);
    XCTAssertEqualWithAccuracy(QLMBiquadMagnitude(&sub, 160, 48000), pow(10, -6.0 / 20), 1e-9);
    XCTAssertGreaterThan(QLMBiquadMagnitude(&sub, 40, 48000), 0.9);
}

- (void)testStability {
    QLMBiquad peak = QLMBiquadPeak(250.31, 3, 0.7, 48000);
    XCTAssertTrue(QLMBiquadIsStable(&peak));
    QLMBiquad low = QLMBiquadLowShelf(100, -12, 12000);
    XCTAssertTrue(QLMBiquadIsStable(&low));
    QLMBiquad bypass = QLMBiquadBypass();
    XCTAssertTrue(QLMBiquadIsStable(&bypass));
    QLMBiquad poleOutside = {1, 0, 0, 0, 1.5};
    XCTAssertFalse(QLMBiquadIsStable(&poleOutside));
    QLMBiquad realPoleOutside = {1, 0, 0, 2.5, 1};
    XCTAssertFalse(QLMBiquadIsStable(&realPoleOutside));
    // A negative Q designs an unstable peak, which the block must refuse.
    QLMBiquad negativeQ = QLMBiquadPeak(1000, 6, -1, 48000);
    XCTAssertFalse(QLMBiquadIsStable(&negativeQ));
}

// Appendix A.2: five little-endian floats, with a1 and a2 negated.
- (void)testPackFlipsTheFeedbackSigns {
    QLMBiquad biquad = {1, 0, 0, 0.5, 0.25};
    uint8_t packed[QLMBiquadPackedSize];
    QLMBiquadPack(&biquad, packed);
    float floats[5];
    memcpy(floats, packed, sizeof floats);
    XCTAssertEqual(floats[0], 1.0f);
    XCTAssertEqual(floats[1], 0.0f);
    XCTAssertEqual(floats[2], 0.0f);
    XCTAssertEqual(floats[3], -0.5f);
    XCTAssertEqual(floats[4], -0.25f);

    // A regression vector from the A.3 formulas: 1 kHz, +6 dB, Q 1, at 48 kHz.
    QLMBiquad peak = QLMBiquadPeak(1000, 6, 1, 48000);
    QLMBiquadPack(&peak, packed);
    const uint8_t expected[QLMBiquadPackedSize] = {0x41, 0xA0, 0x85, 0x3F, 0xDF, 0x99, 0xF2, 0xBF, 0x0C, 0x23,
                                                    0x5E, 0x3F, 0xDF, 0x99, 0xF2, 0x3F, 0x8F, 0x63, 0x69, 0xBF};
    XCTAssertEqual(memcmp(packed, expected, sizeof expected), 0);
}

@end
