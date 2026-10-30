#import "QLMTestSupport.h"

#import "QLMDSPBlock.h"
#include "QLMCommands.h"
#include "QLMReplies.h"
#import "QLMSetupInternal.h"

// Sources: the DSP passes GLM sent in the captures below, each scenario's
// notes.md, and Fixtures/Main.sam. A monitor is named by its node's serial
// in the fixture: 1000002 and 1000003 the Left and Right 8351B, 1000004 and
// 1000005 the Rear Left and Rear Right 8330A, 1000006 the 7370A, and 1000007
// the 7350A. Payloads are compared byte for byte; the session is the address.
@interface QLMDSPBlockGoldenTests : XCTestCase
@end

// What GLM sent one session from its 17 01 through the 40 frames after its
// 3D. Only DSP opcodes are kept, so the polls between are dropped.
@interface QLMCapturedPass : NSObject
@property (nonatomic) uint8_t session;
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) NSMutableArray<NSData *> *payloads;
@property (nonatomic) BOOL synced;
@end

@implementation QLMCapturedPass
@end

static BOOL QLMIsDSPOpcode(uint8_t opcode) {
    switch (opcode) {
    case 0x10: case 0x17: case 0x3B: case 0x3C: case 0x3D: case 0x3E: case 0x40: case 0x42: case 0x43: case 0x4B:
        return YES;
    default:
        return NO;
    }
}

static NSArray<QLMCapturedPass *> *QLMPassesInCapture(QLMCapture *capture) {
    NSMutableArray<QLMCapturedPass *> *passes = [NSMutableArray array];
    QLMCapturedPass *open = nil;
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        QLMMessage message = exchange.message;
        const uint8_t *payload = message.payload;
        if (message.length >= 2 && payload[0] == 0x17 && payload[1] == 0x01) {
            open = [[QLMCapturedPass alloc] init];
            open.session = message.address;
            open.time = exchange.time;
            open.payloads = [NSMutableArray array];
            [passes addObject:open];
        }
        if (open == nil || message.address != open.session) {
            continue;
        }
        if (open.synced && payload[0] != 0x40) {
            open = nil;
            continue;
        }
        if (QLMIsDSPOpcode(payload[0])) {
            [open.payloads addObject:QLMBytes(payload, message.length)];
            open.synced = open.synced || payload[0] == 0x3D;
        }
    }
    return passes;
}

// The bytes that name a payload's setting: a PEQ slot, a level subcommand,
// a routing input, or the opcode alone.
static NSData *QLMSettingKey(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    NSUInteger length = 1;
    if (bytes[0] == 0x10) {
        length = bytes[1] == 0x02 ? 2 : 3;
    } else if (bytes[0] == 0x40) {
        length = 2;
    }
    return [payload subdataWithRange:NSMakeRange(0, MIN(length, payload.length))];
}

static BOOL QLMIsLevel(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    return payload.length == 6 && bytes[0] == 0x10 && bytes[1] == 0x01 && bytes[2] == 0x00;
}

static uint32_t QLMLevelWordOf(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    return (uint32_t)bytes[3] << 16 | (uint32_t)bytes[4] << 8 | bytes[5];
}

// GLM's level word: floor(10^(dB/20) * (2^23 - 1)), with 0 dB and up at
// 7F FF FF. Rounding misses four of the eleven captured levels.
static uint32_t QLMFlooredLevelWord(double decibels) {
    return decibels >= 0 ? 0x7FFFFF : (uint32_t)floor(pow(10, decibels / 20) * 8388607.0);
}

static NSData *QLMHex(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    for (NSString *pair in [hex componentsSeparatedByString:@" "]) {
        uint8_t byte = (uint8_t)strtoul(pair.UTF8String, NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

// The frames GLM sends that qlm's block leaves out. The allowlist refuses
// all but 40 01, the subwoofer's routing for input 1, whose meaning no
// capture shows.
static NSSet<NSData *> *QLMExtrasForClass(QLMSetupNodeClass nodeClass) {
    switch (nodeClass) {
    case QLMSetupNodeClassThreeWay:
        return [NSSet setWithArray:@[QLMHex(@"43 00 02"), QLMHex(@"4B 00 00 00 01")]];
    case QLMSetupNodeClassSubwoofer:
        return [NSSet setWithArray:@[QLMHex(@"40 01 02 00 00"), QLMHex(@"3E 00 00"), QLMHex(@"42 00 00"), QLMHex(@"3C 00 00")]];
    default:
        return [NSSet set];
    }
}

// How `pass` differs from `block`, or nil when the pass holds every setting
// of the block with the block's value, and the class's extras besides. The
// level may be one count above GLM's word.
static NSArray<NSString *> *_Nullable QLMDifferences(QLMDSPBlock *block, QLMCapturedPass *pass) {
    NSMutableDictionary<NSData *, NSData *> *expected = [NSMutableDictionary dictionary];
    for (NSData *payload in block.payloads) {
        expected[QLMSettingKey(payload)] = payload;
    }
    NSMutableArray<NSString *> *differences = [NSMutableArray array];
    NSMutableSet<NSData *> *seen = [NSMutableSet set];
    NSMutableSet<NSData *> *missingExtras = [QLMExtrasForClass(block.node.nodeClass) mutableCopy];
    for (NSData *payload in pass.payloads) {
        NSData *key = QLMSettingKey(payload);
        NSData *mine = expected[key];
        if (mine == nil) {
            if ([QLMExtrasForClass(block.node.nodeClass) containsObject:payload]) {
                [missingExtras removeObject:payload];
            } else {
                [differences addObject:[NSString stringWithFormat:@"GLM only: %@", payload]];
            }
            continue;
        }
        [seen addObject:key];
        BOOL same = [mine isEqualToData:payload];
        if (QLMIsLevel(payload)) {
            uint32_t qlm = QLMLevelWordOf(mine);
            uint32_t glm = QLMLevelWordOf(payload);
            same = qlm >= glm && qlm - glm <= 1;
        }
        if (!same) {
            [differences addObject:[NSString stringWithFormat:@"%@ in place of %@", payload, mine]];
        }
    }
    for (NSData *key in expected) {
        if (![seen containsObject:key]) {
            [differences addObject:[NSString stringWithFormat:@"qlm only: %@", expected[key]]];
        }
    }
    for (NSData *extra in missingExtras) {
        [differences addObject:[NSString stringWithFormat:@"no extra %@", extra]];
    }
    return differences.count == 0 ? nil : differences;
}

@implementation QLMDSPBlockGoldenTests

// Each capture's DSP passes in order, as session and node serial, and the
// group GLM applied. A monitor that wakes into the group is leased again
// and gets a second pass at its new session. At startup GLM sends every
// node its block, off ones included; blocksForGroup skips those.
static NSDictionary<NSString *, NSArray<NSString *> *> *QLMCapturedPasses(void) {
    return @{
        @"group-switch-main-4x2-main-2x2": @[@"Main 2x2", @"03:1000002 06:1000003 05:1000006 07:1000007"],
        @"group-switch-main-2x2-main-2x1": @[@"Main 2x1", @"03:1000002 06:1000003 05:1000006"],
        @"group-switch-main-2x1-main-4x2": @[@"Main 4x2", (@"03:1000002 06:1000003 04:1000004 02:1000005 05:1000006 07:1000007 "
                                                           @"08:1000005 09:1000004 0A:1000007")],
        @"group-switch-main-4x2-main-2x1": @[@"Main 2x1", @"03:1000002 06:1000003 05:1000006"],
        @"group-switch-main-2x1-main-2x2": @[@"Main 2x2", (@"03:1000002 06:1000003 05:1000006 0A:1000007 0B:1000007 "
                                                           @"03:1000002 06:1000003 05:1000006 0B:1000007")],
        @"group-switch-main-2x2-main-4x2": @[@"Main 4x2", (@"03:1000002 06:1000003 09:1000004 08:1000005 05:1000006 0B:1000007 "
                                                           @"0C:1000005 0D:1000004")],
        @"startup-idle": @[@"Main 2x1", @"02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"],
        @"startup-idle-mic": @[@"Main 2x1", @"02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"],
        @"knob-sweep": @[@"Main 2x1", @"02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"],
        @"standby-wake": @[@"Main 4x2", @"11:1000003 12:1000005 13:1000002 14:1000004 15:1000006 16:1000003 17:1000007"],
        @"unplug": @[@"Main 4x2", @"14:1000005 15:1000002 16:1000004 17:1000006 18:1000003 19:1000007"],
        @"unplug-proxy-hang": @[@"Main 4x2", @"08:1000005 09:1000002 0A:1000004 0B:1000006 0C:1000003 0D:1000007"],
    };
}

// Each session's model, from its reply to 39, where the capture holds one.
static NSDictionary<NSNumber *, NSString *> *QLMModelsInCapture(QLMCapture *capture) {
    NSMutableDictionary<NSNumber *, NSString *> *models = [NSMutableDictionary dictionary];
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        QLMMessage message = exchange.message;
        QLMMessage reply = exchange.reply;
        char text[QLMPayloadMax];
        char model[32];
        char firmware[32];
        if (message.length == 1 && message.payload[0] == 0x39 && exchange.answered && QLMReplyText(&reply, text, sizeof text) &&
            QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware)) {
            models[@(message.address)] = @(model);
        }
    }
    return models;
}

static QLMSetupGroup *QLMGroupNamed(NSString *name) {
    for (QLMSetupGroup *group in QLMReadFixtureSetup().groups) {
        if ([group.name isEqualToString:name]) {
            return group;
        }
    }
    return nil;
}

// Every captured pass matches its node's block, setting for setting, and
// no other node's. What qlm leaves out is exactly its class's extras. Where
// the capture holds the session's reply to 39, its model is the node's.
- (void)testEveryCapturedPassMatchesItsBlock {
    NSUInteger passes = 0;
    NSUInteger payloads = 0;
    NSUInteger identified = 0;
    QLMSetup *setup = QLMReadFixtureSetup();
    NSDictionary<NSString *, NSArray<NSString *> *> *table = QLMCapturedPasses();
    for (NSString *scenario in [table.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        QLMSetupGroup *group = QLMGroupNamed(table[scenario][0]);
        NSArray<NSString *> *expected = [table[scenario][1] componentsSeparatedByString:@" "];
        QLMCapture *capture = QLMReadCapture(scenario, NULL);
        NSArray<QLMCapturedPass *> *captured = QLMPassesInCapture(capture);
        NSDictionary<NSNumber *, NSString *> *models = QLMModelsInCapture(capture);
        XCTAssertEqual(captured.count, expected.count, @"%@", scenario);
        for (NSUInteger i = 0; i < MIN(captured.count, expected.count); i++) {
            QLMCapturedPass *pass = captured[i];
            NSArray<NSString *> *parts = [expected[i] componentsSeparatedByString:@":"];
            XCTAssertEqual(pass.session, (uint8_t)strtoul(parts[0].UTF8String, NULL, 16), @"%@ pass %lu", scenario, (unsigned long)i);
            NSString *model = models[@(pass.session)];
            if (model != nil) {
                XCTAssertEqualObjects(model, [setup deviceWithSerial:parts[1]].model, @"%@ at %.3f s", scenario, pass.time);
                identified += 1;
            }
            for (QLMSetupNode *node in group.nodes) {
                NSError *error = nil;
                QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:&error];
                XCTAssertNotNil(block, @"%@", error);
                NSArray<NSString *> *differences = QLMDifferences(block, pass);
                if ([node.serial isEqualToString:parts[1]]) {
                    XCTAssertNil(differences, @"%@ at %.3f s, %@: %@", scenario, pass.time, node.serial, differences);
                } else {
                    XCTAssertNotNil(differences, @"%@ at %.3f s also matches %@", scenario, pass.time, node.serial);
                }
            }
            passes += 1;
            payloads += pass.payloads.count;
        }
    }
    XCTAssertEqual(passes, 73u);
    XCTAssertEqual(payloads, 2467u);
    XCTAssertEqual(identified, 44u);
}

// A two-way's pass is its block in order, the 8351B's two extras aside: 43
// right after the level pair, and 4B right after the crossover.
- (void)testTwoWayPassesAreTheBlockInOrder {
    NSDictionary<NSString *, NSArray<NSString *> *> *table = QLMCapturedPasses();
    NSUInteger checked = 0;
    for (NSString *scenario in table) {
        QLMSetupGroup *group = QLMGroupNamed(table[scenario][0]);
        NSArray<NSString *> *expected = [table[scenario][1] componentsSeparatedByString:@" "];
        NSArray<QLMCapturedPass *> *captured = QLMPassesInCapture(QLMReadCapture(scenario, NULL));
        for (NSUInteger i = 0; i < MIN(captured.count, expected.count); i++) {
            QLMSetupNode *node = [group nodeWithSerial:[expected[i] componentsSeparatedByString:@":"][1]];
            if (node.nodeClass == QLMSetupNodeClassSubwoofer) {
                continue;
            }
            NSMutableArray<NSData *> *glm = [captured[i].payloads mutableCopy];
            if (node.nodeClass == QLMSetupNodeClassThreeWay) {
                XCTAssertEqualObjects(glm[4], QLMHex(@"43 00 02"), @"%@ at %.3f s", scenario, captured[i].time);
                XCTAssertEqualObjects(glm[26], QLMHex(@"4B 00 00 00 01"), @"%@ at %.3f s", scenario, captured[i].time);
                [glm removeObjectAtIndex:26];
                [glm removeObjectAtIndex:4];
            }
            NSArray<NSData *> *mine = [QLMDSPBlock blockForNode:node inGroup:group error:NULL].payloads;
            XCTAssertEqual(glm.count, mine.count, @"%@ at %.3f s", scenario, captured[i].time);
            for (NSUInteger j = 0; j < MIN(glm.count, mine.count); j++) {
                if (QLMIsLevel(mine[j])) {
                    XCTAssertTrue(QLMIsLevel(glm[j]));
                } else {
                    XCTAssertEqualObjects(glm[j], mine[j], @"%@ at %.3f s, frame %lu", scenario, captured[i].time, (unsigned long)j);
                }
            }
            checked += 1;
        }
    }
    XCTAssertEqual(checked, 47u);
}

// GLM floors the level word. qlm's builder rounds, so where the two differ
// its word is one count high, about 1e-6 dB. Four captured levels show it:
// the Left 8351B at -0.17 dB (group-switch-main-2x1-main-4x2, 35.618 s) and
// -5.3 dB (group-switch-main-4x2-main-2x2, 13.690 s), the Rear Right 8330A
// at -0.2 dB (group-switch-main-2x1-main-4x2, 36.137 s), and the Right
// 8351B at -2.97 dB (group-switch-main-4x2-main-2x1, 13.106 s).
- (void)testGLMFloorsTheLevelWord {
    NSDictionary<NSString *, NSArray<NSString *> *> *table = QLMCapturedPasses();
    NSMutableSet<NSNumber *> *levels = [NSMutableSet set];
    for (NSString *scenario in table) {
        QLMSetupGroup *group = QLMGroupNamed(table[scenario][0]);
        NSArray<NSString *> *expected = [table[scenario][1] componentsSeparatedByString:@" "];
        NSArray<QLMCapturedPass *> *captured = QLMPassesInCapture(QLMReadCapture(scenario, NULL));
        for (NSUInteger i = 0; i < MIN(captured.count, expected.count); i++) {
            QLMSetupNode *node = [group nodeWithSerial:[expected[i] componentsSeparatedByString:@":"][1]];
            double decibels = node.levelSensitivity + node.groupSensitivity;
            for (NSData *payload in captured[i].payloads) {
                if (QLMIsLevel(payload)) {
                    XCTAssertEqual(QLMLevelWordOf(payload), QLMFlooredLevelWord(decibels), @"%@ at %.3f s", scenario, captured[i].time);
                    [levels addObject:@(decibels)];
                }
            }
        }
    }
    XCTAssertEqual(levels.count, 11u);
    for (NSNumber *decibels in @[@-0.17, @-5.3, @-0.2, @-2.97]) {
        XCTAssertLessThanOrEqual(QLMLevelWordForDecibels(decibels.doubleValue) - QLMFlooredLevelWord(decibels.doubleValue), 1u);
    }
}

// A copy of `node` with every band at `sampleRate`.
static QLMSetupNode *QLMNodeAtRate(QLMSetupNode *node, double sampleRate) {
    QLMSetupNode *copy = [[QLMSetupNode alloc] init];
    copy.className = node.className;
    copy.nodeClass = node.nodeClass;
    copy.serial = node.serial;
    copy.input = node.input;
    copy.levelSensitivity = node.levelSensitivity;
    copy.timeOfFlightCompensation = node.timeOfFlightCompensation;
    copy.crossoverFrequency = node.crossoverFrequency;
    NSMutableArray<QLMSetupBand *> *bands = [NSMutableArray array];
    for (QLMSetupBand *band in node.bands) {
        QLMSetupBand *moved = [[QLMSetupBand alloc] init];
        moved.type = band.type;
        moved.index = band.index;
        moved.frequency = band.frequency;
        moved.gain = band.gain;
        moved.q = band.q;
        moved.sampleRate = sampleRate;
        [bands addObject:moved];
    }
    copy.bands = bands;
    return copy;
}

// The 8351B's design rate. Every slot GLM sent either 8351B in any group
// matches qlm's 96 kHz design bit for bit, and no filter matches a 48 kHz
// design. qlm still refuses the group. Lifting that is the user's decision.
- (void)testThe8351BIsDesignedAt96kHz {
    NSDictionary<NSString *, NSArray<NSString *> *> *table = QLMCapturedPasses();
    NSMutableSet<NSData *> *filters = [NSMutableSet set];
    for (NSString *scenario in table) {
        QLMSetupGroup *group = QLMGroupNamed(table[scenario][0]);
        NSArray<NSString *> *expected = [table[scenario][1] componentsSeparatedByString:@" "];
        NSArray<QLMCapturedPass *> *captured = QLMPassesInCapture(QLMReadCapture(scenario, NULL));
        for (NSUInteger i = 0; i < MIN(captured.count, expected.count); i++) {
            QLMSetupNode *node = [group nodeWithSerial:[expected[i] componentsSeparatedByString:@":"][1]];
            if (node.nodeClass != QLMSetupNodeClassThreeWay) {
                continue;
            }
            QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:NULL];
            XCTAssertEqual(block.designRate, 96000);
            XCTAssertFalse(block.rateVerified);
            NSArray<NSData *> *at48 = [QLMDSPBlock blockForNode:QLMNodeAtRate(node, 48000) inGroup:group error:NULL].payloads;
            const uint8_t bypass[] = {0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
            for (NSData *payload in captured[i].payloads) {
                const uint8_t *bytes = payload.bytes;
                if (bytes[0] != 0x10 || bytes[1] != 0x0E) {
                    continue;
                }
                XCTAssertEqualObjects(payload, block.payloads[4 + bytes[2]]);
                if (memcmp(bytes + 3, bypass, sizeof bypass) != 0) {
                    XCTAssertNotEqualObjects(payload, at48[4 + bytes[2]]);
                    [filters addObject:payload];
                }
            }
        }
    }
    XCTAssertEqual(filters.count, 41u);
}

@end
