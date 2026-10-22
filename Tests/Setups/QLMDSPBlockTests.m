#import <XCTest/XCTest.h>

#include "QLMBiquad.h"
#import "QLMDSPBlock.h"
#include "QLMFrame.h"
#import "QLMSetupInternal.h"
#import "QLMSetupReader.h"

// Sources: the hlm protocol spec, revision 13, section 9 for the block's
// order, section 5 for the slots, section 6 for the level and delay words,
// and section 7 for the crossover and routing frames. The nodes come from
// Fixtures/Main.sam.
@interface QLMDSPBlockTests : XCTestCase
@end

@implementation QLMDSPBlockTests

- (QLMSetup *)fixture {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"Main" ofType:@"sam"];
    if (path == nil) {
        path = [[@(__FILE__) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Fixtures/Main.sam"];
    }
    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readFileAtPath:path error:&error];
    XCTAssertNotNil(setup, @"%@", error);
    return setup;
}

static NSData *QLMBytes(const uint8_t *bytes, size_t length) {
    return [NSData dataWithBytes:bytes length:length];
}

- (void)testTwoWayBlockInGLMsOrder {
    QLMSetup *setup = [self fixture];
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
    QLMBiquad highShelfBiquad = QLMBiquadHighShelf(500.67, -0.27, 48000);
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
    QLMSetup *setup = [self fixture];
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

// The Safety rule: an 8351B's rate is unverified, so its block says so.
- (void)testThreeWayIsUnverified {
    QLMSetup *setup = [self fixture];
    QLMSetupGroup *group = setup.groups[0];
    NSError *error = nil;
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:group.nodes[1] inGroup:group error:&error];
    XCTAssertNotNil(block, @"%@", error);
    XCTAssertEqual(block.designRate, 96000);
    XCTAssertFalse(block.rateVerified);
    XCTAssertTrue([block.warnings.firstObject containsString:@"96000"]);
}

- (void)testBlocksForGroupSkipNodesThatAreOff {
    QLMSetup *setup = [self fixture];
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
    QLMSetup *setup = [self fixture];
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
