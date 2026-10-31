#import "QLMTestSupport.h"

#include <math.h>

#include "QLMBiquad.h"
#import "QLMDSPBlock.h"
#include "QLMCommands.h"
#import "QLMSetupInternal.h"
#import "QLMSetupReader.h"

#import "QLMCompareApply.h"

// Sources: the DSP passes GLM sent in the captures below, each scenario's
// notes.md, and each row's setup file. In Fixtures/Main.sam a monitor is
// named by its node's serial: 1000002 and 1000003 the Left and Right 8351B,
// 1000004 and 1000005 the Rear Left and Rear Right 8330A, 1000006 the 7370A,
// and 1000007 the 7350A. Payloads are compared byte for byte; the session is
// the address. QLMPassesInCapture and QLMBlockComparison are qlmctl
// compare-apply's, so the verb checks what these tests check.
@interface QLMDSPBlockGoldenTests : XCTestCase
@end

// A captured pass, with the row's capture, setup, group, and node.
@interface QLMGoldenPass : NSObject
@property (nonatomic) QLMCapturedPass *captured;
@property (nonatomic, copy) NSString *capture;
@property (nonatomic) QLMSetup *setup;
@property (nonatomic) QLMSetupGroup *group;
@property (nonatomic) QLMSetupNode *node;
@property (nonatomic) size_t row;
@end

@implementation QLMGoldenPass

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ at %.3f s", self.capture, self.captured.time];
}

@end

static BOOL QLMIsLevel(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    return payload.length == 6 && bytes[0] == 0x10 && bytes[1] == 0x01 && bytes[2] == 0x00;
}

static uint32_t QLMLevelWordOf(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    return (uint32_t)bytes[3] << 16 | (uint32_t)bytes[4] << 8 | bytes[5];
}

static NSData *QLMHex(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    for (NSString *pair in [hex componentsSeparatedByString:@" "]) {
        uint8_t byte = (uint8_t)strtoul(pair.UTF8String, NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

// Each GLM apply a test checks: a capture, the setup file GLM applied, from
// the repository's root, the group, and a window of the capture's seconds.
// Its passes are every DSP pass in the window, in order, as session and node
// serial. A monitor that wakes into the group is leased again and gets a
// second pass at its new session, and GLM may cut the first one short. At
// startup GLM sends every node its block, off ones included. A capture of
// setups/N.sam snapshots takes one row per apply, against the snapshot
// GLM applied, its window from that apply to the next's.
static const struct {
    const char *capture;
    const char *setup;
    const char *group;
    double from;
    double to;
    const char *passes;
} QLMGoldenApplies[] = {
    {"group-switch-main-2x1-main-2x2", "Tests/Setups/Fixtures/Main.sam", "Main 2x2", 0, INFINITY,
     "03:1000002 06:1000003 05:1000006 0A:1000007 0B:1000007 03:1000002 06:1000003 05:1000006 0B:1000007"},
    {"group-switch-main-2x1-main-4x2", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 0, INFINITY,
     "03:1000002 06:1000003 04:1000004 02:1000005 05:1000006 07:1000007 08:1000005 09:1000004 0A:1000007"},
    {"group-switch-main-2x2-main-2x1", "Tests/Setups/Fixtures/Main.sam", "Main 2x1", 0, INFINITY,
     "03:1000002 06:1000003 05:1000006"},
    {"group-switch-main-2x2-main-4x2", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 0, INFINITY,
     "03:1000002 06:1000003 09:1000004 08:1000005 05:1000006 0B:1000007 0C:1000005 0D:1000004"},
    {"group-switch-main-4x2-main-2x1", "Tests/Setups/Fixtures/Main.sam", "Main 2x1", 0, INFINITY,
     "03:1000002 06:1000003 05:1000006"},
    {"group-switch-main-4x2-main-2x2", "Tests/Setups/Fixtures/Main.sam", "Main 2x2", 0, INFINITY,
     "03:1000002 06:1000003 05:1000006 07:1000007"},
    {"setup-a-baseline", "captures/setup-a-baseline/setups/0.sam", "Main 2x1", 0, 45,
     "03:1000002 06:1000003 05:1000006"},
    {"setup-a-baseline", "captures/setup-a-baseline/setups/0.sam", "Main 4x2", 45, INFINITY,
     "03:1000002 06:1000003 05:1000006 07:1000007 08:1000005 09:1000004 0A:1000007"},
    {"setup-b-peq-8351b", "captures/setup-b-peq-8351b/setups/0.sam", "Main 4x2", 0, 170,
     "0B:1000005 0C:1000002 0D:1000004 0E:1000006 0F:1000003 10:1000007"},
    {"setup-b-peq-8351b", "captures/setup-b-peq-8351b/setups/1.sam", "Main 2x1", 170, 181,
     "0C:1000002 0F:1000003 0E:1000006"},
    {"setup-b-peq-8351b", "captures/setup-b-peq-8351b/setups/1.sam", "Main 4x2", 181, 290,
     "0C:1000002 0F:1000003 0D:1000004 0B:1000005 0E:1000006 10:1000007 11:1000005 12:1000004 13:1000007"},
    {"setup-b-peq-8351b", "captures/setup-b-peq-8351b/setups/2.sam", "Main 2x1", 290, 299,
     "0C:1000002 0F:1000003 0E:1000006"},
    {"setup-b-peq-8351b", "captures/setup-b-peq-8351b/setups/2.sam", "Main 4x2", 299, INFINITY,
     "0C:1000002 0F:1000003 12:1000004 11:1000005 0E:1000006 13:1000007 14:1000005 15:1000004 16:1000007"},
    {"setup-j-restore", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 0, 34.2,
     "0C:1000002 0E:1000006 0F:1000003 14:1000005 15:1000004 16:1000007"},
    {"setup-j-restore", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 34.2, 40,
     "0C:1000002 0F:1000003 15:1000004 14:1000005 0E:1000006 16:1000007"},
    {"setup-j-restore", "Tests/Setups/Fixtures/Main.sam", "Main 2x1", 40, INFINITY,
     "0C:1000002 0F:1000003 0E:1000006"},
    {"knob-sweep", "Tests/Setups/Fixtures/Main.sam", "Main 2x1", 0, INFINITY,
     "02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"},
    {"standby-wake", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 0, INFINITY,
     "11:1000003 12:1000005 13:1000002 14:1000004 15:1000006 16:1000003 17:1000007"},
    {"startup-idle", "Tests/Setups/Fixtures/Main.sam", "Main 2x1", 0, INFINITY,
     "02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"},
    {"startup-idle-mic", "Tests/Setups/Fixtures/Main.sam", "Main 2x1", 0, INFINITY,
     "02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"},
    {"unplug", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 0, INFINITY,
     "14:1000005 15:1000002 16:1000004 17:1000006 18:1000003 19:1000007"},
    {"unplug-proxy-hang", "Tests/Setups/Fixtures/Main.sam", "Main 4x2", 0, INFINITY,
     "08:1000005 09:1000002 0A:1000004 0B:1000006 0C:1000003 0D:1000007"},
};

// A setup file from the repository's root, read once and shared, so each
// row's passes share its nodes.
static QLMSetup *QLMReadGoldenSetup(NSString *path) {
    static NSMutableDictionary<NSString *, QLMSetup *> *setups;
    if (setups == nil) {
        setups = [NSMutableDictionary dictionary];
    }
    if (setups[path] == nil) {
        setups[path] = [QLMSetupReader readFileAtPath:QLMRepositoryPath(path) error:NULL];
    }
    return setups[path];
}

@implementation QLMDSPBlockGoldenTests

// Every pass in the table, with its capture, setup, group, and node.
// Asserts that each window holds the row's passes at its sessions.
- (NSArray<QLMGoldenPass *> *)passes {
    NSMutableArray<QLMGoldenPass *> *passes = [NSMutableArray array];
    for (size_t r = 0; r < sizeof QLMGoldenApplies / sizeof QLMGoldenApplies[0]; r++) {
        NSString *scenario = @(QLMGoldenApplies[r].capture);
        QLMSetup *setup = QLMReadGoldenSetup(@(QLMGoldenApplies[r].setup));
        XCTAssertNotNil(setup, @"%s", QLMGoldenApplies[r].setup);
        QLMSetupGroup *group = [setup groupNamed:@(QLMGoldenApplies[r].group)];
        XCTAssertNotNil(group, @"%@: %s", scenario, QLMGoldenApplies[r].group);
        NSArray<NSString *> *expected = [@(QLMGoldenApplies[r].passes) componentsSeparatedByString:@" "];
        NSArray<QLMCapturedPass *> *captured =
            QLMPassesInCapture(QLMReadCapture(scenario, NULL), QLMGoldenApplies[r].from, QLMGoldenApplies[r].to);
        XCTAssertEqual(captured.count, expected.count, @"%@", scenario);
        for (NSUInteger i = 0; i < MIN(captured.count, expected.count); i++) {
            NSArray<NSString *> *parts = [expected[i] componentsSeparatedByString:@":"];
            QLMGoldenPass *pass = [[QLMGoldenPass alloc] init];
            pass.captured = captured[i];
            XCTAssertEqual(pass.captured.session, (uint8_t)strtoul(parts[0].UTF8String, NULL, 16), @"%@ pass %lu", scenario, (unsigned long)i);
            pass.capture = scenario;
            pass.setup = setup;
            pass.group = group;
            pass.node = [group nodeWithSerial:parts[1]];
            pass.row = r;
            XCTAssertNotNil(pass.node, @"%@ pass %lu", scenario, (unsigned long)i);
            [passes addObject:pass];
        }
    }
    return passes;
}

// Every captured pass matches its node's block, setting for setting, and
// no other node's. A pass GLM cut short matches the block's start, and
// only the 7350A's two in setup-b-peq-8351b are. Where the capture holds
// the session's reply to 39, its model is the node's.
- (void)testEveryCapturedPassMatchesItsBlock {
    NSUInteger payloads = 0;
    NSUInteger identified = 0;
    NSMutableArray<NSString *> *cut = [NSMutableArray array];
    NSArray<QLMGoldenPass *> *passes = [self passes];
    for (QLMGoldenPass *pass in passes) {
        if (pass.captured.model != nil) {
            XCTAssertEqualObjects(pass.captured.model, [pass.setup deviceWithSerial:pass.node.serial].model, @"%@", pass);
            identified += 1;
        }
        if (pass.captured.cutShort) {
            [cut addObject:pass.description];
        }
        for (QLMSetupNode *node in pass.group.nodes) {
            NSError *error = nil;
            QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:pass.group error:&error];
            XCTAssertNotNil(block, @"%@", error);
            QLMBlockComparison *comparison = [QLMBlockComparison comparisonOfBlock:block withPass:pass.captured];
            if (node == pass.node) {
                XCTAssertEqual(comparison.differenceCount, 0u, @"%@, %@: %@ %@ %@", pass, node.serial, comparison.changed,
                               comparison.glmOnly, comparison.qlmOnly);
            } else {
                XCTAssertNotEqual(comparison.differenceCount, 0u, @"%@ also matches %@", pass, node.serial);
            }
        }
        payloads += pass.captured.payloads.count;
    }
    XCTAssertEqual(passes.count, 128u);
    XCTAssertEqual(payloads, 4277u);
    XCTAssertEqual(identified, 92u);
    XCTAssertEqualObjects(cut, (@[@"setup-b-peq-8351b at 183.450 s", @"setup-b-peq-8351b at 300.973 s"]));
}

// compare-apply's match. Given the row's group, it finds for each pass the
// table's node, and the two match. Where two sessions match one node, the
// later was leased in the capture: the monitor, leased again.
- (void)testTheMatchFindsEachPassesNode {
    NSArray<QLMGoldenPass *> *passes = [self passes];
    NSMutableDictionary<NSNumber *, NSMutableArray<QLMGoldenPass *> *> *byRow = [NSMutableDictionary dictionary];
    for (QLMGoldenPass *pass in passes) {
        byRow[@(pass.row)] = byRow[@(pass.row)] ?: [NSMutableArray array];
        [byRow[@(pass.row)] addObject:pass];
    }
    NSUInteger checked = 0;
    for (NSArray<QLMGoldenPass *> *row in byRow.allValues) {
        NSArray<QLMPassMatch *> *matches = QLMMatchPasses([row valueForKey:@"captured"], row[0].setup, row[0].group, NULL);
        for (NSUInteger i = 0; i < row.count; i++) {
            XCTAssertTrue(matches[i].matches, @"%@: %@", row[i], matches[i].earlierPass);
            XCTAssertEqual(matches[i].node, row[i].node, @"%@", row[i]);
            checked += 1;
        }
    }
    XCTAssertEqual(checked, passes.count);
}

// S7's rule. Every generator stop GLM sent in a row's window is the same 14
// bytes, 154 of them, as docs/refused-frames.md counts. Each pass has one or
// more since its session's last pass: at launch and wake right before
// 17 01, and in a switch in the routing pass. A switch also stops the
// monitors off in the new group, which then get no pass, and a monitor may
// get two before one pass, so the rule counts no exact number per pass.
- (void)testEveryGeneratorStopIsTheKnownOne {
    for (QLMGoldenPass *pass in [self passes]) {
        XCTAssertGreaterThan(pass.captured.generatorStops.count, 0u, @"%@", pass);
    }
    NSUInteger stops = 0;
    for (size_t r = 0; r < sizeof QLMGoldenApplies / sizeof QLMGoldenApplies[0]; r++) {
        QLMCapture *capture = QLMReadCapture(@(QLMGoldenApplies[r].capture), NULL);
        for (QLMCapturedStop *stop in QLMGeneratorStopsInCapture(capture, QLMGoldenApplies[r].from, QLMGoldenApplies[r].to)) {
            XCTAssertEqualObjects(stop.payload, QLMHex(@"05 04 00 00 00 FF FF EA 00 01 90 00 02 DA"), @"%s at %.3f s",
                                  QLMGoldenApplies[r].capture, stop.time);
            XCTAssertTrue(QLMIsKnownGeneratorStop(stop.payload));
            stops += 1;
        }
    }
    XCTAssertEqual(stops, 154u);
}

// A two-way's or an 8351B's pass is its block in order, frame for frame,
// with nothing left out. The 8351B's has 43 00 02 right after the level
// pair, and 4B 00 00 00 01 right after the crossover, in every pass.
- (void)testTwoWayAndThreeWayPassesAreTheBlockInOrder {
    NSUInteger checked = 0;
    NSUInteger threeWays = 0;
    for (QLMGoldenPass *pass in [self passes]) {
        if (pass.node.nodeClass == QLMSetupNodeClassSubwoofer) {
            continue;
        }
        NSArray<NSData *> *glm = pass.captured.payloads;
        if (pass.node.nodeClass == QLMSetupNodeClassThreeWay) {
            XCTAssertEqualObjects(glm[4], QLMHex(@"43 00 02"), @"%@", pass);
            XCTAssertEqualObjects(glm[26], QLMHex(@"4B 00 00 00 01"), @"%@", pass);
            threeWays += 1;
        }
        NSArray<NSData *> *mine = [QLMDSPBlock blockForNode:pass.node inGroup:pass.group error:NULL].payloads;
        XCTAssertEqual(glm.count, mine.count, @"%@", pass);
        for (NSUInteger j = 0; j < MIN(glm.count, mine.count); j++) {
            XCTAssertEqualObjects(glm[j], mine[j], @"%@, frame %lu", pass, (unsigned long)j);
        }
        checked += 1;
    }
    XCTAssertEqual(checked, 83u);
    XCTAssertEqual(threeWays, 47u);
}

// A subwoofer's pass is its block in order, frame for frame. One cut short
// is the block's start.
- (void)testSubwooferPassesAreTheBlockInOrder {
    NSUInteger checked = 0;
    for (QLMGoldenPass *pass in [self passes]) {
        if (pass.node.nodeClass != QLMSetupNodeClassSubwoofer) {
            continue;
        }
        NSArray<NSData *> *mine = [QLMDSPBlock blockForNode:pass.node inGroup:pass.group error:NULL].payloads;
        if (pass.captured.cutShort) {
            XCTAssertLessThan(pass.captured.payloads.count, mine.count, @"%@", pass);
            mine = [mine subarrayWithRange:NSMakeRange(0, MIN(pass.captured.payloads.count, mine.count))];
        }
        XCTAssertEqualObjects(pass.captured.payloads, mine, @"%@", pass);
        checked += 1;
    }
    XCTAssertEqual(checked, 45u);
}

// GLM floors the level word. Four captured levels tell floor from round,
// where rounding is one count high: the Left 8351B at -0.17 dB
// (group-switch-main-2x1-main-4x2, 35.618 s) and -5.3 dB
// (group-switch-main-4x2-main-2x2, 13.690 s), the Rear Right 8330A at
// -0.2 dB (group-switch-main-2x1-main-4x2, 36.137 s), and the Right 8351B
// at -2.97 dB (group-switch-main-4x2-main-2x1, 13.106 s).
- (void)testGLMFloorsTheLevelWord {
    NSMutableSet<NSNumber *> *levels = [NSMutableSet set];
    NSMutableSet<NSNumber *> *belowRound = [NSMutableSet set];
    for (QLMGoldenPass *pass in [self passes]) {
        double decibels = pass.node.levelSensitivity + pass.node.groupSensitivity;
        for (NSData *payload in pass.captured.payloads) {
            if (QLMIsLevel(payload)) {
                uint32_t word = QLMLevelWordOf(payload);
                XCTAssertEqual(word, QLMLevelWordForDecibels(decibels), @"%@", pass);
                [levels addObject:@(decibels)];
                if (word < round(pow(10, decibels / 20) * (double)QLMVolumeWordMax)) {
                    [belowRound addObject:@(decibels)];
                }
            }
        }
    }
    XCTAssertEqual(levels.count, 11u);
    XCTAssertEqualObjects(belowRound, ([NSSet setWithArray:@[@-0.17, @-5.3, @-0.2, @-2.97]]));
}

// A node of `node`'s class and input, with its bands at `sampleRate`.
static QLMSetupNode *QLMNodeAtRate(QLMSetupNode *node, double sampleRate) {
    QLMSetupNode *moved = [[QLMSetupNode alloc] init];
    moved.nodeClass = node.nodeClass;
    moved.input = node.input;
    moved.groupDelayCompensation = node.groupDelayCompensation;
    moved.bassExtensionCrossover = node.bassExtensionCrossover;
    NSMutableArray<QLMSetupBand *> *bands = [NSMutableArray array];
    for (QLMSetupBand *band in node.bands) {
        QLMSetupBand *copy = [[QLMSetupBand alloc] init];
        copy.type = band.type;
        copy.index = band.index;
        copy.frequency = band.frequency;
        copy.gain = band.gain;
        copy.q = band.q;
        copy.sampleRate = sampleRate;
        [bands addObject:copy];
    }
    moved.bands = bands;
    return moved;
}

// The 8351B's design rate. Every slot GLM sent either 8351B in any group
// matches qlm's 96 kHz design bit for bit, and no filter matches a 48 kHz
// design. qlm still refuses the group. Lifting that is the user's decision.
- (void)testThe8351BIsDesignedAt96kHz {
    QLMBiquad flat = QLMBiquadBypass();
    uint8_t bypass[QLMBiquadPackedSize];
    QLMBiquadPack(&flat, bypass);
    NSMutableSet<NSData *> *filters = [NSMutableSet set];
    for (QLMGoldenPass *pass in [self passes]) {
        if (pass.node.nodeClass != QLMSetupNodeClassThreeWay) {
            continue;
        }
        QLMDSPBlock *block = [QLMDSPBlock blockForNode:pass.node inGroup:pass.group error:NULL];
        XCTAssertEqual(block.designRate, 96000);
        XCTAssertFalse(block.rateVerified);
        NSArray<NSData *> *at48 = [QLMDSPBlock blockForNode:QLMNodeAtRate(pass.node, 48000) inGroup:pass.group error:NULL].payloads;
        XCTAssertEqual(at48.count, block.payloads.count);
        for (NSData *payload in pass.captured.payloads) {
            const uint8_t *bytes = payload.bytes;
            if (bytes[0] != 0x10 || bytes[1] != 0x0E) {
                continue;
            }
            // Slot 0 follows 43 00 02.
            XCTAssertEqualObjects(payload, block.payloads[5 + bytes[2]]);
            if (memcmp(bytes + 3, bypass, sizeof bypass) != 0) {
                XCTAssertNotEqualObjects(payload, at48[5 + bytes[2]]);
                [filters addObject:payload];
            }
        }
    }
    XCTAssertEqual(filters.count, 49u);
}

@end
