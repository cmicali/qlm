#import <XCTest/XCTest.h>

#include "QLMBiquad.h"
#import "QLMDSPBlock.h"
#include "QLMFrame.h"
#import "QLMSetupInternal.h"
#import "QLMTestSupport.h"

// Sources: the hlm protocol spec, revision 13, section 9 for the block's
// order, section 5 for the slots, section 6 for the level and delay words,
// and section 7 for the crossover and routing frames. The nodes come from
// Fixtures/Main.sam.
@interface QLMDSPBlockTests : XCTestCase
@end

@implementation QLMDSPBlockTests

- (void)testTwoWayBlockInGLMsOrder {
    QLMSetup *setup = QLMReadFixtureSetup();
    QLMSetupGroup *group = setup.groups[0];
    QLMSetupNode *node = group.nodes[0];
    NSError *error = nil;
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:&error];
    XCTAssertNotNil(block, @"%@", error);
    XCTAssertEqual(block.designRate, 48000);
    XCTAssertTrue(block.rateVerified);
    XCTAssertEqual(block.payloads.count, 27u);

    // Section 9: 17 01, 10 02, 10 01 00, 10 01 09, PEQ x20, 3B, 3D, 40.
    const uint8_t prepare[] = {0x17, 0x01};
    XCTAssertEqualObjects(block.payloads[0], QLMBytes(prepare, sizeof prepare));
    // 6 ms of time of flight at 48 kHz is 288 samples.
    const uint8_t delay[] = {0x10, 0x02, 0x00, 0x00, 0x01, 0x20};
    XCTAssertEqualObjects(block.payloads[1], QLMBytes(delay, sizeof delay));
    // -0.2 dB at 2^23 - 1, rounded.
    uint32_t level = (uint32_t)round(pow(10, -0.2 / 20) * 8388607);
    const uint8_t levelFrame[] = {0x10, 0x01, 0x00, (uint8_t)(level >> 16), (uint8_t)(level >> 8), (uint8_t)level};
    XCTAssertEqualObjects(block.payloads[2], QLMBytes(levelFrame, sizeof levelFrame));
    const uint8_t unknownLevel[] = {0x10, 0x01, 0x09, 0x00, 0x00, 0x00};
    XCTAssertEqualObjects(block.payloads[3], QLMBytes(unknownLevel, sizeof unknownLevel));
    for (NSUInteger slot = 0; slot < 20; slot++) {
        NSData *payload = block.payloads[4 + slot];
        const uint8_t *bytes = payload.bytes;
        XCTAssertEqual(payload.length, 24u);
        XCTAssertEqual(bytes[0], 0x10);
        XCTAssertEqual(bytes[1], 0x0E);
        XCTAssertEqual(bytes[2], slot);
        XCTAssertEqual(bytes[23], 0x00);
    }
    const uint8_t crossover[] = {0x3B, 0x00, 0x55};  // 85 Hz
    XCTAssertEqualObjects(block.payloads[24], QLMBytes(crossover, sizeof crossover));
    const uint8_t sync[] = {0x3D, 0x00, 0x00};
    XCTAssertEqualObjects(block.payloads[25], QLMBytes(sync, sizeof sync));
    const uint8_t routing[] = {0x40, 0x00, 0x02, 0x00, 0x02};  // input 2: AES3 B
    XCTAssertEqualObjects(block.payloads[26 + 0], QLMBytes(routing, sizeof routing));

    // Section 5's slots: low shelf 1 in slot 0, bypassed at 0 dB; high
    // shelf 2 in slot 3; peak 1 in slot 4, designed at 48 kHz.
    const uint8_t *slot0 = block.payloads[4].bytes;
    uint8_t bypass[QLMBiquadPackedSize];
    QLMBiquad bypassBiquad = QLMBiquadBypass();
    QLMBiquadPack(&bypassBiquad, bypass);
    XCTAssertEqual(memcmp(slot0 + 3, bypass, sizeof bypass), 0);
    const uint8_t *slot3 = block.payloads[4 + 3].bytes;
    uint8_t highShelf[QLMBiquadPackedSize];
    QLMBiquad highShelfBiquad = QLMBiquadHighShelf(500.67, -0.27, QLMBiquadHighShelfQ, 48000);
    QLMBiquadPack(&highShelfBiquad, highShelf);
    XCTAssertEqual(memcmp(slot3 + 3, highShelf, sizeof highShelf), 0);
    const uint8_t *slot4 = block.payloads[4 + 4].bytes;
    uint8_t peak[QLMBiquadPackedSize];
    QLMBiquad peakBiquad = QLMBiquadPeak(250.31, 3, 0.7, 48000);
    QLMBiquadPack(&peakBiquad, peak);
    XCTAssertEqual(memcmp(slot4 + 3, peak, sizeof peak), 0);

    for (NSData *payload in block.payloads) {
        XCTAssertTrue(QLMFrameAllows(payload.bytes, payload.length));
    }
}

- (void)testSubwooferBlock {
    QLMSetup *setup = QLMReadFixtureSetup();
    QLMSetupGroup *group = setup.groups[0];
    QLMSetupNode *node = group.nodes[3];
    XCTAssertEqual(node.nodeClass, QLMSetupNodeClassSubwoofer);
    NSError *error = nil;
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:&error];
    XCTAssertNotNil(block, @"%@", error);
    XCTAssertEqual(block.designRate, 12000);
    XCTAssertTrue(block.rateVerified);
    // Section 6: phase 150 degrees at an 85 Hz crossover is 235 samples.
    const uint8_t delay[] = {0x10, 0x02, 0x00, 0x00, 0x00, 0xEB};
    XCTAssertEqualObjects(block.payloads[1], QLMBytes(delay, sizeof delay));
    // Twenty peaks, slot 0 holding peak 1.
    uint8_t peak[QLMBiquadPackedSize];
    QLMBiquad peakBiquad = QLMBiquadPeak(node.bands[0].frequency, node.bands[0].gain, node.bands[0].q, 12000);
    QLMBiquadPack(&peakBiquad, peak);
    XCTAssertEqual(memcmp((const uint8_t *)block.payloads[4].bytes + 3, peak, sizeof peak), 0);
    const uint8_t routing[] = {0x40, 0x00, 0x02, 0x00, 0x03};  // input 3: AES3 A+B
    XCTAssertEqualObjects(block.payloads[26], QLMBytes(routing, sizeof routing));
    XCTAssertEqual(block.warnings.count, 0u);
}

// The block for the node with `serial` in `group`.
static QLMDSPBlock *QLMBlockForSerial(QLMSetupGroup *group, NSString *serial) {
    return [QLMDSPBlock blockForNode:[group nodeWithSerial:serial] inGroup:group error:NULL];
}

// Source: captures/group-switch-main-2x1-main-4x2, the switch to Main 4x2.
// Each monitor is known by its level frame. Time-of-flight_Compensation is
// in milliseconds: the 8330As' 6 is 288 samples, and the 8351B's 1.23 is 59.
// The subwoofers' delays are their phase at 85 Hz.
- (void)testDelaysMatchTheCapturedSwitchToMain4x2 {
    QLMSetupGroup *group = QLMReadFixtureSetup().groups[0];
    QLMDSPBlock *rearRight = QLMBlockForSerial(group, @"1000005");
    const uint8_t rearRightDelay[] = {0x10, 0x02, 0x00, 0x00, 0x01, 0x20};  // 36.125 s, to 02
    XCTAssertEqualObjects(rearRight.payloads[1], QLMBytes(rearRightDelay, sizeof rearRightDelay));
    XCTAssertEqual(rearRight.warnings.count, 0u);
    const uint8_t left[] = {0x10, 0x02, 0x00, 0x00, 0x00, 0x3B};  // 35.615 s, to 03
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000002").payloads[1], QLMBytes(left, sizeof left));
    const uint8_t rearLeft[] = {0x10, 0x02, 0x00, 0x00, 0x01, 0x20};  // 35.805 s, to 04
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000004").payloads[1], QLMBytes(rearLeft, sizeof rearLeft));
    const uint8_t sub[] = {0x10, 0x02, 0x00, 0x00, 0x00, 0xEB};  // 36.441 s, to 05
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000006").payloads[1], QLMBytes(sub, sizeof sub));
    const uint8_t right[] = {0x10, 0x02, 0x00, 0x00, 0x00, 0x00};  // 35.704 s, to 06
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000003").payloads[1], QLMBytes(right, sizeof right));
    const uint8_t center[] = {0x10, 0x02, 0x00, 0x00, 0x00, 0xA5};  // 36.672 s, to 07
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000007").payloads[1], QLMBytes(center, sizeof center));
}

// Source: captures/startup-idle, at 8.857 s. GLM opened on Main 2x1 and sent
// its 7370A 10 02 00 00 01 90: 180 degrees at a 60 Hz crossover, 400 samples.
- (void)testSubwooferDelayMatchesTheCapturedStartup {
    QLMSetupGroup *group = QLMReadFixtureSetup().groups[2];
    const uint8_t sub[] = {0x10, 0x02, 0x00, 0x00, 0x01, 0x90};
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000006").payloads[1], QLMBytes(sub, sizeof sub));
}

// Source: captures/group-switch-main-2x1-main-4x2, the 40 frames of the
// switch to Main 4x2. Inputs 1 to 3 are AES3, with the channel last.
- (void)testAESRoutingMatchesTheCapturedSwitchToMain4x2 {
    QLMSetupGroup *group = QLMReadFixtureSetup().groups[0];
    const uint8_t inputTwo[] = {0x40, 0x00, 0x02, 0x00, 0x02};  // 36.423 s, to 02
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000005").payloads.lastObject, QLMBytes(inputTwo, sizeof inputTwo));
    const uint8_t inputOne[] = {0x40, 0x00, 0x02, 0x00, 0x01};  // 35.699 s, to 03
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000002").payloads.lastObject, QLMBytes(inputOne, sizeof inputOne));
    const uint8_t inputThree[] = {0x40, 0x00, 0x02, 0x00, 0x03};  // 36.515 s, to 05
    XCTAssertEqualObjects(QLMBlockForSerial(group, @"1000006").payloads.lastObject, QLMBytes(inputThree, sizeof inputThree));
}

// No capture has a node on input 4, so the analog frame stays unverified.
- (void)testAnalogRoutingIsMarkedUnverified {
    QLMSetupGroup *group = QLMReadFixtureSetup().groups[0];
    QLMSetupNode *node = [[QLMSetupNode alloc] init];
    node.nodeClass = QLMSetupNodeClassTwoWay;
    node.input = 4;
    node.bands = [group nodeWithSerial:@"1000005"].bands;
    NSError *error = nil;
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:&error];
    XCTAssertNotNil(block, @"%@", error);
    const uint8_t analog[] = {0x40, 0x00, 0x01, 0x02, 0x00};
    XCTAssertEqualObjects(block.payloads.lastObject, QLMBytes(analog, sizeof analog));
    XCTAssertTrue([block.warnings.lastObject containsString:@"analog"]);
}

// The Safety rule: an 8351B's rate is unverified, so its block says so.
- (void)testThreeWayIsUnverified {
    QLMSetup *setup = QLMReadFixtureSetup();
    QLMSetupGroup *group = setup.groups[0];
    NSError *error = nil;
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:group.nodes[1] inGroup:group error:&error];
    XCTAssertNotNil(block, @"%@", error);
    XCTAssertEqual(block.designRate, 96000);
    XCTAssertFalse(block.rateVerified);
    XCTAssertTrue([block.warnings.firstObject containsString:@"96000"]);
}

- (void)testBlocksForGroupSkipNodesThatAreOff {
    QLMSetup *setup = QLMReadFixtureSetup();
    NSError *error = nil;
    NSArray<QLMDSPBlock *> *all = [QLMDSPBlock blocksForGroup:setup.groups[0] error:&error];
    XCTAssertEqual(all.count, 6u, @"%@", error);
    NSArray<QLMDSPBlock *> *twoByTwo = [QLMDSPBlock blocksForGroup:setup.groups[1] error:&error];
    XCTAssertEqual(twoByTwo.count, 4u, @"%@", error);
    for (QLMDSPBlock *block in twoByTwo) {
        XCTAssertTrue(block.node.on);
    }
}

- (void)testRefusals {
    QLMSetup *setup = QLMReadFixtureSetup();
    QLMSetupGroup *group = setup.groups[0];
    NSError *error = nil;

    QLMSetupNode *unknownClass = [[QLMSetupNode alloc] init];
    unknownClass.className = @"FourwayGen3";
    XCTAssertNil([QLMDSPBlock blockForNode:unknownClass inGroup:group error:&error]);
    XCTAssertEqual(error.code, QLMDSPBlockErrorClass);

    QLMSetupNode *fewBands = [[QLMSetupNode alloc] init];
    fewBands.nodeClass = QLMSetupNodeClassTwoWay;
    fewBands.bands = [group.nodes[0].bands subarrayWithRange:NSMakeRange(0, 19)];
    XCTAssertNil([QLMDSPBlock blockForNode:fewBands inGroup:group error:&error]);
    XCTAssertEqual(error.code, QLMDSPBlockErrorBands);

    QLMSetupNode *shelfOnASub = [[QLMSetupNode alloc] init];
    shelfOnASub.nodeClass = QLMSetupNodeClassSubwoofer;
    shelfOnASub.bands = group.nodes[0].bands;
    XCTAssertNil([QLMDSPBlock blockForNode:shelfOnASub inGroup:group error:&error]);
    XCTAssertEqual(error.code, QLMDSPBlockErrorBands);

    QLMSetupNode *unstable = [[QLMSetupNode alloc] init];
    unstable.nodeClass = QLMSetupNodeClassTwoWay;
    unstable.input = 1;
    NSMutableArray<QLMSetupBand *> *bands = [group.nodes[0].bands mutableCopy];
    QLMSetupBand *bad = [[QLMSetupBand alloc] init];
    bad.type = QLMSetupBandPeak;
    bad.index = 1;
    bad.frequency = 1000;
    bad.gain = 6;
    bad.q = -1;
    bad.sampleRate = 48000;
    bands[4] = bad;
    unstable.bands = bands;
    XCTAssertNil([QLMDSPBlock blockForNode:unstable inGroup:group error:&error]);
    XCTAssertEqual(error.code, QLMDSPBlockErrorUnstable);

    QLMSetupNode *badInput = [[QLMSetupNode alloc] init];
    badInput.nodeClass = QLMSetupNodeClassTwoWay;
    badInput.input = 9;
    badInput.bands = group.nodes[0].bands;
    XCTAssertNil([QLMDSPBlock blockForNode:badInput inGroup:group error:&error]);
    XCTAssertEqual(error.code, QLMDSPBlockErrorInput);
}

@end
