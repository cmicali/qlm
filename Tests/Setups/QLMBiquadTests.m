#import <XCTest/XCTest.h>

#include "QLMBiquad.h"

// Sources: the hlm protocol spec, revision 13. Section 5 gives the bypass
// bytes and the slot rates, Appendix A.2 the sign flip, A.3 the RBJ forms
// with Q 0.3 and 0.5 for the shelves, and A.4 the zero-gain bypass. The
// captured slots come from captures/group-switch-main-2x1-main-4x2 and
// group-switch-main-2x2-main-2x1.
@interface QLMBiquadTests : XCTestCase
@end

@implementation QLMBiquadTests

// The coefficients are single precision, so a shape holds within 0.01 dB.
- (void)assertBiquad:(QLMBiquad)biquad at:(double)frequency rate:(double)sampleRate decibels:(double)decibels {
    XCTAssertEqualWithAccuracy(20 * log10(QLMBiquadMagnitude(&biquad, frequency, sampleRate)), decibels, 0.01);
}

- (void)testZeroGainIsTheBypassFromSection5 {
    QLMBiquad peak = QLMBiquadPeak(1000, 0, 1, 48000);
    XCTAssertTrue(QLMBiquadIsBypass(&peak));
    QLMBiquad low = QLMBiquadLowShelf(100, 0, QLMBiquadLowShelfQ, 48000);
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
    [self assertBiquad:peak at:1000 rate:48000 decibels:6];
    [self assertBiquad:peak at:0 rate:48000 decibels:0];
    [self assertBiquad:peak at:24000 rate:48000 decibels:0];
    [self assertBiquad:QLMBiquadPeak(84.29, -7.42, 2.55, 48000) at:84.29 rate:48000 decibels:-7.42];
}

// A shelf reaches its gain on its side, unity on the other, and half its
// decibels at its frequency.
- (void)testShelfShapes {
    QLMBiquad low = QLMBiquadLowShelf(100, 4, QLMBiquadLowShelfQ, 48000);
    [self assertBiquad:low at:0 rate:48000 decibels:4];
    [self assertBiquad:low at:24000 rate:48000 decibels:0];
    [self assertBiquad:low at:100 rate:48000 decibels:2];

    QLMBiquad high = QLMBiquadHighShelf(500.67, -0.27, QLMBiquadHighShelfQ, 48000);
    [self assertBiquad:high at:24000 rate:48000 decibels:-0.27];
    [self assertBiquad:high at:0 rate:48000 decibels:0];
    [self assertBiquad:high at:500.67 rate:48000 decibels:-0.135];
}

// Section 5: a 12 kHz design read at 48 kHz lands four times higher.
- (void)testTheRateMovesTheFilter {
    QLMBiquad sub = QLMBiquadPeak(40, -6, 10, 12000);
    [self assertBiquad:sub at:40 rate:12000 decibels:-6];
    [self assertBiquad:sub at:160 rate:48000 decibels:-6];
    XCTAssertGreaterThan(QLMBiquadMagnitude(&sub, 40, 48000), 0.9);
}

- (void)testStability {
    QLMBiquad peak = QLMBiquadPeak(250.31, 3, 0.7, 48000);
    XCTAssertTrue(QLMBiquadIsStable(&peak));
    QLMBiquad low = QLMBiquadLowShelf(100, -12, QLMBiquadLowShelfQ, 12000);
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
}

- (void)assertBiquad:(QLMBiquad)biquad packsTo:(NSString *)hex {
    uint8_t packed[QLMBiquadPackedSize];
    QLMBiquadPack(&biquad, packed);
    NSMutableString *actual = [NSMutableString string];
    for (size_t i = 0; i < sizeof packed; i++) {
        [actual appendFormat:@"%@%02X", i == 0 ? @"" : @" ", packed[i]];
    }
    XCTAssertEqualObjects(actual, hex);
}

// GLM's own coefficients, which a design in double normalized in single
// precision gives bit for bit. The 8330A's first peak and second high shelf
// went to 02 at 36.210 s and 36.199 s, and the 7370A's first peak to 05 at
// 36.438 s.
- (void)testNormalizesInSinglePrecisionAsGLMDoes {
    [self assertBiquad:QLMBiquadPeak(250.31, 3, 0.7, 48000) packsTo:@"02 05 81 3F 1D EC FA BF 34 13 74 3F 1D EC FA 3F 39 1D 76 BF"];
    [self assertBiquad:QLMBiquadHighShelf(500.67, -0.27, QLMBiquadHighShelfQ, 48000) packsTo:@"DD 68 78 3F 80 85 E8 BF 47 A6 59 3F F5 DE EF 3F 0F C2 60 BF"];
    [self assertBiquad:QLMBiquadPeak(15.12, -7.33, 6.74, 12000) packsTo:@"94 DE 7F 3F 4E C3 FF BF 24 AC 7F 3F 4E C3 FF 3F B8 8A 7F BF"];
}

// The Left 8351B's second high shelf, 649.91 Hz at -0.63 dB, went to 03 at
// 14.580 s in group-switch-main-2x2-main-2x1. It is a 96 kHz design with a
// Q of 0.3, not the two-way's 0.5.
- (void)testThreeWayHighShelfTakesItsOwnQ {
    QLMBiquad shelf = QLMBiquadHighShelf(649.91, -0.63, QLMBiquadThreeWayHighShelfQ, 96000);
    [self assertBiquad:shelf packsTo:@"38 AB 6E 3F 22 65 DE BF F3 89 4E 3F 08 22 EF 3F F6 AE 5E BF"];
    QLMBiquad twoWayQ = QLMBiquadHighShelf(649.91, -0.63, QLMBiquadHighShelfQ, 96000);
    XCTAssertGreaterThan(fabs(twoWayQ.a1 - shelf.a1), 0.04);
}

@end
