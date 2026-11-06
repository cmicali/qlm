#import "QLMTestSupport.h"

#include <math.h>

#include "QLMBiquad.h"
#include "QLMCommands.h"
#include "QLMDescribe.h"
#import "QLMDSPBlock.h"

// The traffic window's words for each frame. Each fact names its source: a
// capture's frame, or a section of hlm's spec, as docs/protocol.md gives it.
@interface QLMDescribeTests : XCTestCase
@end

@implementation QLMDescribeTests

static NSString *QLMRequestText(QLMMessage message, double ceiling, double rate) {
    QLMDescribeContext context = {ceiling, rate};
    char text[QLMDescriptionMax];
    QLMDescribeRequest(&message, &context, text, sizeof text);
    return @(text);
}

static NSString *QLMPlainRequestText(QLMMessage message) {
    return QLMRequestText(message, NAN, 0);
}

static NSString *QLMReplyText(QLMMessage reply, const QLMMessage *request) {
    char text[QLMDescriptionMax];
    QLMDescribeReply(&reply, request, text, sizeof text);
    return @(text);
}

#pragma mark - Addresses

// docs/protocol.md, The addresses: hlm §3.
- (void)testTheAddresses {
    char text[32];
    QLMDescribeAddress(0xFF, text, sizeof text);
    XCTAssertEqualObjects(@(text), @"broadcast FF");
    QLMDescribeAddress(0xF0, text, sizeof text);
    XCTAssertEqualObjects(@(text), @"adapter multicast F0");
    QLMDescribeAddress(0x01, text, sizeof text);
    XCTAssertEqualObjects(@(text), @"adapter 01");
    QLMDescribeAddress(0x0B, text, sizeof text);
    XCTAssertEqualObjects(@(text), @"session 0B");
}

#pragma mark - Requests

// The probe, hlm §7 and startup-idle at 8.419 s. The lease, hlm §7. The
// keep-alive, startup-idle at 8.534 s. 03, setup-b-peq-8351b at 22.461 s.
- (void)testDiscoveryAndTheLease {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandProbe()), @"probe");
    const uint8_t hardwareID[3] = {0x12, 0x34, 0x56};
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandAssignSession(hardwareID, 0x0B)), @"lease session 0B to hardware ID 12 34 56");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandKeepAlive()), @"keep-alive");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0xFF, 0x03)), @"drop every lease");
}

// A lease is F0 02, the hardware ID, and the session (hlm §7). Only a lease
// names a monitor by its ID.
- (void)testTheLeaseReaderReadsOnlyALease {
    const uint8_t hardwareID[3] = {0x12, 0x34, 0x56};
    QLMMessage lease = QLMCommandAssignSession(hardwareID, 0x0B);
    uint8_t read[3] = {0};
    XCTAssertTrue(QLMLeaseHardwareID(&lease, read));
    QLMAssertBytes(read, 3, 0x12, 0x34, 0x56);
    QLMMessage probe = QLMCommandProbe();
    XCTAssertFalse(QLMLeaseHardwareID(&probe, read));
    QLMMessage elsewhere = lease;
    elsewhere.address = 0x0B;
    XCTAssertFalse(QLMLeaseHardwareID(&elsewhere, read));
}

// The poll to a session, hlm §7. The status poll to 01, docs/adapter-status.md.
// The serial and system info, startup-idle at 7.304 and 7.299 s.
- (void)testThePollsAndTheQueries {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPoll(0x0B)), @"poll");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPoll(QLMAddressAdapter)), @"status poll");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandSerialNumber(0x0B)), @"ask for the serial");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandSystemInfo(QLMAddressAdapter)), @"ask for system info");
}

// 7F FF FF is 0 dB, hlm §4. 0C CC CC is -20 dB, quit-glm at 0.3 s. 00 00 08
// is the bottom stop, volume-sweep at 28.36 s. 00 00 02 is the duck,
// group-switch-main-4x2-main-2x1 at 12.359 s. Every step is the table's.
- (void)testTheVolume {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0xFF, 0x1F, 0x7F, 0xFF, 0xFF)), @"volume 0.0 dB");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0xFF, 0x1F, 0x0C, 0xCC, 0xCC)), @"volume −20.0 dB");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0xFF, 0x1F, 0x00, 0x31, 0x07)), @"volume −56.5 dB");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0xFF, 0x1F, 0x00, 0x00, 0x08)), @"volume −100 dB, the bottom stop");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandDuck()), @"duck under an apply, 00 00 02, below the bottom stop");
    XCTAssertTrue([QLMPlainRequestText(QLMMakeMessage(0xFF, 0x1F, 0x0C, 0xCC, 0xCD)) hasSuffix:@"not one of GLM's steps"]);
    for (double decibels = 0; decibels > -100; decibels -= 0.5) {
        NSString *text = QLMPlainRequestText(QLMCommandVolume(decibels, 0));
        XCTAssertFalse([text containsString:@"not one of"], @"%@ at %.1f", text, decibels);
    }
}

// The builder clamps to the ceiling (testEveryVolumeBuilderHonorsTheCeiling),
// so a frame at it says so. One above it never goes out, and says so loudly.
- (void)testAVolumeAtTheCeilingSaysSo {
    XCTAssertEqualObjects(QLMRequestText(QLMCommandVolume(-10, -30), -30, 0), @"volume −30.0 dB, held at the ceiling");
    XCTAssertEqualObjects(QLMRequestText(QLMCommandVolume(-42.5, -30), -30, 0), @"volume −42.5 dB");
    XCTAssertEqualObjects(QLMRequestText(QLMCommandVolume(-20, 0), -30, 0), @"volume −20.0 dB, ABOVE the ceiling −30.0 dB");
}

// 03 muted, 04 unmuted, 05 then 07 outside the group: mute-dim, and
// knob-sweep at 19.135 s. The adapter's 2B 01 and 2B 00: mute-dim at 46.189
// and 48.596 s.
- (void)testMuteAndTheLED {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMute(0x0B, QLMMuteValueMuted)), @"mute on");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMute(0x0B, QLMMuteValueUnmuted)), @"mute off");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMute(0x0B, QLMMuteValueOutsideLead)), @"outside the group, first of two");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMute(0x0B, QLMMuteValueOutside)), @"outside the group");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMute(QLMAddressAdapter, 0x01)), @"adapter's mute on, as mute all sends it");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMute(QLMAddressAdapter, 0x00)), @"adapter's mute off");
    XCTAssertTrue([QLMPlainRequestText(QLMCommandMute(0x0B, 0x09)) containsString:@"a value GLM never sends"]);
}

// 3A 03's steps, hlm §7.
- (void)testPower {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPower(QLMPowerStepStandbyPrepare)), @"power: prepare for standby");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPower(QLMPowerStepPowerOff)), @"power: off to standby");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPower(QLMPowerStepWakeFirst)), @"power: wake, first step");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandMonitorPower(0x0B, QLMPowerStepWakeSecond)), @"power: wake, second step");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0x0B, 0x3A, 0x01)), @"standalone setting 3A 01, refused by qlm");
}

// The block. 17 01, startup-idle at 8.538 s. 6 ms is 288 samples,
// group-switch-main-2x1-main-4x2. The level word, hlm §6. 3B 00 55 is
// 85 Hz, refused-frames.md. AES3 A and B is 40 00 02 00 03, and a
// subwoofer's second routing 40 01 02 00 00, group-switch-main-2x1-main-4x2.
// 3C, 3E, 42, 43, 4B, 2D, and 3D are unknown, refused-frames.md.
- (void)testTheBlock {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPrepare(0x0B)), @"17 01, first in a block, meaning unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandDelay(0x0B, 288)), @"delay 288 samples, 6 ms at 48 kHz");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandLevel(0x0B, QLMVolumeWordMax)), @"level 0.00 dB");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandLevel(0x0B, QLMLevelWordForDecibels(-3.5))), @"level −3.50 dB");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandLevelUnknown(0x0B)), @"10 01 09 00 00 00, meaning unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandCrossover(0x0B, 0x55)), @"crossover 85 Hz");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandInputSync(0x0B)), @"3D 00 00, meaning unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandRouting(0x0B, 0, 2, 0, 3)), @"routing: AES3, channel A and B");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandRouting(0x0B, 1, 2, 0, 0)),
                          @"routing 40 01 02 00 00, as GLM sends each subwoofer, meaning unknown");
    XCTAssertTrue([QLMPlainRequestText(QLMCommandRouting(0x0B, 3, 1, 0, 0)) hasSuffix:@"unverified"]);
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandSubwooferUnknown(0x0B, 0x3E)), @"3E 00 00, as GLM sends a subwoofer, meaning unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandThreeWay43(0x0B, 2)), @"43 00 02, as GLM sends the 8351B, meaning unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandThreeWay4B(0x0B, 1)), @"4B 00 00 00 01, as GLM sends the 8351B, meaning unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandInputPreamble()), @"2D 00, before 3D 00 00, meaning unknown");
}

// What qlm refuses still reads in a capture: the generator stop, hlm §7;
// 01 22 and 01 51 82, refused-frames.md. A form no doc gives is unknown.
- (void)testRefusedAndUnknownFrames {
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0x0B, 0x05, 0x04, 0x00)), @"generator stop, refused by qlm");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0x01, 0x22)), @"ask for the adapter's identity, refused by qlm");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0x01, 0x51, 0x82)), @"51 82, meaning unknown, refused by qlm");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0x0B, 0x15)), @"flash commit, refused by qlm");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0x0B, 0x77, 0x01)), @"opcode 77 with 2 bytes, unknown");
    XCTAssertEqualObjects(QLMPlainRequestText(QLMMakeMessage(0xFF, 0x1F, 0x01)), @"opcode 1F with 2 bytes, unknown");
}

#pragma mark - PEQ bands

// A flat band is 1, 0, 0, 0, 0: hlm §5, startup-idle at 8.553 s.
- (void)testAFlatBand {
    QLMBiquad flat = QLMBiquadBypass();
    uint8_t packed[QLMBiquadPackedSize];
    QLMBiquadPack(&flat, packed);
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPEQ(0x0B, 5, packed)), @"PEQ slot 05: flat");
}

- (void)assertBand:(QLMBiquad)biquad shape:(QLMBandShape)shape frequency:(double)frequency q:(double)q gain:(double)gain rate:(double)rate {
    uint8_t packed[QLMBiquadPackedSize];
    QLMBiquadPack(&biquad, packed);
    QLMBandReading band = QLMReadPEQBand(packed, rate);
    XCTAssertEqual(band.shape, shape, @"%.1f Hz Q %.2f %.1f dB at %.0f", frequency, q, gain, rate);
    XCTAssertEqualWithAccuracy(band.frequency, frequency, frequency * fmax(2e-3, 2 * band.spread), @"%.1f Hz at %.0f", frequency, rate);
    XCTAssertEqualWithAccuracy(band.q, q, q * fmax(1e-2, 2 * band.spread), @"%.1f Hz Q %.2f at %.0f", frequency, q, rate);
    XCTAssertEqualWithAccuracy(band.gainDecibels, gain, 0.02, @"%.1f Hz %.1f dB at %.0f", frequency, gain, rate);
}

// The peak and the shelves are RBJ's, with the shelves' fixed Qs
// (QLMBiquad.h). The read inverts every design across the range the
// 8351B's bands were captured over: 25 Hz to 18 kHz, -20 to +6 dB, Q 0.1
// to 20 (setup-b-peq-8351b), at each design rate (hlm §4).
- (void)testEveryDesignReadsBack {
    const double rates[] = {12000, 48000, 96000};
    const double gains[] = {-20, -3, 1.5, 6};
    for (size_t r = 0; r < 3; r++) {
        double rate = rates[r];
        for (double frequency = 25; frequency < rate * 0.2 && frequency <= 18000; frequency *= 2.3) {
            for (size_t g = 0; g < 4; g++) {
                double gain = gains[g];
                for (double q = 0.1; q <= 20; q *= 3.3) {
                    [self assertBand:QLMBiquadPeak(frequency, gain, q, rate) shape:QLMBandShapePeak frequency:frequency q:q gain:gain rate:rate];
                }
                [self assertBand:QLMBiquadLowShelf(frequency, gain, QLMBiquadLowShelfQ, rate)
                           shape:QLMBandShapeLowShelf frequency:frequency q:QLMBiquadLowShelfQ gain:gain rate:rate];
                [self assertBand:QLMBiquadHighShelf(frequency, gain, QLMBiquadHighShelfQ, rate)
                           shape:QLMBandShapeHighShelf frequency:frequency q:QLMBiquadHighShelfQ gain:gain rate:rate];
            }
        }
    }
}

- (void)testABandReadsInWords {
    QLMBiquad peak = QLMBiquadPeak(1000, -3, 2, 48000);
    uint8_t packed[QLMBiquadPackedSize];
    QLMBiquadPack(&peak, packed);
    QLMMessage frame = QLMCommandPEQ(0x0B, 5, packed);
    XCTAssertEqualObjects(QLMRequestText(frame, NAN, 48000), @"PEQ slot 05: peak 1 kHz, Q 2, −3.0 dB");
    XCTAssertEqualObjects(QLMRequestText(frame, NAN, 0), @"PEQ slot 05: peak 0.02083 of the design rate, Q 2, −3.0 dB");
    QLMBiquad low = QLMBiquadPeak(25, -3, 2, 96000);
    QLMBiquadPack(&low, packed);
    XCTAssertTrue([QLMRequestText(QLMCommandPEQ(0x0B, 5, packed), NAN, 96000) hasPrefix:@"PEQ slot 05: peak about 2"],
                  @"a band near DC reads loosely, and says so");
    uint8_t unstable[QLMBiquadPackedSize] = {0};
    XCTAssertEqualObjects(QLMPlainRequestText(QLMCommandPEQ(0x0B, 1, unstable)), @"PEQ slot 01: no peak or shelf, unknown");
}

// Every band of every node in the fixture setup reads back as the file
// states it. qlm's blocks match GLM's frames for this setup bit for bit
// (QLMDSPBlockGoldenTests), so these are GLM's frames too.
- (void)testEveryBandOfTheFixtureReadsAsTheFileStatesIt {
    NSUInteger read = 0;
    for (QLMSetupGroup *group in QLMReadFixtureSetup().groups) {
        for (QLMSetupNode *node in group.nodes) {
            QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:NULL];
            if (block == nil) {
                continue;
            }
            NSMutableDictionary<NSNumber *, NSData *> *slots = [NSMutableDictionary dictionary];
            for (NSData *payload in block.payloads) {
                const uint8_t *bytes = payload.bytes;
                if (payload.length == 24 && bytes[0] == 0x10 && bytes[1] == 0x0E) {
                    slots[@(bytes[2])] = payload;
                }
            }
            for (QLMSetupBand *band in node.bands) {
                NSInteger slot = node.nodeClass == QLMSetupNodeClassSubwoofer ? band.index - 1
                               : band.type == QLMSetupBandLowShelf ? band.index - 1
                               : band.type == QLMSetupBandHighShelf ? 2 + band.index - 1
                                                                    : 4 + band.index - 1;
                NSData *payload = slots[@(slot)];
                XCTAssertNotNil(payload);
                QLMBandReading reading = QLMReadPEQBand((const uint8_t *)payload.bytes + 3, band.sampleRate);
                if (band.gain == 0) {
                    XCTAssertEqual(reading.shape, QLMBandShapeFlat);
                    continue;
                }
                QLMBandShape shape = band.type == QLMSetupBandPeak ? QLMBandShapePeak
                                   : band.type == QLMSetupBandLowShelf ? QLMBandShapeLowShelf
                                                                       : QLMBandShapeHighShelf;
                XCTAssertEqual(reading.shape, shape, @"%@ slot %ld", node.serial, (long)slot);
                XCTAssertEqualWithAccuracy(reading.frequency, band.frequency, band.frequency * fmax(2e-3, 2 * reading.spread));
                XCTAssertEqualWithAccuracy(reading.gainDecibels, band.gain, 0.02);
                if (band.type == QLMSetupBandPeak) {
                    XCTAssertEqualWithAccuracy(reading.q, band.q, band.q * fmax(1e-2, 2 * reading.spread));
                }
                read += 1;
            }
        }
    }
    XCTAssertGreaterThan(read, 0u);
}

#pragma mark - Replies

// startup-idle at 7.294 s: no mic, the knob in at -1004 tenths
// (docs/protocol.md, The adapter's status). The same with the mic:
// startup-idle-mic, DE and DD as raw counts of unconfirmed meaning.
- (void)testTheAdaptersStatus {
    QLMMessage poll = QLMCommandPoll(QLMAddressAdapter);
    QLMMessage status = QLMMakeMessage(0x01, 0x09, 0x33, 0x30, 0x36, 0xDF, 0xFF, 0xFF, 0xFC, 0x14);
    XCTAssertEqualObjects(QLMReplyText(status, &poll), @"status: knob at −100.4 dB, no mic");
    XCTAssertEqualObjects(QLMReplyText(status, NULL), @"status: knob at −100.4 dB, no mic", @"its shape answers 01 08 alone");
    QLMMessage mic = QLMMakeMessage(0x01, 0x09, 0x32, 0x34, 0xDE, 0x1B, 0xAB, 0xFB, 0xA0, 0xDD, 0x00, 0x22, 0x4E, 0x4F, 0x31);
    XCTAssertEqualObjects(QLMReplyText(mic, &poll), @"status: no knob, mic in, DE 464255904, DD 2248271, raw counts");
}

// The no-answer frame, startup-idle at 20.146 s. The probe's hardware ID,
// startup-idle at 8.424 s. The lease's ack, hlm §8. A plain ack, hlm §8.
- (void)testTheAcks {
    QLMMessage probe = QLMCommandProbe();
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x7E), &probe), @"no answer");
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x12, 0x34, 0x56), &probe), @"hardware ID 12 34 56");
    const uint8_t hardwareID[3] = {0x12, 0x34, 0x56};
    QLMMessage lease = QLMCommandAssignSession(hardwareID, 0x0B);
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x0B), &lease), @"lease taken, session 0B");
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x0C), &lease), @"lease taken, session 0C, not the 0B asked");
    QLMMessage mute = QLMCommandMute(0x0B, QLMMuteValueMuted);
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09), &mute), @"ack");
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x06), &mute), @"ack, busy 06");
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x06), NULL), @"a reply with no request to read it by",
                          @"09 06 is a busy marker or a lease's ack: only the request tells");
}

// System info, startup-idle at 7.300 s.
- (void)testTheTextReplies {
    QLMMessage info = QLMCommandSystemInfo(QLMAddressAdapter);
    const char text[] = "\x09" "c-0;model-GLM Adapter;ver-1.4.0.6113;hw-0.0.202";
    QLMMessage reply = QLMMessageMake(0x01, (const uint8_t *)text, sizeof text);
    XCTAssertEqualObjects(QLMReplyText(reply, &info), @"system info: GLM Adapter, firmware 1.4.0.6113");
    QLMMessage serial = QLMCommandSerialNumber(0x0B);
    const char number[] = "\x09" "8330AP21039626";
    XCTAssertEqualObjects(QLMReplyText(QLMMessageMake(0x01, (const uint8_t *)number, sizeof number - 1), &serial),
                          @"serial 8330AP21039626");
}

// The two parts of a split frame: sleep-wake-darkwake, the Left 8351B at
// 313.283 and 313.878 s (docs/telemetry.md, Split frames). The count of
// seconds, 8A by 256 plus 49: docs/telemetry.md.
- (void)testTelemetry {
    QLMMessage poll = QLMCommandPoll(0x15);
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x41, 0x2A), &poll),
                          @"first part of a split frame: no power state, 42 °C");
    QLMMessage second = QLMMakeMessage(0x01, 0x09, 0x81, 0x00, 0x2A, 0x82, 0x00, 0x2A, 0x83, 0x00, 0x2A, 0x42, 0x9F, 0x43, 0x80,
                                       0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x49, 0x73, 0x88, 0x00, 0x4B, 0x89, 0x00, 0x41, 0x84, 0x02, 0xF1);
    XCTAssertEqualObjects(QLMReplyText(second, &poll), @"no 41: the second part of a split frame");
    QLMMessage whole = QLMMakeMessage(0x01, 0x09, 0x41, 0x2A, 0x81, 0x00, 0x2A, 0x82, 0x00, 0x2A, 0x83, 0x00, 0x2A, 0x42, 0x9F, 0x43,
                                      0x80, 0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x49, 0x73, 0x88, 0x00, 0x4B, 0x89, 0x00, 0x41, 0x84,
                                      0x02, 0xF1, 0x8A, 0x00, 0x01);
    XCTAssertEqualObjects(QLMReplyText(whole, &poll),
                          @"telemetry: on, 42 °C, two- or three-way; meters in 159, HF 128, mid 128, LF 128; woke 371 s ago");
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09), &poll), @"no new telemetry");
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, 0x07), &poll), @"busy, no new telemetry");
}

#pragma mark - Every capture

// Every frame in every capture reads in a form docs/protocol.md gives, and
// every reply reads against the request before it. The one exception is
// three 08s with more bytes, 08 7D, 08 7D 5D, and 08 7D 5D 5D, in GLM's
// block to a session no monitor held, setup-b-peq-8351b at 183.635,
// 183.825, and 183.835 s. They read as unknown.
- (void)testEveryCapturedFrameReads {
    NSUInteger frames = 0;
    NSMutableArray<NSString *> *unknown = [NSMutableArray array];
    for (NSString *scenario in QLMCaptureScenarios()) {
        QLMCapture *capture = QLMReadCapture(scenario, NULL);
        for (QLMCaptureExchange *exchange in capture.exchanges) {
            QLMMessage request = exchange.message;
            NSString *text = QLMPlainRequestText(request);
            if ([text hasSuffix:@"bytes, unknown"]) {
                [unknown addObject:[NSString stringWithFormat:@"%@ %.3f %@", scenario, exchange.time, QLMAdapterRecord(&request)]];
            }
            if (exchange.replyFrame == nil) {
                continue;
            }
            QLMMessage reply = exchange.answered ? exchange.reply : QLMMakeMessage(0x01, 0x7E);
            NSString *words = QLMReplyText(reply, &request);
            for (NSString *bad in @[@"unexpected", @"no reply's shape", @"does not read", @"no status's shape", @"cut off"]) {
                XCTAssertFalse([words containsString:bad], @"%@ at %.3f: %@ to %@", scenario, exchange.time, words, text);
            }
            frames += 1;
        }
    }
    XCTAssertGreaterThan(frames, 50000u);
    XCTAssertEqualObjects(unknown, (@[
        @"setup-b-peq-8351b 183.635 {length = 3, bytes = 0x10087d}",
        @"setup-b-peq-8351b 183.825 {length = 4, bytes = 0x10087d5d}",
        @"setup-b-peq-8351b 183.835 {length = 5, bytes = 0x10087d5d5d}",
    ]));
}

// startup-idle at 7.295 and 7.962 s: 01 22's identity and 01 51 82's text.
- (void)testTheRefusedQueriesRepliesRead {
    QLMMessage identity = QLMMakeMessage(0x01, 0x22);
    const char text[] = "\x09" "GLM Adapter ";
    XCTAssertEqualObjects(QLMReplyText(QLMMessageMake(0x01, (const uint8_t *)text, sizeof text), &identity),
                          @"the adapter's identity: GLM Adapter ");
    QLMMessage query = QLMMakeMessage(0x01, 0x51, 0x82);
    XCTAssertEqualObjects(QLMReplyText(QLMMakeMessage(0x01, 0x09, '2', '1', '9', '0', '0', '0'), &query),
                          @"51 82's reply, meaning unknown: 219000");
}

@end
