#import "QLMTestSupport.h"

#import "QLMCommands.h"

// Sources: the hlm protocol spec, revision 13. Section 4 gives the volume
// scale's calibration points, section 7 each command's bytes, and section 9
// the power and dim procedures. GLM's own levels, which settle the scale,
// are in QLMVolumeScaleTests.
@interface QLMCommandsTests : XCTestCase
@end

@implementation QLMCommandsTests

// Section 4's calibration points. GLM's levels in the captures agree.
- (void)testVolumeWordsMatchSection4 {
    XCTAssertEqual(QLMVolumeWordForDecibels(0), 0x7FFFFFu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-10), 0x287A26u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-20), 0x0CCCCCu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-30), 0x040C37u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-40), 0x0147AEu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-50), 0x00679Fu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-59.5), 0x0022B5u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-70), 0x000A5Cu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-80), 0x000346u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-120.4), 0x000008u);
}

- (void)testVolumeWordsClampToTheSlider {
    XCTAssertEqual(QLMVolumeWordForDecibels(6), 0x7FFFFFu);
    XCTAssertEqual(QLMVolumeWordForDecibels(INFINITY), 0x7FFFFFu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-99.5), 0x000058u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-100), 0x000008u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-200), 0x000008u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-INFINITY), 0x000008u);
    XCTAssertEqual(QLMVolumeWordForDecibels(NAN), 0x000008u);
}

// Between steps, the nearest step, as GLM does with the knob.
- (void)testVolumeWordsRoundToTheNearestStep {
    XCTAssertEqual(QLMVolumeWordForDecibels(-0.2), 0x7FFFFFu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-0.3), 0x78D6FBu);
    XCTAssertEqual(QLMVolumeWordForDecibels(-41.7), 0x0113B5u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-99.7), 0x000058u);
    XCTAssertEqual(QLMVolumeWordForDecibels(-99.8), 0x000008u);
}

- (void)testDecibelsForWordInverts {
    XCTAssertEqual(QLMVolumeDecibelsForWord(0x7FFFFF), 0);
    XCTAssertEqualWithAccuracy(QLMVolumeDecibelsForWord(0x0CCCCC), -20, 1e-4);
    XCTAssertEqualWithAccuracy(QLMVolumeDecibelsForWord(0x000008), -120.4, 0.02);
    XCTAssertEqual(QLMVolumeDecibelsForWord(0), -INFINITY);
}

// Section 7: `FE` on the broadcast address, `02` with the hardware ID and the
// new session on the multicast address, and `04` on the broadcast address.
- (void)testDiscoveryBuilders {
    QLMMessage probe = QLMCommandProbe();
    XCTAssertEqual(probe.address, QLMAddressBroadcast);
    QLMAssertBytes(probe.payload, probe.length, 0xFE);

    const uint8_t hardwareID[3] = {0xAA, 0xBB, 0xCC};
    QLMMessage assign = QLMCommandAssignSession(hardwareID, 0x02);
    XCTAssertEqual(assign.address, QLMAddressMulticast);
    QLMAssertBytes(assign.payload, assign.length, 0x02, 0xAA, 0xBB, 0xCC, 0x02);

    QLMMessage keepAlive = QLMCommandKeepAlive();
    XCTAssertEqual(keepAlive.address, QLMAddressBroadcast);
    QLMAssertBytes(keepAlive.payload, keepAlive.length, 0x04);
}

// Section 7: `08`, `19 01`, and `39` to one session.
- (void)testQueryBuilders {
    QLMMessage poll = QLMCommandPoll(0x03);
    XCTAssertEqual(poll.address, 0x03);
    QLMAssertBytes(poll.payload, poll.length, 0x08);

    QLMMessage serial = QLMCommandSerialNumber(0x03);
    XCTAssertEqual(serial.address, 0x03);
    QLMAssertBytes(serial.payload, serial.length, 0x19, 0x01);

    QLMMessage info = QLMCommandSystemInfo(0x03);
    XCTAssertEqual(info.address, 0x03);
    QLMAssertBytes(info.payload, info.length, 0x39);
}

// Section 7: GLM mutes with `2B 03` and unmutes with `2B 04`.
- (void)testMuteBuilder {
    QLMMessage mute = QLMCommandMute(0x02, QLMMuteValueMuted);
    XCTAssertEqual(mute.address, 0x02);
    QLMAssertBytes(mute.payload, mute.length, 0x2B, 0x03);
    QLMMessage unmute = QLMCommandMute(0x02, QLMMuteValueUnmuted);
    QLMAssertBytes(unmute.payload, unmute.length, 0x2B, 0x04);

    // mute-dim: mute all tells the adapter with `01 2B 01`, and unmute all
    // with `01 2B 00`.
    QLMMessage adapterMuted = QLMCommandMute(QLMAddressReply, QLMMuteValueAdapterMuted);
    XCTAssertEqual(adapterMuted.address, 0x01);
    QLMAssertBytes(adapterMuted.payload, adapterMuted.length, 0x2B, 0x01);
    QLMMessage adapterUnmuted = QLMCommandMute(QLMAddressReply, QLMMuteValueAdapterUnmuted);
    QLMAssertBytes(adapterUnmuted.payload, adapterUnmuted.length, 0x2B, 0x00);
}

// Section 7 and 9: `3A 03 02` then `3A 03 00` to sleep, `3A 03 7F` and
// `3A 03 01` to wake, all on the broadcast address from a host.
- (void)testPowerBuilder {
    QLMMessage prepare = QLMCommandPower(QLMPowerStepStandbyPrepare);
    XCTAssertEqual(prepare.address, QLMAddressBroadcast);
    QLMAssertBytes(prepare.payload, prepare.length, 0x3A, 0x03, 0x02);
    QLMMessage off = QLMCommandPower(QLMPowerStepPowerOff);
    QLMAssertBytes(off.payload, off.length, 0x3A, 0x03, 0x00);
    QLMMessage wakeFirst = QLMCommandPower(QLMPowerStepWakeFirst);
    QLMAssertBytes(wakeFirst.payload, wakeFirst.length, 0x3A, 0x03, 0x7F);
    QLMMessage wakeSecond = QLMCommandPower(QLMPowerStepWakeSecond);
    QLMAssertBytes(wakeSecond.payload, wakeSecond.length, 0x3A, 0x03, 0x01);

    // The group-switch captures: the same frames to one monitor.
    QLMMessage wakeOne = QLMCommandMonitorPower(0x08, QLMPowerStepWakeSecond);
    XCTAssertEqual(wakeOne.address, 0x08);
    QLMAssertBytes(wakeOne.payload, wakeOne.length, 0x3A, 0x03, 0x01);
    QLMMessage standbyOne = QLMCommandMonitorPower(0x08, QLMPowerStepStandbyPrepare);
    QLMAssertBytes(standbyOne.payload, standbyOne.length, 0x3A, 0x03, 0x02);
}

// Section 7: `1F` with the word big-endian on the broadcast address.
- (void)testVolumeBuilder {
    QLMMessage volume = QLMCommandVolume(-10, 0);
    XCTAssertEqual(volume.address, QLMAddressBroadcast);
    QLMAssertBytes(volume.payload, volume.length, 0x1F, 0x28, 0x7A, 0x26);
}

// The Safety rule in AGENTS.md: every volume frame is clamped to the user's
// ceiling. Every builder that makes one is covered here.
- (void)testEveryVolumeBuilderHonorsTheCeiling {
    QLMMessage word = QLMCommandVolumeWord(0x7FFFFF, 0x287A26);
    QLMAssertBytes(word.payload, word.length, 0x1F, 0x28, 0x7A, 0x26);
    QLMMessage ceilingAboveZero = QLMCommandVolumeWord(0xFFFFFF, 0xFFFFFF);
    QLMAssertBytes(ceilingAboveZero.payload, ceilingAboveZero.length, 0x1F, 0x7F, 0xFF, 0xFF);

    QLMMessage decibels = QLMCommandVolume(0, -20);
    QLMAssertBytes(decibels.payload, decibels.length, 0x1F, 0x0C, 0xCC, 0xCC);
    QLMMessage under = QLMCommandVolume(-30, -20);
    QLMAssertBytes(under.payload, under.length, 0x1F, 0x04, 0x0C, 0x37);

    // Dim goes 20 dB below what is playing: the ceiling, when the volume is
    // above it.
    QLMMessage dim = QLMCommandDim(0, -20);
    QLMAssertBytes(dim.payload, dim.length, 0x1F, 0x01, 0x47, 0xAE);
    QLMMessage dimUnder = QLMCommandDim(-10, 0);
    QLMAssertBytes(dimUnder.payload, dimUnder.length, 0x1F, 0x04, 0x0C, 0x37);
    QLMMessage dimBetweenSteps = QLMCommandDim(0, -20.2);
    QLMAssertBytes(dimBetweenSteps.payload, dimBetweenSteps.length, 0x1F, 0x01, 0x35, 0x59);
    QLMMessage dimAboveZero = QLMCommandDim(INFINITY, INFINITY);
    QLMAssertBytes(dimAboveZero.payload, dimAboveZero.length, 0x1F, 0x0C, 0xCC, 0xCC);
    QLMMessage dimNoCeiling = QLMCommandDim(0, NAN);
    QLMAssertBytes(dimNoCeiling.payload, dimNoCeiling.length, 0x1F, 0x00, 0x00, 0x08);

    QLMMessage duck = QLMCommandDuck();
    QLMAssertBytes(duck.payload, duck.length, 0x1F, 0x00, 0x00, 0x02);

    // A ceiling between steps falls to the step below, even when the volume
    // rounds up to the step above it.
    QLMMessage betweenSteps = QLMCommandVolume(0, -20.2);
    QLMAssertBytes(betweenSteps.payload, betweenSteps.length, 0x1F, 0x0C, 0x15, 0x7F);
    QLMMessage roundsUp = QLMCommandVolume(-20.2, -20.2);
    QLMAssertBytes(roundsUp.payload, roundsUp.length, 0x1F, 0x0C, 0x15, 0x7F);
    QLMMessage onStep = QLMCommandVolume(-20.2, -20);
    QLMAssertBytes(onStep.payload, onStep.length, 0x1F, 0x0C, 0xCC, 0xCC);
    QLMMessage noCeiling = QLMCommandVolume(0, NAN);
    QLMAssertBytes(noCeiling.payload, noCeiling.length, 0x1F, 0x00, 0x00, 0x08);
}

static uint32_t QLMVolumeWordOf(QLMMessage message) {
    return (uint32_t)message.payload[1] << 16 | (uint32_t)message.payload[2] << 8 | message.payload[3];
}

// The same rule across the whole scale, on and between the steps: no word
// passes the ceiling or 7F FF FF, and dim is 20 dB below the volume sent.
- (void)testNoVolumeFramePassesTheCeiling {
    const double ceilings[] = {INFINITY, 6, 0, -0.1, -0.25, -0.5, -2.5, -3, -10.2, -20, -20.2, -59.75, -99.5, -99.9, -100, -120, -INFINITY, NAN};
    NSMutableArray<NSNumber *> *volumes = [NSMutableArray arrayWithArray:@[@(INFINITY), @(-INFINITY), @(NAN)]];
    for (int hundredths = 1000; hundredths >= -13000; hundredths -= 5) {
        [volumes addObject:@(hundredths / 100.0)];
    }
    NSUInteger failures = 0;
    for (size_t c = 0; c < sizeof ceilings / sizeof ceilings[0]; c++) {
        double ceiling = ceilings[c];
        for (NSNumber *volume in volumes) {
            double decibels = volume.doubleValue;
            QLMMessage messages[] = {QLMCommandVolume(decibels, ceiling), QLMCommandDim(decibels, ceiling)};
            uint32_t sent = QLMVolumeWordOf(messages[0]);
            uint32_t dimmed = sent == QLMVolumeWordMin ? QLMVolumeWordMin
                                                       : QLMVolumeWordForDecibels(QLMVolumeDecibelsForWord(sent) - QLMDimDecibels);
            BOOL ok = QLMVolumeWordOf(messages[1]) == dimmed;
            for (size_t m = 0; m < 2; m++) {
                uint32_t word = QLMVolumeWordOf(messages[m]);
                ok = ok && messages[m].address == QLMAddressBroadcast && messages[m].length == 4;
                ok = ok && word <= QLMVolumeWordMax && word >= QLMVolumeWordMin;
                if (word != QLMVolumeWordMin && !isnan(ceiling)) {
                    ok = ok && QLMVolumeDecibelsForWord(word) <= ceiling + 1e-5;
                }
            }
            if (!ok && failures++ < 5) {
                XCTFail(@"%g dB under a ceiling of %g dB", decibels, ceiling);
            }
        }
    }
    XCTAssertEqual(failures, 0u);
    for (uint64_t word = 0; word <= UINT32_MAX; word += 0x00FFFFFF) {
        XCTAssertLessThanOrEqual(QLMVolumeWordOf(QLMCommandVolumeWord((uint32_t)word, UINT32_MAX)), (uint32_t)QLMVolumeWordMax);
    }
}

// Section 9: dim is the current volume 20 dB down, floored at 00 00 08.
- (void)testDimFloorsAtTheSlider {
    QLMMessage dim = QLMCommandDim(-110, 0);
    QLMAssertBytes(dim.payload, dim.length, 0x1F, 0x00, 0x00, 0x08);
}

// Section 6: a level word is linear gain at 2^23 - 1. GLM floors it, as
// QLMDSPBlockGoldenTests shows. The spec's observed words invert to their
// stated decibels within a hundredth.
- (void)testLevelWords {
    XCTAssertEqual(QLMLevelWordForDecibels(0), 0x7FFFFFu);
    XCTAssertEqual(QLMLevelWordForDecibels(3), 0x7FFFFFu);
    for (NSNumber *observed in @[@0x7A3957, @0x748C42, @0x00679F]) {
        // TRAP: invert the middle of the word's step. About one word in ten,
        // inverted itself, floors one count low.
        double decibels = 20 * log10((observed.doubleValue + 0.5) / (double)QLMVolumeWordMax);
        XCTAssertEqual(QLMLevelWordForDecibels(decibels), observed.unsignedIntValue);
    }
    XCTAssertEqualWithAccuracy(20 * log10(0x7A3957 / (double)QLMVolumeWordMax), -0.4, 0.01);
}

// Sections 6, 7, and 9: the DSP block's frames.
- (void)testDSPBlockBuilders {
    QLMMessage prepare = QLMCommandPrepare(0x02);
    XCTAssertEqual(prepare.address, 0x02);
    QLMAssertBytes(prepare.payload, prepare.length, 0x17, 0x01);
    QLMMessage delay = QLMCommandDelay(0x02, 356);
    QLMAssertBytes(delay.payload, delay.length, 0x10, 0x02, 0x00, 0x00, 0x01, 0x64);
    QLMMessage level = QLMCommandLevel(0x02, 0x7FFFFF);
    QLMAssertBytes(level.payload, level.length, 0x10, 0x01, 0x00, 0x7F, 0xFF, 0xFF);
    QLMMessage levelOver = QLMCommandLevel(0x02, 0xFFFFFF);
    QLMAssertBytes(levelOver.payload, levelOver.length, 0x10, 0x01, 0x00, 0x7F, 0xFF, 0xFF);
    QLMMessage unknown = QLMCommandLevelUnknown(0x02);
    QLMAssertBytes(unknown.payload, unknown.length, 0x10, 0x01, 0x09, 0x00, 0x00, 0x00);
    uint8_t coefficients[20] = {0x00, 0x00, 0x80, 0x3F};
    QLMMessage peq = QLMCommandPEQ(0x02, 0x13, coefficients);
    XCTAssertEqual(peq.length, 24u);
    XCTAssertEqual(peq.payload[0], 0x10);
    XCTAssertEqual(peq.payload[1], 0x0E);
    XCTAssertEqual(peq.payload[2], 0x13);
    XCTAssertEqual(memcmp(peq.payload + 3, coefficients, 20), 0);
    XCTAssertEqual(peq.payload[23], 0x00);
    QLMMessage crossover = QLMCommandCrossover(0x02, 90);
    QLMAssertBytes(crossover.payload, crossover.length, 0x3B, 0x00, 0x5A);
    QLMMessage sync = QLMCommandInputSync(0x02);
    QLMAssertBytes(sync.payload, sync.length, 0x3D, 0x00, 0x00);
    QLMMessage routing = QLMCommandRouting(0x02, 0x00, 0x02, 0x00, 0x01);
    QLMAssertBytes(routing.payload, routing.length, 0x40, 0x00, 0x02, 0x00, 0x01);
    QLMMessage subwoofer = QLMCommandSubwooferUnknown(0x05, 0x3E);
    XCTAssertEqual(subwoofer.address, 0x05);
    QLMAssertBytes(subwoofer.payload, subwoofer.length, 0x3E, 0x00, 0x00);

    QLMMessage messages[] = {prepare, delay, level, unknown, peq, crossover, sync, routing, subwoofer};
    for (size_t i = 0; i < sizeof messages / sizeof messages[0]; i++) {
        uint8_t out[QLMFrameMax];
        size_t length = 0;
        XCTAssertEqual(QLMFrameEncode(&messages[i], out, sizeof out, &length), QLMFrameOK, @"builder %zu", i);
    }
}

- (void)testEveryBuilderEncodes {
    const uint8_t hardwareID[3] = {1, 2, 3};
    QLMMessage messages[] = {
        QLMCommandProbe(), QLMCommandAssignSession(hardwareID, 0x02), QLMCommandKeepAlive(), QLMCommandPoll(0x02),
        QLMCommandSerialNumber(0x02), QLMCommandSystemInfo(0x02), QLMCommandMute(0x02, QLMMuteValueMuted),
        QLMCommandMute(QLMAddressReply, QLMMuteValueAdapterMuted), QLMCommandPower(QLMPowerStepWakeFirst),
        QLMCommandMonitorPower(0x02, QLMPowerStepWakeSecond), QLMCommandMonitorPower(0x02, QLMPowerStepStandbyPrepare),
        QLMCommandVolumeWord(0x7FFFFF, 0x7FFFFF), QLMCommandVolume(-6, 0), QLMCommandDim(-6, 0), QLMCommandDuck(),
        QLMCommandInputSync(QLMAddressBroadcast), QLMCommandInputPreamble(),
    };
    for (size_t i = 0; i < sizeof messages / sizeof messages[0]; i++) {
        uint8_t out[QLMFrameMax];
        size_t length = 0;
        XCTAssertEqual(QLMFrameEncode(&messages[i], out, sizeof out, &length), QLMFrameOK, @"builder %zu", i);
        QLMMessage decoded;
        XCTAssertEqual(QLMFrameDecode(out, length, &decoded), QLMFrameOK, @"builder %zu", i);
        XCTAssertEqual(decoded.address, messages[i].address);
        XCTAssertEqual(decoded.length, messages[i].length);
    }
}

@end
