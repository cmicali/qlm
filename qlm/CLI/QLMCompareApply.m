#import "QLMCompareApply.h"

#include <math.h>
#include <string.h>
#include <sysexits.h>

#include "QLMFrame.h"
#include "QLMReplies.h"
#import "QLMControl.h"
#import "QLMSetupReader.h"

const int QLMCompareApplyDiffers = 1;

// What one lease of a session names: the hardware ID it leased, and the
// model the session's next reply to 39 gives. Each 39 reply comes a few ms
// after its lease. qlm's runs and Phase 0's captures lease monitors again,
// at new sessions or reused ones, so a session's model holds only for its
// lease. A session leased before the capture began has no hardware ID.
@interface QLMLease : NSObject
@property (nonatomic, nullable) NSData *hardwareID;
@property (nonatomic, nullable) NSString *model;
@end

@implementation QLMLease
@end

@interface QLMCapturedPass ()
@property (nonatomic, readwrite) uint8_t session;
@property (nonatomic, readwrite) NSTimeInterval time;
@property (nonatomic, readwrite) NSArray<NSData *> *payloads;
@property (nonatomic, readwrite) NSArray<NSData *> *generatorStops;
@property (nonatomic, readwrite) BOOL cutShort;
@property (nonatomic) QLMLease *lease;
@end

@implementation QLMCapturedPass

- (nullable NSString *)model {
    return self.lease.model;
}

- (nullable NSData *)hardwareID {
    return self.lease.hardwareID;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"session %02X at %.3f s", self.session, self.time];
}

@end

@interface QLMSessionFrame ()
@property (nonatomic, nullable) QLMLease *lease;
@end

@implementation QLMSessionFrame

- (nullable NSString *)model {
    return self.lease.model;
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

static BOOL QLMInWindow(NSTimeInterval time, NSTimeInterval from, NSTimeInterval to) {
    return time >= from && time < to;
}

static QLMSessionFrame *QLMFrameOf(QLMCaptureExchange *exchange) {
    QLMSessionFrame *frame = [[QLMSessionFrame alloc] init];
    frame.session = exchange.message.address;
    frame.time = exchange.time;
    frame.payload = QLMPayloadOf(exchange.message);
    return frame;
}

NSArray<QLMCapturedPass *> *QLMPassesInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to,
                                               NSArray<QLMSessionFrame *> **outside) {
    NSMutableArray<QLMCapturedPass *> *passes = [NSMutableArray array];
    NSMutableArray<QLMSessionFrame *> *frames = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSMutableArray<NSData *> *> *stops = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, QLMLease *> *leases = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, QLMCapturedPass *> *lastPasses = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSMutableArray<QLMSessionFrame *> *> *waiting = [NSMutableDictionary dictionary];
    QLMCapturedPass *open = nil;
    NSMutableArray<NSData *> *openPayloads = nil;
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        QLMMessage message = exchange.message;
        const uint8_t *payload = message.payload;
        NSNumber *session = @(message.address);
        if (message.address == QLMAddressMulticast && message.length == 5 && payload[0] == 0x02) {
            QLMLease *lease = [[QLMLease alloc] init];
            lease.hardwareID = [NSData dataWithBytes:payload + 1 length:3];
            leases[@(payload[4])] = lease;
            continue;
        }
        if (!QLMAddressIsLeasable(message.address) || message.length == 0) {
            continue;
        }
        if (leases[session] == nil) {
            leases[session] = [[QLMLease alloc] init];
        }
        if (payload[0] == 0x05) {
            NSMutableArray<NSData *> *sessionStops = stops[session] ?: [NSMutableArray array];
            [sessionStops addObject:QLMPayloadOf(message)];
            stops[session] = sessionStops;
        }
        if (message.length == 1 && payload[0] == 0x39 && exchange.answered && leases[session].model == nil) {
            QLMMessage reply = exchange.reply;
            char text[QLMPayloadMax];
            char model[32];
            char firmware[32];
            if (QLMReplyText(&reply, text, sizeof text) && QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware)) {
                leases[session].model = @(model);
            }
        }
        if (message.length >= 2 && payload[0] == 0x17 && payload[1] == 0x01) {
            open = [[QLMCapturedPass alloc] init];
            open.session = message.address;
            open.time = exchange.time;
            openPayloads = [NSMutableArray array];
            open.payloads = openPayloads;
            open.generatorStops = stops[session] ?: @[];
            open.cutShort = YES;
            open.lease = leases[session];
            [stops removeObjectForKey:session];
            lastPasses[session] = open;
            BOOL inWindow = QLMInWindow(exchange.time, from, to);
            if (inWindow) {
                [passes addObject:open];
            }
            for (QLMSessionFrame *frame in waiting[session]) {
                frame.precedes = inWindow ? open : nil;
            }
            [waiting removeObjectForKey:session];
        }
        // A pass ends at the first frame to its session after the 40 frames
        // that follow its 3D, or at the next 17 01. TRAP: no frame before
        // its 3D marks a pass cut short. GLM's cycle sends a session its
        // poll, 08, and its state, 2B, mid-pass (setup-j-restore, 35.009
        // and 35.013 s to 0E), and it leases monitors mid-pass
        // (setup-b-peq-8351b, 182.734 s, in 0D's pass).
        BOOL inPass = open != nil && message.address == open.session;
        if (inPass && !open.cutShort && payload[0] != 0x40) {
            open = nil;
            inPass = NO;
        }
        if (!QLMIsDSPOpcode(payload[0])) {
            continue;
        }
        if (inPass) {
            [openPayloads addObject:QLMPayloadOf(message)];
            open.cutShort = open.cutShort && payload[0] != 0x3D;
        } else if (QLMInWindow(exchange.time, from, to)) {
            QLMSessionFrame *frame = QLMFrameOf(exchange);
            QLMCapturedPass *last = lastPasses[session];
            frame.follows = last != nil && QLMInWindow(last.time, from, to) ? last : nil;
            frame.lease = leases[session];
            [frames addObject:frame];
            waiting[session] = waiting[session] ?: [NSMutableArray array];
            [waiting[session] addObject:frame];
        }
    }
    if (outside != NULL) {
        *outside = frames;
    }
    return passes;
}

NSArray<QLMSessionFrame *> *QLMGeneratorStopsInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to) {
    NSMutableArray<QLMSessionFrame *> *stops = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        QLMMessage message = exchange.message;
        if (message.length > 0 && message.payload[0] == 0x05 && QLMAddressIsLeasable(message.address) &&
            QLMInWindow(exchange.time, from, to)) {
            [stops addObject:QLMFrameOf(exchange)];
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

static BOOL QLMIsBand(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    return payload.length >= 3 && bytes[0] == 0x10 && bytes[1] == 0x0E;
}

NSData *QLMBlockSetting(QLMDSPBlock *block, NSData *payload) {
    NSData *key = QLMSettingKey(payload);
    NSData *found = nil;
    for (NSData *sent in [block.payloads arrayByAddingObjectsFromArray:block.leftOutPayloads]) {
        found = [QLMSettingKey(sent) isEqualToData:key] ? sent : found;
    }
    return found;
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

typedef NS_ENUM(NSInteger, QLMOutsideVerdict) {
    QLMOutsideExplained,
    QLMOutsidePassedThrough,
    QLMOutsideUnexplained,
};

// What compare-apply makes of each frame outside a pass in its window.
@interface QLMOutsideReader : NSObject
- (instancetype)initWithFrames:(NSArray<QLMSessionFrame *> *)frames
                       matches:(NSArray<QLMPassMatch *> *)matches
                         setup:(QLMSetup *)setup
                         group:(QLMSetupGroup *)group;
- (QLMOutsideVerdict)verdictOf:(QLMSessionFrame *)frame label:(NSString *_Nonnull *_Nonnull)label;
// The pass a frame is listed before: the one its routing frame is for, or
// the next, for a frame no pass in the window comes before. Nil for a frame
// listed after its pass, or one with no pass at its session.
- (nullable QLMCapturedPass *)passListedBefore:(QLMSessionFrame *)frame;
@end

static BOOL QLMIsRouting(NSData *payload) {
    const uint8_t *bytes = payload.bytes;
    return bytes[0] == 0x3B || bytes[0] == 0x40;
}

// The session, then the setting the frame names.
static NSData *QLMSessionSetting(QLMSessionFrame *frame) {
    uint8_t session = frame.session;
    NSMutableData *key = [NSMutableData dataWithBytes:&session length:1];
    [key appendData:QLMSettingKey(frame.payload)];
    return key;
}

@implementation QLMOutsideReader {
    NSArray<QLMPassMatch *> *_matches;
    QLMSetup *_setup;
    QLMSetupGroup *_group;
    NSMutableDictionary<NSString *, QLMDSPBlock *> *_blocks;   // by node serial
    NSMutableDictionary<NSData *, QLMSessionFrame *> *_lasts;  // by session and setting
    NSSet<QLMSessionFrame *> *_routing;                         // each pass's own
}

- (instancetype)initWithFrames:(NSArray<QLMSessionFrame *> *)frames
                       matches:(NSArray<QLMPassMatch *> *)matches
                         setup:(QLMSetup *)setup
                         group:(QLMSetupGroup *)group {
    self = [super init];
    _matches = matches;
    _setup = setup;
    _group = group;
    _blocks = [NSMutableDictionary dictionary];
    for (QLMSetupNode *node in group.nodes) {
        _blocks[node.serial] = [QLMDSPBlock blockForNode:node inGroup:group error:NULL];
    }
    _lasts = [NSMutableDictionary dictionary];
    // A switch routes the monitors it leaves off too, and they get no pass.
    // So a routing frame is its next pass's only when it's the last of its
    // setting before that pass. setup-a-baseline routes the 7350A for Main
    // 2x1 at 40.049 s, and again for Main 4x2 before its pass at 46.940 s.
    NSMutableDictionary<NSArray *, QLMSessionFrame *> *routing = [NSMutableDictionary dictionary];
    for (QLMSessionFrame *frame in frames) {
        _lasts[QLMSessionSetting(frame)] = frame;
        if (QLMIsRouting(frame.payload) && frame.precedes != nil) {
            routing[@[QLMSessionSetting(frame), frame.precedes]] = frame;
        }
    }
    _routing = [NSSet setWithArray:routing.allValues];
    return self;
}

- (nullable QLMCapturedPass *)passListedBefore:(QLMSessionFrame *)frame {
    return [_routing containsObject:frame] || frame.follows == nil ? frame.precedes : nil;
}

// The node of the session's pass before the frame, else after it. With no
// pass at the session in the window, the node its lease names, or the one
// node of the group of its model.
- (nullable QLMSetupNode *)nodeOf:(QLMSessionFrame *)frame {
    QLMSetupNode *after = nil;
    for (QLMPassMatch *match in _matches) {
        if (match.node != nil && match.pass == frame.follows) {
            return match.node;
        }
        if (match.node != nil && match.pass == frame.precedes) {
            after = match.node;
        }
    }
    if (after != nil) {
        return after;
    }
    NSMutableArray<QLMSetupNode *> *ofModel = [NSMutableArray array];
    for (QLMSetupNode *node in _group.nodes) {
        if (_blocks[node.serial] == nil) {
            continue;
        }
        if (frame.lease.hardwareID != nil && [node.hardwareID isEqualToData:frame.lease.hardwareID]) {
            return node;
        }
        if ([[_setup deviceWithSerial:node.serial].model isEqualToString:frame.model]) {
            [ofModel addObject:node];
        }
    }
    return ofModel.count == 1 ? ofModel.firstObject : nil;
}

- (QLMOutsideVerdict)verdictOf:(QLMSessionFrame *)frame label:(NSString **)label {
    NSData *payload = frame.payload;
    const uint8_t *bytes = payload.bytes;
    NSData *key = QLMSettingKey(payload);
    if (QLMIsRouting(payload)) {
        if (![_routing containsObject:frame]) {
            *label = @"routing, to a monitor with no pass right after it";
            return QLMOutsideExplained;
        }
        NSData *theirs = nil;
        for (NSData *sent in frame.precedes.payloads) {
            theirs = [QLMSettingKey(sent) isEqualToData:key] ? sent : theirs;
        }
        if ([theirs isEqualToData:payload]) {
            *label = @"as the pass after it sends it";
            return QLMOutsideExplained;
        }
        *label = theirs == nil ? @"a setting the pass after it lacks" : @"not as the pass after it sends it";
        return QLMOutsideUnexplained;
    }
    NSString *slot = QLMIsBand(payload) ? [NSString stringWithFormat:@"slot %02X, ", bytes[2]] : @"";
    QLMSetupNode *node = [self nodeOf:frame];
    NSData *mine = node != nil ? QLMBlockSetting(_blocks[node.serial], payload) : nil;
    if (bytes[0] != 0x10 && mine == nil) {
        *label = @"not a setting of the block";
        return QLMOutsideUnexplained;
    }
    if (_lasts[QLMSessionSetting(frame)] != frame) {
        *label = [slot stringByAppendingString:@"passed through"];
        return QLMOutsidePassedThrough;
    }
    if ([mine isEqualToData:payload]) {
        *label = [slot stringByAppendingString:@"as the block sends it"];
        return QLMOutsideExplained;
    }
    *label = [slot stringByAppendingString:node == nil ? @"no node to compare" : mine == nil ? @"a setting the block lacks"
                                                                                            : @"not as the block sends it"];
    return QLMOutsideUnexplained;
}

@end

// Prints each of `frames` that `listed` keeps, under `heading`, with what the
// reader makes of it, and counts each verdict.
static void QLMPrintOutside(FILE *out, const char *heading, NSArray<QLMSessionFrame *> *frames, BOOL (^listed)(QLMSessionFrame *),
                            QLMOutsideReader *reader, NSUInteger counts[3]) {
    BOOL any = NO;
    for (QLMSessionFrame *frame in frames) {
        if (!listed(frame)) {
            continue;
        }
        if (!any) {
            fprintf(out, "%s\n", heading);
            any = YES;
        }
        NSString *label = nil;
        counts[[reader verdictOf:frame label:&label]] += 1;
        fprintf(out, "  %10.3f s  %s\n  %14s%s\n", frame.time, label.UTF8String, "", QLMHexText(frame.payload).UTF8String);
    }
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
    NSArray<QLMSessionFrame *> *outside = nil;
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(capture, from, to, &outside);
    BOOL check = given[@"--check-outside"] != nil;
    if (passes.count == 0 && !(check && outside.count > 0)) {
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
    QLMOutsideReader *reader = [[QLMOutsideReader alloc] initWithFrames:outside matches:matches setup:setup group:group];
    NSUInteger counts[3] = {0};
    NSMutableOrderedSet<NSNumber *> *passless = [NSMutableOrderedSet orderedSet];
    for (QLMSessionFrame *frame in outside) {
        if (frame.follows == nil && frame.precedes == nil) {
            [passless addObject:@(frame.session)];
        }
    }
    for (NSNumber *session in passless) {
        NSString *heading = [NSString stringWithFormat:@"\nGLM, outside a pass, to session %02X, which has no pass in the window",
                                                       session.unsignedCharValue];
        QLMPrintOutside(out, heading.UTF8String, outside, ^BOOL(QLMSessionFrame *frame) {
            return frame.session == session.unsignedCharValue && frame.follows == nil && frame.precedes == nil;
        }, reader, counts);
    }
    fprintf(out, "\n");
    NSUInteger matched = 0;
    for (QLMPassMatch *match in matches) {
        QLMPrintMatch(out, match, setup);
        QLMPrintOutside(out, "  GLM, outside a pass, before it", outside, ^BOOL(QLMSessionFrame *frame) {
            return [reader passListedBefore:frame] == match.pass;
        }, reader, counts);
        QLMPrintOutside(out, "  GLM, outside a pass, after it", outside, ^BOOL(QLMSessionFrame *frame) {
            return frame.follows == match.pass && [reader passListedBefore:frame] == nil;
        }, reader, counts);
        matched += match.matches ? 1 : 0;
    }
    NSArray<QLMSessionFrame *> *stops = QLMGeneratorStopsInCapture(capture, from, to);
    NSUInteger oddStops = 0;
    for (QLMSessionFrame *stop in stops) {
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
    NSUInteger unexplained = counts[QLMOutsideUnexplained];
    if (outside.count > 0) {
        fprintf(out, "%lu DSP %s outside a pass: %lu explained, %lu passed through, and %lu not explained.%s\n",
                (unsigned long)outside.count, outside.count == 1 ? "frame" : "frames", (unsigned long)counts[QLMOutsideExplained],
                (unsigned long)counts[QLMOutsidePassedThrough], (unsigned long)unexplained,
                check || unexplained == 0 ? "" : " They count only with --check-outside.");
    }
    fprintf(out, "%lu of %lu %s match", (unsigned long)matched, (unsigned long)matches.count, matches.count == 1 ? "pass" : "passes");
    unexplained = check ? unexplained : 0;
    if (matched < matches.count || oddStops > 0 || unexplained > 0) {
        fprintf(out, ". %lu %s, %s%lu generator %s", (unsigned long)(matches.count - matched),
                matches.count - matched == 1 ? "differs" : "differ", check ? "" : "and ", (unsigned long)oddStops,
                oddStops == 1 ? "stop differs" : "stops differ");
        if (check) {
            fprintf(out, ", and %lu outside a pass %s", (unsigned long)unexplained, unexplained == 1 ? "isn't explained" : "aren't explained");
        }
        fprintf(out, ".\n");
        return QLMCompareApplyDiffers;
    }
    fprintf(out, ", apart from what qlm leaves out: the generator stop, and the 8351B's 43 00 02 and 4B 00 00 00 01.\n");
    return 0;
}
