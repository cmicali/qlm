#import "QLMCompareApply.h"

#include <math.h>
#include <sysexits.h>

#include "QLMFrame.h"
#include "QLMReplies.h"
#import "QLMControl.h"
#import "QLMSetupReader.h"

const int QLMCompareApplyDiffers = 1;

@interface QLMCapturedPass ()
@property (nonatomic, readwrite) uint8_t session;
@property (nonatomic, readwrite) NSTimeInterval time;
@property (nonatomic, readwrite) NSArray<NSData *> *payloads;
@property (nonatomic, readwrite) NSArray<NSData *> *generatorStops;
@property (nonatomic, readwrite, nullable) NSString *model;
@property (nonatomic, readwrite, nullable) NSData *hardwareID;
@end

@implementation QLMCapturedPass

- (NSString *)description {
    return [NSString stringWithFormat:@"session %02X at %.3f s", self.session, self.time];
}

@end

static BOOL QLMIsDSPOpcode(uint8_t opcode) {
    switch (opcode) {
    case 0x10: case 0x17: case 0x3B: case 0x3C: case 0x3D: case 0x3E: case 0x40: case 0x42: case 0x43: case 0x4B:
        return YES;
    default:
        return NO;
    }
}

static NSData *QLMPayloadOf(QLMMessage message) {
    return [NSData dataWithBytes:message.payload length:message.length];
}

NSArray<QLMCapturedPass *> *QLMPassesInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to) {
    NSMutableArray<QLMCapturedPass *> *passes = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSMutableArray<NSData *> *> *stops = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSData *> *leases = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *models = [NSMutableDictionary dictionary];
    QLMCapturedPass *open = nil;
    NSMutableArray<NSData *> *openPayloads = nil;
    BOOL synced = NO;
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        QLMMessage message = exchange.message;
        const uint8_t *payload = message.payload;
        if (message.address == QLMAddressMulticast && message.length == 5 && payload[0] == 0x02) {
            leases[@(payload[4])] = [NSData dataWithBytes:payload + 1 length:3];
        } else if (message.length > 0 && payload[0] == 0x05 && QLMAddressIsLeasable(message.address)) {
            NSMutableArray<NSData *> *sessionStops = stops[@(message.address)] ?: [NSMutableArray array];
            [sessionStops addObject:QLMPayloadOf(message)];
            stops[@(message.address)] = sessionStops;
        }
        if (message.length == 1 && payload[0] == 0x39 && exchange.answered) {
            QLMMessage reply = exchange.reply;
            char text[QLMPayloadMax];
            char model[32];
            char firmware[32];
            if (QLMReplyText(&reply, text, sizeof text) && QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware)) {
                models[@(message.address)] = @(model);
            }
        }
        if (message.length >= 2 && payload[0] == 0x17 && payload[1] == 0x01) {
            open = [[QLMCapturedPass alloc] init];
            open.session = message.address;
            open.time = exchange.time;
            openPayloads = [NSMutableArray array];
            open.payloads = openPayloads;
            open.generatorStops = stops[@(message.address)] ?: @[];
            [stops removeObjectForKey:@(message.address)];
            if (exchange.time >= from && exchange.time < to) {
                [passes addObject:open];
            }
            synced = NO;
        }
        if (open == nil || message.address != open.session) {
            continue;
        }
        if (synced && payload[0] != 0x40) {
            open = nil;
            continue;
        }
        if (QLMIsDSPOpcode(payload[0])) {
            [openPayloads addObject:QLMPayloadOf(message)];
            synced = synced || payload[0] == 0x3D;
        }
    }
    for (QLMCapturedPass *pass in passes) {
        pass.model = models[@(pass.session)];
        pass.hardwareID = leases[@(pass.session)];
    }
    return passes;
}

#pragma mark - The comparison

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

// The generator stop GLM sends a session before each pass, the same 14
// bytes in every capture.
static NSData *QLMKnownGeneratorStop(void) {
    static NSData *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const uint8_t stop[] = {0x05, 0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xEA, 0x00, 0x01, 0x90, 0x00, 0x02, 0xDA};
        known = [NSData dataWithBytes:stop length:sizeof stop];
    });
    return known;
}

@interface QLMBlockComparison ()
@property (nonatomic, readwrite) NSArray<NSArray<NSData *> *> *changed;
@property (nonatomic, readwrite) NSArray<NSData *> *glmOnly;
@property (nonatomic, readwrite) NSArray<NSData *> *leftOut;
@property (nonatomic, readwrite) NSArray<NSData *> *missingLeftOut;
@property (nonatomic, readwrite) NSArray<NSData *> *qlmOnly;
@property (nonatomic, readwrite) BOOL inOrder;
// Fewer differences first, then in order.
- (NSUInteger)rank;
@end

@implementation QLMBlockComparison

+ (instancetype)comparisonOfBlock:(QLMDSPBlock *)block withPass:(QLMCapturedPass *)pass {
    NSMutableDictionary<NSData *, NSData *> *expected = [NSMutableDictionary dictionary];
    for (NSData *payload in block.payloads) {
        expected[QLMSettingKey(payload)] = payload;
    }
    NSArray<NSData *> *extras = block.leftOutPayloads;
    NSMutableArray<NSArray<NSData *> *> *changed = [NSMutableArray array];
    NSMutableSet<NSData *> *changedSeen = [NSMutableSet set];
    NSMutableOrderedSet<NSData *> *glmOnly = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSData *> *leftOut = [NSMutableOrderedSet orderedSet];
    NSMutableSet<NSData *> *seen = [NSMutableSet set];
    NSMutableArray<NSData *> *kept = [NSMutableArray array];
    NSData *knownStop = QLMKnownGeneratorStop();
    for (NSData *stop in pass.generatorStops) {
        [([stop isEqualToData:knownStop] ? leftOut : glmOnly) addObject:stop];
    }
    for (NSData *payload in pass.payloads) {
        if ([extras containsObject:payload]) {
            [leftOut addObject:payload];
            continue;
        }
        [kept addObject:payload];
        NSData *key = QLMSettingKey(payload);
        NSData *mine = expected[key];
        if (mine == nil) {
            [glmOnly addObject:payload];
            continue;
        }
        [seen addObject:key];
        if (![mine isEqualToData:payload] && ![changedSeen containsObject:payload]) {
            [changedSeen addObject:payload];
            [changed addObject:@[payload, mine]];
        }
    }
    NSMutableOrderedSet<NSData *> *qlmOnly = [NSMutableOrderedSet orderedSet];
    for (NSData *payload in block.payloads) {
        if (![seen containsObject:QLMSettingKey(payload)]) {
            [qlmOnly addObject:payload];
        }
    }
    NSMutableArray<NSData *> *missing = [NSMutableArray array];
    for (NSData *extra in extras) {
        if (![leftOut containsObject:extra]) {
            [missing addObject:extra];
        }
    }

    QLMBlockComparison *comparison = [[QLMBlockComparison alloc] init];
    comparison.changed = changed;
    comparison.glmOnly = glmOnly.array;
    comparison.leftOut = leftOut.array;
    comparison.missingLeftOut = missing;
    comparison.qlmOnly = qlmOnly.array;
    comparison.inOrder = [kept isEqualToArray:block.payloads];
    return comparison;
}

- (NSUInteger)differenceCount {
    return self.changed.count + self.glmOnly.count + self.missingLeftOut.count + self.qlmOnly.count;
}

- (BOOL)matches {
    return self.differenceCount == 0 && self.inOrder;
}

- (NSUInteger)rank {
    return self.differenceCount * 2 + (self.inOrder ? 0 : 1);
}

@end

#pragma mark - The match

@interface QLMPassMatch ()
@property (nonatomic, readwrite) QLMCapturedPass *pass;
@property (nonatomic, readwrite, nullable) QLMSetupGroup *group;
@property (nonatomic, readwrite, nullable) QLMSetupNode *node;
@property (nonatomic, readwrite, nullable) QLMDSPBlock *block;
@property (nonatomic, readwrite, nullable) QLMBlockComparison *comparison;
@property (nonatomic, readwrite) NSUInteger ties;
@end

@implementation QLMPassMatch
@end

// A node a pass may match, with its block, and its device's model.
@interface QLMMatchCandidate : NSObject
@property (nonatomic) QLMSetupGroup *group;
@property (nonatomic) QLMSetupNode *node;
@property (nonatomic) QLMDSPBlock *block;
@property (nonatomic, nullable) NSString *model;
@end

@implementation QLMMatchCandidate
@end

NSArray<QLMPassMatch *> *QLMMatchPasses(NSArray<QLMCapturedPass *> *passes, QLMSetup *setup, NSArray<QLMSetupGroup *> *groups,
                                        NSArray<NSString *> **refusals) {
    NSMutableArray<QLMMatchCandidate *> *candidates = [NSMutableArray array];
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    NSMutableArray<NSString *> *refused = [NSMutableArray array];
    for (QLMSetupGroup *group in groups ?: setup.groups) {
        for (QLMSetupNode *node in group.nodes) {
            NSError *error = nil;
            QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:&error];
            if (block == nil) {
                [refused addObject:[NSString stringWithFormat:@"%@, node %@: %@", group.name, node.serial, error.localizedDescription]];
                continue;
            }
            QLMMatchCandidate *candidate = [[QLMMatchCandidate alloc] init];
            candidate.group = group;
            candidate.node = node;
            candidate.block = block;
            candidate.model = [setup deviceWithSerial:node.serial].model;
            [candidates addObject:candidate];
            if (node.hardwareID != nil) {
                [hardwareIDs addObject:node.hardwareID];
            }
        }
    }
    if (refusals != NULL) {
        *refusals = refused;
    }

    NSMutableArray<QLMPassMatch *> *matches = [NSMutableArray array];
    for (QLMCapturedPass *pass in passes) {
        BOOL byHardwareID = pass.hardwareID != nil && [hardwareIDs containsObject:pass.hardwareID];
        QLMMatchCandidate *best = nil;
        QLMBlockComparison *bestComparison = nil;
        NSUInteger ties = 0;
        for (QLMMatchCandidate *candidate in candidates) {
            if ((pass.model != nil && ![candidate.model isEqualToString:pass.model]) ||
                (byHardwareID && ![candidate.node.hardwareID isEqualToData:pass.hardwareID])) {
                continue;
            }
            QLMBlockComparison *comparison = [QLMBlockComparison comparisonOfBlock:candidate.block withPass:pass];
            if (best == nil || comparison.rank < bestComparison.rank) {
                best = candidate;
                bestComparison = comparison;
                ties = 0;
            } else if (comparison.rank == bestComparison.rank && ![candidate.block.payloads isEqualToArray:best.block.payloads]) {
                ties += 1;
            }
        }
        QLMPassMatch *match = [[QLMPassMatch alloc] init];
        match.pass = pass;
        match.group = best.group;
        match.node = best.node;
        match.block = best.block;
        match.comparison = bestComparison;
        match.ties = ties;
        [matches addObject:match];
    }
    return matches;
}

#pragma mark - The verb

static NSString *QLMHexText(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:payload.length];
    for (NSUInteger i = 0; i < payload.length; i++) {
        [pairs addObject:[NSString stringWithFormat:@"%02X", bytes[i]]];
    }
    return [pairs componentsJoinedByString:@" "];
}

static void QLMPrintPayload(FILE *out, const char *label, NSData *payload) {
    fprintf(out, "  %-10s %s\n", label, QLMHexText(payload).UTF8String);
}

static int QLMCompareRefuse(FILE *err, NSString *problem) {
    fprintf(err, "qlmctl: %s\nqlmctl: compare-apply reads two files and opens no bus. qlmctl help lists its options.\n",
            problem.UTF8String);
    return EX_USAGE;
}

static void QLMPrintMatch(FILE *out, QLMPassMatch *match, QLMSetup *setup) {
    QLMCapturedPass *pass = match.pass;
    fprintf(out, "%8.3f s  session %02X  ", pass.time, pass.session);
    QLMBlockComparison *comparison = match.comparison;
    if (comparison == nil) {
        fprintf(out, "%s: no node qlm builds a block for can match\n", pass.model.UTF8String ?: "?");
        for (NSData *payload in pass.payloads) {
            QLMPrintPayload(out, "GLM only", payload);
        }
        return;
    }
    QLMSetupDevice *device = [setup deviceWithSerial:match.node.serial];
    fprintf(out, "%s %s \"%s\" in %s: ", device.model.UTF8String ?: "?", match.node.serial.UTF8String,
            device.name.UTF8String ?: "", match.group.name.UTF8String);
    if (comparison.matches) {
        fprintf(out, "matches\n");
    } else if (comparison.differenceCount == 0) {
        fprintf(out, "the same settings, not in GLM's order\n");
    } else {
        fprintf(out, "%lu %s\n", (unsigned long)comparison.differenceCount, comparison.differenceCount == 1 ? "difference" : "differences");
    }
    for (NSArray<NSData *> *pair in comparison.changed) {
        QLMPrintPayload(out, "GLM", pair[0]);
        QLMPrintPayload(out, "qlm", pair[1]);
    }
    for (NSData *payload in comparison.glmOnly) {
        QLMPrintPayload(out, "GLM only", payload);
    }
    for (NSData *payload in comparison.qlmOnly) {
        QLMPrintPayload(out, "qlm only", payload);
    }
    for (NSData *payload in comparison.missingLeftOut) {
        QLMPrintPayload(out, "not sent", payload);
    }
    for (NSData *payload in comparison.leftOut) {
        QLMPrintPayload(out, "left out", payload);
    }
    if (!comparison.matches && match.ties > 0) {
        fprintf(out, "  %lu other %s as close\n", (unsigned long)match.ties, match.ties == 1 ? "node is" : "nodes are");
    }
}

int QLMCompareApply(NSArray<NSString *> *arguments, FILE *out, FILE *err) {
    NSString *problem = nil;
    NSDictionary<NSString *, NSString *> *given = QLMCompareArguments(arguments, &problem);
    if (given == nil) {
        return QLMCompareRefuse(err, problem);
    }
    NSString *reports = given[@"reports"];
    double from = given[@"--from"] != nil ? given[@"--from"].doubleValue : 0;
    double to = given[@"--to"] != nil ? given[@"--to"].doubleValue : INFINITY;

    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readFileAtPath:given[@"setup"] error:&error];
    if (setup == nil) {
        fprintf(err, "qlmctl: %s: %s\n", given[@"setup"].UTF8String, error.localizedDescription.UTF8String);
        return EX_DATAERR;
    }
    NSArray<QLMSetupGroup *> *groups = nil;
    if (given[@"--group"] != nil) {
        QLMSetupGroup *group = [setup groupNamed:given[@"--group"]];
        if (group == nil) {
            fprintf(err, "qlmctl: no group named '%s'\n", given[@"--group"].UTF8String);
            return EX_DATAERR;
        }
        groups = @[group];
    }
    QLMCapture *capture = [QLMCapture captureWithContentsOfFile:reports error:&error];
    if (capture == nil) {
        fprintf(err, "qlmctl: %s: %s\n", reports.UTF8String, error.localizedDescription.UTF8String);
        return EX_DATAERR;
    }
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(capture, from, to);
    if (passes.count == 0) {
        fprintf(err, "qlmctl: %s holds no DSP pass%s\n", reports.UTF8String, isinf(to) && from == 0 ? "" : " in that window");
        return EX_DATAERR;
    }

    NSArray<NSString *> *refusals = nil;
    NSArray<QLMPassMatch *> *matches = QLMMatchPasses(passes, setup, groups, &refusals);
    fprintf(out, "%s, %s, against %lu DSP %s in %s\n", setup.setupName.UTF8String ?: "(unnamed setup)",
            groups != nil ? groups[0].name.UTF8String : "every group", (unsigned long)passes.count,
            passes.count == 1 ? "pass" : "passes", reports.UTF8String);
    for (NSString *refusal in refusals) {
        fprintf(out, "qlm builds no block for %s\n", refusal.UTF8String);
    }
    fprintf(out, "\n");
    NSUInteger matched = 0;
    for (QLMPassMatch *match in matches) {
        QLMPrintMatch(out, match, setup);
        matched += match.comparison.matches ? 1 : 0;
    }
    fprintf(out, "\n%lu of %lu %s match", (unsigned long)matched, (unsigned long)matches.count,
            matches.count == 1 ? "pass" : "passes");
    if (matched < matches.count) {
        fprintf(out, ". %lu %s.\n", (unsigned long)(matches.count - matched), matches.count - matched == 1 ? "differs" : "differ");
        return QLMCompareApplyDiffers;
    }
    fprintf(out, ", apart from what qlm leaves out: the generator stop, and the 8351B's 43 00 02 and 4B 00 00 00 01.\n");
    return 0;
}
