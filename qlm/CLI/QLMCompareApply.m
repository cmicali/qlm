#import "QLMCompareApply.h"

#include <math.h>
#include <string.h>
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
@property (nonatomic, readwrite) BOOL cutShort;
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
            open.cutShort = YES;
            [stops removeObjectForKey:@(message.address)];
            if (exchange.time >= from && exchange.time < to) {
                [passes addObject:open];
            }
        }
        if (open == nil || message.address != open.session) {
            continue;
        }
        if (!open.cutShort && payload[0] != 0x40) {
            open = nil;
            continue;
        }
        if (QLMIsDSPOpcode(payload[0])) {
            [openPayloads addObject:QLMPayloadOf(message)];
            open.cutShort = open.cutShort && payload[0] != 0x3D;
        }
    }
    for (QLMCapturedPass *pass in passes) {
        pass.model = models[@(pass.session)];
        pass.hardwareID = leases[@(pass.session)];
    }
    return passes;
}

@implementation QLMCapturedStop
@end

NSArray<QLMCapturedStop *> *QLMGeneratorStopsInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to) {
    NSMutableArray<QLMCapturedStop *> *stops = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        QLMMessage message = exchange.message;
        if (message.length > 0 && message.payload[0] == 0x05 && QLMAddressIsLeasable(message.address) && exchange.time >= from &&
            exchange.time < to) {
            QLMCapturedStop *stop = [[QLMCapturedStop alloc] init];
            stop.session = message.address;
            stop.time = exchange.time;
            stop.payload = QLMPayloadOf(message);
            [stops addObject:stop];
        }
    }
    return stops;
}

BOOL QLMIsKnownGeneratorStop(NSData *payload) {
    static const uint8_t known[] = {0x05, 0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xEA, 0x00, 0x01, 0x90, 0x00, 0x02, 0xDA};
    return payload.length == sizeof known && memcmp(payload.bytes, known, sizeof known) == 0;
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
    NSArray<NSData *> *extras = block.leftOutPayloads;
    NSMutableOrderedSet<NSData *> *leftOut = [NSMutableOrderedSet orderedSet];
    NSMutableArray<NSData *> *kept = [NSMutableArray array];
    for (NSData *payload in pass.payloads) {
        if ([extras containsObject:payload]) {
            [leftOut addObject:payload];
        } else {
            [kept addObject:payload];
        }
    }
    NSArray<NSData *> *payloads = block.payloads;
    if (pass.cutShort && kept.count < payloads.count) {
        payloads = [payloads subarrayWithRange:NSMakeRange(0, kept.count)];
    }
    NSMutableDictionary<NSData *, NSData *> *expected = [NSMutableDictionary dictionary];
    for (NSData *payload in payloads) {
        expected[QLMSettingKey(payload)] = payload;
    }
    NSMutableArray<NSArray<NSData *> *> *changed = [NSMutableArray array];
    NSMutableSet<NSData *> *changedSeen = [NSMutableSet set];
    NSMutableOrderedSet<NSData *> *glmOnly = [NSMutableOrderedSet orderedSet];
    NSMutableSet<NSData *> *seen = [NSMutableSet set];
    for (NSData *payload in kept) {
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
    for (NSData *payload in payloads) {
        if (![seen containsObject:QLMSettingKey(payload)]) {
            [qlmOnly addObject:payload];
        }
    }
    NSMutableArray<NSData *> *missing = [NSMutableArray array];
    for (NSData *extra in extras) {
        if (!pass.cutShort && ![leftOut containsObject:extra]) {
            [missing addObject:extra];
        }
    }

    QLMBlockComparison *comparison = [[QLMBlockComparison alloc] init];
    comparison.changed = changed;
    comparison.glmOnly = glmOnly.array;
    comparison.leftOut = leftOut.array;
    comparison.missingLeftOut = missing;
    comparison.qlmOnly = qlmOnly.array;
    comparison.inOrder = [kept isEqualToArray:payloads];
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
@property (nonatomic, readwrite) QLMSetupGroup *group;
@property (nonatomic, readwrite, nullable) QLMSetupNode *node;
@property (nonatomic, readwrite, nullable) QLMDSPBlock *block;
@property (nonatomic, readwrite, nullable) QLMBlockComparison *comparison;
@property (nonatomic, readwrite) NSUInteger ties;
@property (nonatomic, readwrite, nullable) QLMCapturedPass *earlierPass;
@end

@implementation QLMPassMatch

- (BOOL)matches {
    return self.comparison.matches && self.earlierPass == nil;
}

@end

// The later pass may have reached the earlier one's monitor. Where the
// capture holds both sessions' leases, their hardware IDs say. A later
// session leased in the capture may be the monitor leased again, as when
// one wakes into the group. Otherwise only the same session is.
static BOOL QLMMaybeSameMonitor(QLMCapturedPass *earlier, QLMCapturedPass *later) {
    if (earlier.hardwareID != nil && later.hardwareID != nil) {
        return [earlier.hardwareID isEqualToData:later.hardwareID];
    }
    return later.hardwareID != nil || earlier.session == later.session;
}

// A node a pass may match, with its block, and its device's model.
@interface QLMMatchCandidate : NSObject
@property (nonatomic) QLMSetupNode *node;
@property (nonatomic) QLMDSPBlock *block;
@property (nonatomic, nullable) NSString *model;
@end

@implementation QLMMatchCandidate
@end

NSArray<QLMPassMatch *> *QLMMatchPasses(NSArray<QLMCapturedPass *> *passes, QLMSetup *setup, QLMSetupGroup *group,
                                        NSArray<NSString *> **refusals) {
    NSMutableArray<QLMMatchCandidate *> *candidates = [NSMutableArray array];
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    NSMutableArray<NSString *> *refused = [NSMutableArray array];
    for (QLMSetupNode *node in group.nodes) {
        NSError *error = nil;
        QLMDSPBlock *block = [QLMDSPBlock blockForNode:node inGroup:group error:&error];
        if (block == nil) {
            [refused addObject:[NSString stringWithFormat:@"node %@: %@", node.serial, error.localizedDescription]];
            continue;
        }
        QLMMatchCandidate *candidate = [[QLMMatchCandidate alloc] init];
        candidate.node = node;
        candidate.block = block;
        candidate.model = [setup deviceWithSerial:node.serial].model;
        [candidates addObject:candidate];
        if (node.hardwareID != nil) {
            [hardwareIDs addObject:node.hardwareID];
        }
    }
    if (refusals != NULL) {
        *refusals = refused;
    }

    NSMutableArray<QLMPassMatch *> *matches = [NSMutableArray array];
    NSMutableDictionary<NSString *, QLMCapturedPass *> *firstPasses = [NSMutableDictionary dictionary];
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
        match.group = group;
        match.node = best.node;
        match.block = best.block;
        match.comparison = bestComparison;
        match.ties = ties;
        if (best != nil) {
            QLMCapturedPass *first = firstPasses[best.node.serial];
            if (first == nil) {
                firstPasses[best.node.serial] = pass;
            } else if (!QLMMaybeSameMonitor(first, pass)) {
                match.earlierPass = first;
            }
        }
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
    fprintf(out, "%s %s \"%s\": ", device.model.UTF8String ?: "?", match.node.serial.UTF8String, device.name.UTF8String ?: "");
    if (match.earlierPass != nil) {
        fprintf(out, "%s, but session %02X's pass at %.3f s took this node first\n",
                comparison.matches ? "the same block" : "closest", match.earlierPass.session, match.earlierPass.time);
    } else if (comparison.matches) {
        fprintf(out, pass.cutShort ? "cut short by GLM, and matches the block's start\n" : "matches\n");
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
    if (!match.matches && match.ties > 0) {
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
    QLMSetupGroup *group = [setup groupNamed:given[@"--group"]];
    if (group == nil) {
        fprintf(err, "qlmctl: no group named '%s'\n", given[@"--group"].UTF8String);
        return EX_DATAERR;
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
    NSArray<QLMPassMatch *> *matches = QLMMatchPasses(passes, setup, group, &refusals);
    fprintf(out, "%s, %s, against %lu DSP %s in %s\n", setup.setupName.UTF8String ?: "(unnamed setup)", group.name.UTF8String,
            (unsigned long)passes.count, passes.count == 1 ? "pass" : "passes", reports.UTF8String);
    for (NSString *refusal in refusals) {
        fprintf(out, "qlm builds no block for %s\n", refusal.UTF8String);
    }
    fprintf(out, "\n");
    NSUInteger matched = 0;
    for (QLMPassMatch *match in matches) {
        QLMPrintMatch(out, match, setup);
        matched += match.matches ? 1 : 0;
    }
    NSArray<QLMCapturedStop *> *stops = QLMGeneratorStopsInCapture(capture, from, to);
    NSUInteger oddStops = 0;
    for (QLMCapturedStop *stop in stops) {
        if (!QLMIsKnownGeneratorStop(stop.payload)) {
            if (oddStops++ == 0) {
                fprintf(out, "\n");
            }
            fprintf(out, "%8.3f s  session %02X  a generator stop qlm doesn't know\n", stop.time, stop.session);
            QLMPrintPayload(out, "GLM only", stop.payload);
        }
    }
    fprintf(out, "\n%lu of %lu generator %s are the known 05 04 00 00 00 FF FF EA 00 01 90 00 02 DA.\n",
            (unsigned long)(stops.count - oddStops), (unsigned long)stops.count, stops.count == 1 ? "stop" : "stops");
    fprintf(out, "%lu of %lu %s match", (unsigned long)matched, (unsigned long)matches.count, matches.count == 1 ? "pass" : "passes");
    if (matched < matches.count || oddStops > 0) {
        fprintf(out, ". %lu %s, and %lu generator %s.\n", (unsigned long)(matches.count - matched),
                matches.count - matched == 1 ? "differs" : "differ", (unsigned long)oddStops, oddStops == 1 ? "stop differs" : "stops differ");
        return QLMCompareApplyDiffers;
    }
    fprintf(out, ", apart from what qlm leaves out: the generator stop, and the 8351B's 43 00 02 and 4B 00 00 00 01.\n");
    return 0;
}
