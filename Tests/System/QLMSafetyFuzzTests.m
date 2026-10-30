#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMFakeBus.h"
#import "QLMReportLink.h"
#import "QLMSetupInternal.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCRC.h"
#include "QLMCommands.h"
#include "QLMReplies.h"
#include "QLMReport.h"

// Sources: AGENTS.md's Safety rules, and docs/protocol.md for how the bus,
// the adapter, and the monitors behave. Each run drives System through a few
// hundred random actions on a fake bus of the fixture's six monitors, on the
// virtual clock, and checks qlm's safety rules on every frame:
//
//   1. No volume frame is above the ceiling in force when it goes out.
//   2. Every frame is on GLMProtocol's allowlist, and none is 15, 05, 3A 01,
//      3A 02, or 3A 06.
//   3. Nothing goes out while another host holds the adapter.
//   4. No 2B unmutes a monitor the user muted, by hardware ID, unless the
//      user unmuted it. A 2B unmutes a monitor muted on the wire. To one the
//      user's mute has not reached yet, it only restates its state.
//   5. Once a volume is set, the first frame to reach a monitor after its
//      lease is the volume.
//   6. At most one request is in flight on the report link at a time.
//
// A report link sits between System and the bus, as in the HID adapter. The
// adapter answers in order, as fast as the captures show, and a reply comes
// late or is lost only when an action says so. A run is a pure function of
// its action list, and the list of its seed.
//
// The runs found three System bugs, which "The bugs the runs found" names.
// A violation one of them explains is marked known, and the tests expect
// it. Any other fails the test, and logs the seed and the list.
//
// To replay or soak, set these when running the tests:
//   TEST_RUNNER_QLM_FUZZ_SEED=<seed>, and TEST_RUNNER_QLM_FUZZ_ACTIONS=<n>.
//   TEST_RUNNER_QLM_FUZZ_SHRINK=1, to shrink a failing seed to a short list.
//   TEST_RUNNER_QLM_FUZZ_SOAK=<runs>, for that many seeds of 2,000 actions.
// For example: TEST_RUNNER_QLM_FUZZ_SOAK=50 make test
//   ARGS=-only-testing:QLMTests/QLMSafetyFuzzTests
@interface QLMSafetyFuzzTests : XCTestCase
@end

#pragma mark - Random

// SplitMix64, so a seed gives the same run on every host.
typedef struct {
    uint64_t state;
} QLMFuzzRandom;

static uint64_t QLMFuzzNext(QLMFuzzRandom *random) {
    uint64_t z = (random->state += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

static NSInteger QLMFuzzBelow(QLMFuzzRandom *random, NSInteger count) {
    return (NSInteger)(QLMFuzzNext(random) % (uint64_t)count);
}

static double QLMFuzzBetween(QLMFuzzRandom *random, double low, double high) {
    double unit = (double)(QLMFuzzNext(random) >> 11) / 9007199254740992.0;
    return low + (high - low) * unit;
}

static BOOL QLMFuzzChance(QLMFuzzRandom *random, double chance) {
    return QLMFuzzBetween(random, 0, 1) < chance;
}

#pragma mark - Actions

typedef NS_ENUM(NSInteger, QLMFuzzKind) {
    QLMFuzzAdvance,       // value: seconds
    QLMFuzzVolume,        // value: dB
    QLMFuzzCeiling,       // value: dB
    QLMFuzzDim,           // flag: on
    QLMFuzzMute,          // index: monitor; flag: muted
    QLMFuzzMuteAll,       // flag: muted
    QLMFuzzRecordMuted,   // index: monitor
    QLMFuzzKnobTurn,      // value: target, in tenths; count: tenths a poll
    QLMFuzzKnobDrift,     // count: steps; index: tenths a step; value: seconds a step
    QLMFuzzKnobJitter,    // count: readings; index: tenths at most
    QLMFuzzKnobOut,
    QLMFuzzKnobIn,        // value: tenths
    QLMFuzzSleep,
    QLMFuzzWake,
    QLMFuzzApply,         // index: group; flag: GLM's switch
    QLMFuzzStop,          // waits until System lets go
    QLMFuzzStart,
    QLMFuzzRestart,       // a stop and a start at once
    QLMFuzzRelaunch,      // a new System from the saved mute record; flag: sets a volume
    QLMFuzzDropOff,       // index: monitor
    QLMFuzzComeBack,      // index: monitor; flag: keeps its lease
    QLMFuzzStandby,       // index: monitor
    QLMFuzzSwitchOn,      // index: monitor
    QLMFuzzLapse,         // index: monitor, or -1 for all
    QLMFuzzMonitorDrops,  // index: monitor; count: replies
    QLMFuzzUnplug,
    QLMFuzzReplug,
    QLMFuzzHostTakes,     // flag: GLM, else another process
    QLMFuzzHostQuits,     // index: the reply it leaves behind, 0 for none
    QLMFuzzLateReplies,   // count: replies; value: seconds late
    QLMFuzzLostReplies,   // count: replies
};

@interface QLMFuzzAction : NSObject
@property (nonatomic) QLMFuzzKind kind;
@property (nonatomic) double value;
@property (nonatomic) NSInteger index;
@property (nonatomic) NSInteger count;
@property (nonatomic) BOOL flag;
@end

static QLMFuzzAction *QLMFuzzMake(QLMFuzzKind kind, double value, NSInteger index, NSInteger count, BOOL flag) {
    QLMFuzzAction *action = [[QLMFuzzAction alloc] init];
    action.kind = kind;
    action.value = value;
    action.index = index;
    action.count = count;
    action.flag = flag;
    return action;
}

static NSString *QLMFuzzOnOff(BOOL on) {
    return on ? @"on" : @"off";
}

@implementation QLMFuzzAction

- (NSString *)description {
    switch (self.kind) {
    case QLMFuzzAdvance: return [NSString stringWithFormat:@"advance %.4f s", self.value];
    case QLMFuzzVolume: return [NSString stringWithFormat:@"volume %g dB", self.value];
    case QLMFuzzCeiling: return [NSString stringWithFormat:@"ceiling %g dB", self.value];
    case QLMFuzzDim: return [NSString stringWithFormat:@"dim %@", QLMFuzzOnOff(self.flag)];
    case QLMFuzzMute: return [NSString stringWithFormat:@"mute monitor %ld %@", (long)self.index, QLMFuzzOnOff(self.flag)];
    case QLMFuzzMuteAll: return [NSString stringWithFormat:@"mute all %@", QLMFuzzOnOff(self.flag)];
    case QLMFuzzRecordMuted: return [NSString stringWithFormat:@"record monitor %ld muted elsewhere", (long)self.index];
    case QLMFuzzKnobTurn:
        return [NSString stringWithFormat:@"turn the knob to %.0f tenths, %ld a poll", self.value, (long)self.count];
    case QLMFuzzKnobDrift:
        return [NSString stringWithFormat:@"drift the knob %ld steps of %ld tenths, %.3f s apart", (long)self.count, (long)self.index, self.value];
    case QLMFuzzKnobJitter:
        return [NSString stringWithFormat:@"jitter the knob %ld readings, up to %ld tenths", (long)self.count, (long)self.index];
    case QLMFuzzKnobOut: return @"pull the knob out";
    case QLMFuzzKnobIn: return [NSString stringWithFormat:@"plug the knob in at %.0f tenths", self.value];
    case QLMFuzzSleep: return @"sleep";
    case QLMFuzzWake: return @"wake";
    case QLMFuzzApply: return [NSString stringWithFormat:@"%@ group %ld", self.flag ? @"switch to" : @"apply", (long)self.index];
    case QLMFuzzStop: return @"stop";
    case QLMFuzzStart: return @"start";
    case QLMFuzzRestart: return @"stop and start at once";
    case QLMFuzzRelaunch: return [NSString stringWithFormat:@"relaunch from the saved mute record%@", self.flag ? @", then set the volume" : @""];
    case QLMFuzzDropOff: return [NSString stringWithFormat:@"monitor %ld drops off the bus", (long)self.index];
    case QLMFuzzComeBack:
        return [NSString stringWithFormat:@"monitor %ld comes back%@", (long)self.index, self.flag ? @", lease held" : @", lease lost"];
    case QLMFuzzStandby: return [NSString stringWithFormat:@"monitor %ld goes to standby", (long)self.index];
    case QLMFuzzSwitchOn: return [NSString stringWithFormat:@"monitor %ld is switched on, with no lease", (long)self.index];
    case QLMFuzzLapse:
        return self.index < 0 ? @"every lease lapses" : [NSString stringWithFormat:@"monitor %ld's lease lapses", (long)self.index];
    case QLMFuzzMonitorDrops: return [NSString stringWithFormat:@"monitor %ld drops its next %ld replies", (long)self.index, (long)self.count];
    case QLMFuzzUnplug: return @"unplug the adapter";
    case QLMFuzzReplug: return @"plug the adapter back in";
    case QLMFuzzHostTakes: return self.flag ? @"GLM takes the adapter" : @"another process takes the adapter";
    case QLMFuzzHostQuits: return [NSString stringWithFormat:@"the other host quits, leaving reply %ld", (long)self.index];
    case QLMFuzzLateReplies: return [NSString stringWithFormat:@"the next %ld replies come %.3f s late", (long)self.count, self.value];
    case QLMFuzzLostReplies: return [NSString stringWithFormat:@"the next %ld replies to a monitor are lost", (long)self.count];
    }
    return @"?";
}

@end

// A step of 0.5 dB in [-100, 0].
static double QLMFuzzStep(QLMFuzzRandom *random) {
    return -0.5 * (double)QLMFuzzBelow(random, 201);
}

static double QLMFuzzVolumeValue(QLMFuzzRandom *random, double ceiling) {
    switch (QLMFuzzBelow(random, 12)) {
    case 0: return NAN;
    case 1: return QLMFuzzChance(random, 0.5) ? INFINITY : -INFINITY;
    case 2: return -0.0;
    case 3:
    case 4:
    case 5: return (isfinite(ceiling) ? ceiling : 0) + QLMFuzzBetween(random, 0.1, 30);
    case 6: return QLMFuzzBetween(random, -130, 12);
    default: return QLMFuzzStep(random);
    }
}

static double QLMFuzzCeilingValue(QLMFuzzRandom *random) {
    switch (QLMFuzzBelow(random, 24)) {
    case 0: return NAN;
    case 1: return QLMFuzzChance(random, 0.5) ? INFINITY : -INFINITY;
    case 2: return QLMFuzzChance(random, 0.5) ? 0.0 : -0.0;
    case 3: return 6;
    case 4: return QLMFuzzChance(random, 0.5) ? -100 : -120;
    case 5:
    case 6:
    case 7:
    case 8: return QLMFuzzBetween(random, -90, 0);
    default: return -0.5 * (double)QLMFuzzBelow(random, 161);
    }
}

typedef struct {
    QLMFuzzKind kind;
    NSInteger weight;
} QLMFuzzWeight;

// Twice the percent of actions of each kind.
static const QLMFuzzWeight QLMFuzzWeights[] = {
    {QLMFuzzAdvance, 46}, {QLMFuzzVolume, 14},     {QLMFuzzCeiling, 10},     {QLMFuzzDim, 8},          {QLMFuzzMute, 12},
    {QLMFuzzMuteAll, 6},  {QLMFuzzRecordMuted, 2}, {QLMFuzzKnobTurn, 7},     {QLMFuzzKnobDrift, 4},    {QLMFuzzKnobJitter, 4},
    {QLMFuzzKnobOut, 1},  {QLMFuzzSleep, 4},       {QLMFuzzWake, 6},         {QLMFuzzApply, 10},       {QLMFuzzStop, 4},
    {QLMFuzzRestart, 3},  {QLMFuzzRelaunch, 2},    {QLMFuzzDropOff, 4},      {QLMFuzzComeBack, 5},     {QLMFuzzStandby, 3},
    {QLMFuzzSwitchOn, 5}, {QLMFuzzLapse, 5},       {QLMFuzzMonitorDrops, 4}, {QLMFuzzUnplug, 2},       {QLMFuzzHostTakes, 2},
    {QLMFuzzLateReplies, 6}, {QLMFuzzLostReplies, 4},
};

static QLMFuzzKind QLMFuzzPickKind(QLMFuzzRandom *random) {
    NSInteger total = 0;
    for (size_t i = 0; i < sizeof QLMFuzzWeights / sizeof QLMFuzzWeights[0]; i++) {
        total += QLMFuzzWeights[i].weight;
    }
    NSInteger pick = QLMFuzzBelow(random, total);
    for (size_t i = 0; i < sizeof QLMFuzzWeights / sizeof QLMFuzzWeights[0]; i++) {
        pick -= QLMFuzzWeights[i].weight;
        if (pick < 0) {
            return QLMFuzzWeights[i].kind;
        }
    }
    return QLMFuzzAdvance;
}

static const NSInteger QLMFuzzMonitorCount = 6;
static const NSInteger QLMFuzzStrayKinds = 5;

// The action list for a seed. A rough state steers it: a stopped System
// soon starts, an unplugged adapter soon comes back, and another host soon
// quits. The run skips whatever does not apply when it comes.
static NSArray<QLMFuzzAction *> *QLMFuzzActionsForSeed(uint64_t seed, NSUInteger count, NSInteger groups) {
    QLMFuzzRandom random = {seed};
    NSMutableArray<QLMFuzzAction *> *actions = [NSMutableArray array];
    BOOL running = YES;
    BOOL plugged = YES;
    BOOL otherHost = NO;
    BOOL knobIn = YES;
    double ceiling = -20;
    if (QLMFuzzChance(&random, 0.9)) {
        [actions addObject:QLMFuzzMake(QLMFuzzVolume, QLMFuzzVolumeValue(&random, ceiling), 0, 0, NO)];
    }
    while (actions.count < count) {
        QLMFuzzKind kind = QLMFuzzPickKind(&random);
        if (!running && QLMFuzzChance(&random, 0.3)) {
            kind = QLMFuzzStart;
        } else if (!plugged && QLMFuzzChance(&random, 0.25)) {
            kind = QLMFuzzReplug;
        } else if (otherHost && QLMFuzzChance(&random, 0.25)) {
            kind = QLMFuzzHostQuits;
        } else if (!knobIn && (kind == QLMFuzzKnobTurn || kind == QLMFuzzKnobDrift || kind == QLMFuzzKnobJitter)) {
            kind = QLMFuzzKnobIn;
        }
        NSInteger monitor = QLMFuzzBelow(&random, QLMFuzzMonitorCount);
        QLMFuzzAction *action = QLMFuzzMake(kind, 0, monitor, 0, NO);
        switch (kind) {
        case QLMFuzzAdvance: {
            NSInteger size = QLMFuzzBelow(&random, 20);
            action.value = size < 10 ? QLMFuzzBetween(&random, 0.0005, 0.2) : size < 17 ? QLMFuzzBetween(&random, 0.2, 1.5)
                                                                                       : QLMFuzzBetween(&random, 1.5, 6);
            break;
        }
        case QLMFuzzVolume: action.value = QLMFuzzVolumeValue(&random, ceiling); break;
        case QLMFuzzCeiling:
            action.value = QLMFuzzCeilingValue(&random);
            ceiling = action.value;
            break;
        case QLMFuzzDim:
        case QLMFuzzMuteAll: action.flag = QLMFuzzChance(&random, 0.5); break;
        case QLMFuzzMute: action.flag = QLMFuzzChance(&random, 0.65); break;
        case QLMFuzzKnobTurn:
            action.value = -(double)QLMFuzzBelow(&random, 1005);
            action.count = 11 + QLMFuzzBelow(&random, 70);
            break;
        case QLMFuzzKnobDrift:
            action.count = 5 + QLMFuzzBelow(&random, 26);
            action.index = (1 + QLMFuzzBelow(&random, 4)) * (QLMFuzzChance(&random, 0.5) ? 1 : -1);
            action.value = QLMFuzzBetween(&random, 0.1, 0.6);
            break;
        case QLMFuzzKnobJitter:
            action.count = 5 + QLMFuzzBelow(&random, 26);
            action.index = 1 + QLMFuzzBelow(&random, 6);
            break;
        case QLMFuzzKnobIn: action.value = -(double)QLMFuzzBelow(&random, 1005); break;
        case QLMFuzzApply:
            action.index = QLMFuzzBelow(&random, groups);
            action.flag = QLMFuzzChance(&random, 0.3);
            break;
        case QLMFuzzRelaunch: action.flag = QLMFuzzChance(&random, 0.8); break;
        case QLMFuzzComeBack: action.flag = QLMFuzzChance(&random, 0.5); break;
        case QLMFuzzLapse: action.index = QLMFuzzChance(&random, 0.25) ? -1 : monitor; break;
        case QLMFuzzMonitorDrops: action.count = 1 + QLMFuzzBelow(&random, 6); break;
        case QLMFuzzHostTakes: action.flag = QLMFuzzChance(&random, 0.7); break;
        case QLMFuzzHostQuits: action.index = QLMFuzzBelow(&random, QLMFuzzStrayKinds); break;
        case QLMFuzzLateReplies:
            action.count = 1 + QLMFuzzBelow(&random, 4);
            action.value = QLMFuzzBetween(&random, 0.11, 0.9);
            break;
        case QLMFuzzLostReplies: action.count = 1 + QLMFuzzBelow(&random, 3); break;
        default: break;
        }
        switch (kind) {
        case QLMFuzzStop: running = NO; break;
        case QLMFuzzStart:
        case QLMFuzzRestart:
        case QLMFuzzRelaunch: running = YES; break;
        case QLMFuzzUnplug: plugged = NO; break;
        case QLMFuzzReplug: plugged = YES; break;
        case QLMFuzzHostTakes: otherHost = YES; break;
        case QLMFuzzHostQuits: otherHost = NO; break;
        case QLMFuzzKnobOut: knobIn = NO; break;
        case QLMFuzzKnobIn: knobIn = YES; break;
        default: break;
        }
        [actions addObject:action];
    }
    return actions;
}

#pragma mark - Violations

@interface QLMFuzzViolation : NSObject
@property (nonatomic) NSUInteger check;
@property (nonatomic) NSInteger action;  // -1 before the first, or as the run ends
@property (nonatomic) NSTimeInterval time;
@property (nonatomic, copy) NSString *text;
// The System bug it comes from, when it is one this file names.
@property (nonatomic, copy, nullable) NSString *known;
@end

@implementation QLMFuzzViolation

- (NSString *)description {
    NSString *known = self.known != nil ? [NSString stringWithFormat:@" [known: %@]", self.known] : @"";
    return [NSString stringWithFormat:@"check %lu, at action %ld, %.4f s: %@%@", (unsigned long)self.check, (long)self.action,
                                      self.time, self.text, known];
}

@end

static NSString *QLMFuzzHex(const QLMMessage *message) {
    NSMutableString *text = [NSMutableString stringWithFormat:@"%02X", message->address];
    for (size_t i = 0; i < message->length; i++) {
        [text appendFormat:@" %02X", message->payload[i]];
    }
    return text;
}

// Why the frame breaks rule 2, or nil.
static NSString *_Nullable QLMFuzzForbidden(const QLMMessage *message) {
    const uint8_t *payload = message->payload;
    if (message->length == 0) {
        return @"an empty payload";
    }
    if (payload[0] == 0x15) {
        return @"15, the flash commit";
    }
    if (payload[0] == 0x05) {
        return @"05, a test signal";
    }
    if (payload[0] == 0x3A && message->length >= 2 && (payload[1] == 0x01 || payload[1] == 0x02 || payload[1] == 0x06)) {
        return @"a standalone setting";
    }
    if (!QLMFrameAllows(payload, message->length)) {
        return @"off the allowlist";
    }
    uint8_t report[QLMReportLength];
    if (QLMReportPackOutput(message, report) != QLMReportOK) {
        return @"refused by the encoder";
    }
    return nil;
}

// The loudest word rule 1 allows under `ceiling`: the step at or below it,
// from hlm §4's 0 dB word, with one count to spare, since GLM's table and
// the formula differ by one count now and then (QLMCommands.c). The next
// step up is always more than one count louder. A ceiling that is no number
// allows only the bottom stop.
static uint32_t QLMFuzzCeilingWord(double ceiling) {
    if (isnan(ceiling)) {
        return QLMVolumeWordMin;
    }
    double step = ceil(-ceiling / QLMVolumeDecibelsStep);
    if (step <= 0) {
        return QLMVolumeWordMax;
    }
    if (step >= 200) {
        return QLMVolumeWordMin;
    }
    return (uint32_t)floor(pow(10.0, -step * QLMVolumeDecibelsStep / 20.0) * (double)QLMVolumeWordMax) + 1;
}

// System's rule for a send that reached the bus, reply or not.
static BOOL QLMFuzzWentOut(NSError *_Nullable error) {
    return error == nil || ([error.domain isEqualToString:QLMAdapterErrorDomain] &&
                            (error.code == QLMAdapterErrorTimeout || error.code == QLMAdapterErrorBadReply));
}

// The System bugs this file has found, by the violations they cause.
static NSString *const QLMFuzzKnownLateCompletion = @"a send from before a stop completes in the next run";
static NSString *const QLMFuzzKnownStaleVolume = @"a volume frame keeps the ceiling it was queued under";
static NSString *const QLMFuzzKnownStaleRound = @"a round of 2B keeps the mutes it was queued under";
// A frame waits in System's line a few seconds at most. So a violation
// that a looser ceiling, or the user's unmute, within this window explains
// is the bug's.
static const NSTimeInterval QLMFuzzStaleWindow = 10;
static NSString *const QLMFuzzCountVolume = @"volume frames";
static NSString *const QLMFuzzCountMutedRound = @"2B frames to a monitor the user muted";
static NSString *const QLMFuzzCountRefused = @"sends refused for another host";
static NSString *const QLMFuzzCountLease = @"leases followed by a frame";
static NSString *const QLMFuzzCountLate = @"late replies";
static NSString *const QLMFuzzCountLost = @"lost replies";
static NSString *const QLMFuzzKnownBugs = @"System bugs: a send from before a stop can complete in the next run, and a volume "
                                          @"frame and a round of 2B keep the ceiling and the mutes they were queued under";

// A reply as the adapter frames it: the CRC over the address and payload,
// then 7E and 7D escaped, then the flag (docs/protocol.md, Framing).
static NSData *QLMFuzzReplyFrame(const QLMMessage *reply) {
    uint8_t raw[1 + QLMPayloadMax];
    raw[0] = reply->address;
    memcpy(raw + 1, reply->payload, reply->length);
    uint16_t crc = QLMCRC16GSM(raw, 1 + reply->length);
    NSMutableData *frame = [NSMutableData dataWithBytes:raw length:1];
    uint8_t tail[2] = {(uint8_t)(crc >> 8), (uint8_t)crc};
    for (size_t i = 1; i < 1 + reply->length + 2; i++) {
        uint8_t byte = i < 1 + reply->length ? raw[i] : tail[i - 1 - reply->length];
        if (byte == QLMFrameFlag || byte == QLMFrameEscape) {
            uint8_t escaped[2] = {QLMFrameEscape, (uint8_t)(byte ^ QLMFrameEscapeXor)};
            [frame appendBytes:escaped length:2];
        } else {
            [frame appendBytes:&byte length:1];
        }
    }
    uint8_t flag = QLMFrameFlag;
    [frame appendBytes:&flag length:1];
    return frame;
}

// What another host may leave on the way when it lets go of the adapter
// (QLMReportLink.h): its last status poll's reply, likeliest, or another.
static NSData *_Nullable QLMFuzzStray(NSInteger kind) {
    QLMMessage reply;
    switch (kind) {
    case 1: {
        const uint8_t status[] = {0x09, 0x33, 0x30, 0x36, 0xDF, 0xFF, 0xFF, 0xFC, 0x14};
        reply = QLMMessageMake(QLMAddressReply, status, sizeof status);
        break;
    }
    case 2: {
        const char *text = "c-0;model-GLM Adapter;ver-1.4.0.6113;hw-0.0.202;build-2025.05.19.s  ";
        uint8_t payload[QLMPayloadMax] = {0x09};
        size_t length = strlen(text) + 1;
        memcpy(payload + 1, text, length);
        reply = QLMMessageMake(QLMAddressReply, payload, 1 + length);
        break;
    }
    case 3: {
        const uint8_t ack[] = {0x09};
        reply = QLMMessageMake(QLMAddressReply, ack, sizeof ack);
        break;
    }
    case 4: {
        const uint8_t telemetry[] = {0x09, 0x41, 0x26, 0x47, 0x01, 0x84, 0x02, 0xB0};
        reply = QLMMessageMake(QLMAddressReply, telemetry, sizeof telemetry);
        break;
    }
    default: return nil;
    }
    return QLMFuzzReplyFrame(&reply);
}

#pragma mark - The world

// The monitors' side: the fake bus, where the adapter is plugged, the
// faults on the wire, the user's state as the test set it, and each broken
// rule. Every action changes it from the main thread while the clock is
// settled, and System's queue reads it, so its locks only order the two.
@interface QLMFuzzWorld : NSObject
- (instancetype)initWithClock:(QLMVirtualClock *)clock;
@property (nonatomic, readonly) QLMVirtualClock *clock;
@property (nonatomic, readonly) QLMFakeBus *bus;
@property (atomic) NSInteger action;
@property (atomic) BOOL plugged;
@property (atomic) NSUInteger arrival;  // one more at each replug
// The user's.
@property (nonatomic) double ceiling;
// The loosest word any ceiling in force since `time` allows.
- (uint32_t)loosestCeilingWordSince:(NSTimeInterval)time;
@property (atomic) BOOL volumeSet;
- (void)setMuted:(BOOL)muted hardwareID:(NSData *)hardwareID;
- (void)setAllMuted:(BOOL)muted;
- (BOOL)userMuted:(NSData *)hardwareID;
// The user had the monitor unmuted at `time` or after. Each starts so.
- (BOOL)userUnmuted:(NSData *)hardwareID since:(NSTimeInterval)time;
// Each monitor's mute as the last 2B it took set it. A monitor keeps its
// mute until a host sends another (docs/protocol.md, Monitors keep their
// level and their mute).
- (BOOL)mutedOnTheWire:(NSData *)hardwareID;
- (void)setMutedOnTheWire:(BOOL)muted hardwareID:(NSData *)hardwareID;
// Faults on the wire, each for the next few replies.
- (void)delayReplies:(NSInteger)count by:(NSTimeInterval)seconds;
- (void)loseReplies:(NSInteger)count;
- (NSTimeInterval)takeDelay;  // 0 for none
- (BOOL)takeLoss;
- (void)violate:(NSUInteger)check text:(NSString *)text;
- (void)violate:(NSUInteger)check text:(NSString *)text known:(nullable NSString *)known;
@property (nonatomic, readonly) NSArray<QLMFuzzViolation *> *violations;
// How often each check met what it guards, so none passes for want of it.
- (void)count:(NSString *)what;
@property (nonatomic, readonly) NSCountedSet<NSString *> *counts;
@end

@implementation QLMFuzzWorld {
    NSMutableSet<NSData *> *_muted;
    NSMutableSet<NSData *> *_unmutedSinceAll;
    BOOL _mutingAll;
    NSMutableSet<NSData *> *_mutedOnTheWire;
    NSMutableDictionary<NSData *, NSNumber *> *_mutedSince;
    NSInteger _late;
    NSTimeInterval _lateBy;
    NSInteger _lost;
    NSMutableArray<QLMFuzzViolation *> *_violations;
    NSCountedSet<NSString *> *_counts;
    double _ceiling;
    NSMutableArray<NSArray<NSNumber *> *> *_ceilings;  // time, ceiling
}

- (instancetype)initWithClock:(QLMVirtualClock *)clock {
    self = [super init];
    if (self) {
        _clock = clock;
        _muted = [NSMutableSet set];
        _unmutedSinceAll = [NSMutableSet set];
        _mutedOnTheWire = [NSMutableSet set];
        _mutedSince = [NSMutableDictionary dictionary];
        _violations = [NSMutableArray array];
        _counts = [[NSCountedSet alloc] init];
        _plugged = YES;
        _ceiling = -20;
        _ceilings = [NSMutableArray arrayWithObject:@[@0, @(-20)]];
        _action = -1;
        // The fixture's six monitors: two 8351B, two 8330A, a 7370A, and a
        // 7350A (docs/protocol.md, The big picture). c- is the model's class.
        NSMutableArray<QLMFakeMonitor *> *monitors = [NSMutableArray array];
        for (QLMSetupDevice *device in QLMReadFixtureSetup().devices) {
            if (device.hardwareID == nil) {
                continue;
            }
            NSString *serial = [NSString stringWithFormat:@"%@P2%07lu", device.model, (unsigned long)monitors.count];
            NSString *info = [NSString stringWithFormat:@"c-%ld;model-%@;ver-1.14.7", (long)device.type, device.model];
            uint8_t deviceClass = device.type == 1 ? QLMTelemetryClassSubwoofer : QLMTelemetryClassTwoWay;
            [monitors addObject:[[QLMFakeMonitor alloc] initWithHardwareID:device.hardwareID serialNumber:serial
                                                                systemInfo:info deviceClass:deviceClass]];
        }
        NSAssert(monitors.count == (NSUInteger)QLMFuzzMonitorCount, @"the fixture has six monitors");
        _bus = [[QLMFakeBus alloc] initWithMonitors:monitors];
        _bus.recordsSentMessages = NO;
    }
    return self;
}

// The mutes as the user set them. Mute all mutes every monitor, one that
// appears later included, until the user unmutes it alone or all.
- (void)setMuted:(BOOL)muted hardwareID:(NSData *)hardwareID {
    [self changeMutes:^{
        if (muted) {
            [self->_muted addObject:hardwareID];
            [self->_unmutedSinceAll removeObject:hardwareID];
        } else {
            [self->_muted removeObject:hardwareID];
            [self->_unmutedSinceAll addObject:hardwareID];
        }
    }];
}

- (void)setAllMuted:(BOOL)muted {
    [self changeMutes:^{
        self->_mutingAll = muted;
        [self->_unmutedSinceAll removeAllObjects];
        if (!muted) {
            [self->_muted removeAllObjects];
        }
    }];
}

// Notes when the change mutes each monitor it mutes.
- (void)changeMutes:(dispatch_block_t)change {
    @synchronized(self) {
        NSMutableSet<NSData *> *unmuted = [NSMutableSet set];
        for (QLMFakeMonitor *monitor in _bus.monitors) {
            if (![self userMuted:monitor.hardwareID]) {
                [unmuted addObject:monitor.hardwareID];
            }
        }
        change();
        for (NSData *hardwareID in unmuted) {
            if ([self userMuted:hardwareID]) {
                _mutedSince[hardwareID] = @(_clock.now);
            }
        }
    }
}

- (BOOL)userUnmuted:(NSData *)hardwareID since:(NSTimeInterval)time {
    @synchronized(self) {
        NSNumber *since = _mutedSince[hardwareID];
        return ![self userMuted:hardwareID] || since == nil || since.doubleValue >= time;
    }
}

- (BOOL)userMuted:(NSData *)hardwareID {
    @synchronized(self) {
        return [_muted containsObject:hardwareID] || (_mutingAll && ![_unmutedSinceAll containsObject:hardwareID]);
    }
}

- (BOOL)mutedOnTheWire:(NSData *)hardwareID {
    @synchronized(self) {
        return [_mutedOnTheWire containsObject:hardwareID];
    }
}

- (void)setMutedOnTheWire:(BOOL)muted hardwareID:(NSData *)hardwareID {
    @synchronized(self) {
        if (muted) {
            [_mutedOnTheWire addObject:hardwareID];
        } else {
            [_mutedOnTheWire removeObject:hardwareID];
        }
    }
}

- (void)delayReplies:(NSInteger)count by:(NSTimeInterval)seconds {
    @synchronized(self) {
        _late = count;
        _lateBy = seconds;
    }
}

- (void)loseReplies:(NSInteger)count {
    @synchronized(self) {
        _lost = count;
    }
}

- (NSTimeInterval)takeDelay {
    @synchronized(self) {
        if (_late <= 0) {
            return 0;
        }
        _late -= 1;
        return _lateBy;
    }
}

- (BOOL)takeLoss {
    @synchronized(self) {
        if (_lost <= 0) {
            return NO;
        }
        _lost -= 1;
        return YES;
    }
}

- (double)ceiling {
    @synchronized(self) {
        return _ceiling;
    }
}

- (void)setCeiling:(double)ceiling {
    @synchronized(self) {
        _ceiling = ceiling;
        [_ceilings addObject:@[@(_clock.now), @(ceiling)]];
    }
}

- (uint32_t)loosestCeilingWordSince:(NSTimeInterval)time {
    @synchronized(self) {
        uint32_t loosest = QLMFuzzCeilingWord(_ceiling);
        double inForce = NAN;
        for (NSArray<NSNumber *> *change in _ceilings) {
            if (change[0].doubleValue <= time) {
                inForce = change[1].doubleValue;
            } else {
                loosest = MAX(loosest, QLMFuzzCeilingWord(change[1].doubleValue));
            }
        }
        return MAX(loosest, QLMFuzzCeilingWord(inForce));
    }
}

- (void)violate:(NSUInteger)check text:(NSString *)text {
    [self violate:check text:text known:nil];
}

- (void)violate:(NSUInteger)check text:(NSString *)text known:(NSString *)known {
    QLMFuzzViolation *violation = [[QLMFuzzViolation alloc] init];
    violation.check = check;
    violation.action = self.action;
    violation.time = _clock.now;
    violation.text = text;
    violation.known = known;
    @synchronized(self) {
        [_violations addObject:violation];
    }
}

- (NSArray<QLMFuzzViolation *> *)violations {
    @synchronized(self) {
        return [_violations copy];
    }
}

- (void)count:(NSString *)what {
    @synchronized(self) {
        [_counts addObject:what];
    }
}

- (NSCountedSet<NSString *> *)counts {
    @synchronized(self) {
        return [_counts copy];
    }
}

@end

#pragma mark - The adapter

// What System drives: the GLM adapter as QLMHIDAdapter drives it, through a
// report link, over a wire to the fake bus. It opens only while plugged in
// and free of another host, keeps one link for each arrival, and closes at
// once when the adapter goes or another host takes it. Every reply comes
// from 01, in order, and every probe or unicast no monitor answers gets the
// adapter's 01 7E. It checks every frame System hands over, and every frame
// the link writes. Every method runs on System's queue, the bus's too.
@interface QLMFuzzAdapter : NSObject <QLMAdapter>
- (instancetype)initWithWorld:(QLMFuzzWorld *)world;
// The adapter was plugged in or out, or another host came or went.
- (void)hostChanged;
// A reply the last host left on the way, delivered just after the next write.
@property (nonatomic, nullable) NSData *stray;
@end

@implementation QLMFuzzAdapter {
    QLMFuzzWorld *_world;
    dispatch_queue_t _queue;
    id<QLMClock> _clock;
    BOOL _running;
    BOOL _open;
    QLMReportLink *_link;
    NSUInteger _linkArrival;
    // Ends the replies on the way, which an unplug or another host takes.
    NSUInteger _epoch;
    NSTimeInterval _lastDue;
    // Rule 6: System's send whose handler has not run, and the link's last
    // write that waits for a reply.
    NSUInteger _starts;
    BOOL _lateCompletion;  // a handler from before the last start is running
    // A late completion ended the send in flight, so each completion after
    // it ends the send after its own.
    BOOL _outOfStep;
    NSUInteger _sends;
    NSUInteger _inFlight;  // 0 for none
    NSString *_inFlightText;
    NSUInteger _closes;
    BOOL _waiting;  // for any reply
    NSTimeInterval _waitingSince;
    NSUInteger _waitingCloses;
    NSString *_waitingText;
    // Rule 5: sessions just leased, whose next frame must be the volume.
    NSMutableSet<NSNumber *> *_awaitingVolume;
}

- (instancetype)initWithWorld:(QLMFuzzWorld *)world {
    self = [super init];
    if (self) {
        _world = world;
        _awaitingVolume = [NSMutableSet set];
    }
    return self;
}

- (NSString *)deviceDescription {
    return @"the fuzz's fake bus, through a report link";
}

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    _queue = queue;
    _clock = clock;
    _running = YES;
    _starts += 1;
    [_world.bus startOnQueue:queue clock:clock];
    [self openIfFree];
}

- (void)stop {
    _running = NO;
    [_awaitingVolume removeAllObjects];
    [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The adapter is stopped.")];
}

- (void)openIfFree {
    QLMFuzzWorld *world = _world;
    if (!_running || _open || !world.plugged || world.bus.busyReason != nil) {
        return;
    }
    if (_link == nil || _linkArrival != world.arrival) {
        __weak QLMFuzzAdapter *weakSelf = self;
        _link = [[QLMReportLink alloc] initWithQueue:_queue clock:_clock writer:^NSError *(const uint8_t *report) {
            QLMFuzzAdapter *strongSelf = weakSelf;
            return strongSelf != nil ? [strongSelf write:report] : QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"gone");
        }];
        _linkArrival = world.arrival;
    } else if (_link.failure != nil) {
        return;
    } else {
        [_link reopen];
    }
    _open = YES;
}

// The link fails what it holds, and the handler that tells System so is
// the link's last word on it.
- (void)closeWithError:(NSError *)error {
    if (!_open) {
        return;
    }
    _open = NO;
    _closes += 1;
    _inFlight = 0;
    [_link closeWithError:error];
}

- (void)hostChanged {
    QLMFuzzWorld *world = _world;
    NSString *host = world.bus.busyReason;
    if (!world.plugged || host != nil) {
        NSError *error = !world.plugged ? QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The GLM adapter was unplugged.")
                                        : QLMAdapterErrorMake(QLMAdapterErrorBusy, host);
        [self closeWithError:error];
        _epoch += 1;
        _lastDue = 0;
        return;
    }
    [self openIfFree];
}

- (NSError *)problem {
    QLMFuzzWorld *world = _world;
    NSString *host = world.bus.busyReason;
    if (!_running) {
        return QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The adapter is stopped.");
    }
    if (!world.plugged) {
        return QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is connected.");
    }
    if (host != nil) {
        return QLMAdapterErrorMake(QLMAdapterErrorBusy, host);
    }
    return _link.failure ?: QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is open.");
}

#pragma mark System's side

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    QLMFuzzWorld *world = _world;
    NSString *text = QLMFuzzHex(&message);
    NSString *forbidden = QLMFuzzForbidden(&message);
    if (forbidden != nil) {
        [world violate:2 text:[NSString stringWithFormat:@"System handed over %@: %@", text, forbidden]];
    }
    [self checkVolumeFirst:&message text:text];
    if (_inFlight != 0) {
        NSString *problem = [NSString stringWithFormat:@"System handed over %@ while %@ was in flight", text, _inFlightText];
        BOOL late = _lateCompletion || _outOfStep;
        _outOfStep = late;
        [world violate:6 text:problem known:late ? QLMFuzzKnownLateCompletion : nil];
        // As QLMReportLink does in a build without assertions. Each refusal
        // ends System's send, so the next comes at once: the same bug.
        [_clock async:_queue run:^{
            self->_lateCompletion = late;
            handler(NULL, QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"A request was already in flight."));
            self->_lateCompletion = NO;
        }];
        return;
    }
    NSUInteger token = ++_sends;
    NSUInteger start = _starts;
    _inFlight = token;
    _inFlightText = text;
    QLMAdapterReplyHandler wrapped = ^(const QLMMessage *reply, NSError *error) {
        if (self->_inFlight == token) {
            self->_inFlight = 0;
        } else if (self->_inFlight != 0 && start != self->_starts) {
            self->_outOfStep = YES;
        }
        [self noteReply:reply error:error to:message];
        self->_lateCompletion = start != self->_starts;
        handler(reply, error);
        self->_lateCompletion = NO;
    };
    [self openIfFree];
    if (_open) {
        [_link sendMessage:message replyHandler:wrapped];
        return;
    }
    // As QLMHIDAdapter: through the allowlist even so.
    uint8_t report[QLMReportLength];
    NSError *error = nil;
    if (QLMAdapterPackReport(&message, report, &error)) {
        error = [self problem];
        if (error.code == QLMAdapterErrorBusy) {
            [world count:QLMFuzzCountRefused];
        }
    }
    [_clock async:_queue run:^{
        wrapped(NULL, error);
    }];
}

// Rule 5. System tracks a lease that was acked, and one whose ack was lost
// on the way, since the monitor may hold it.
- (void)noteReply:(const QLMMessage *)reply error:(NSError *)error to:(QLMMessage)message {
    if (message.address != QLMAddressMulticast || message.length != 5 || message.payload[0] != 0x02) {
        return;
    }
    if (!_running || !_world.volumeSet) {
        return;
    }
    uint8_t session = message.payload[4];
    uint8_t acked = 0;
    BOOL ack = reply != NULL && QLMReplySessionAck(reply, &acked) && acked == session;
    if (ack || (reply == NULL && QLMFuzzWentOut(error))) {
        [_awaitingVolume addObject:@(session)];
    }
}

- (void)checkVolumeFirst:(const QLMMessage *)message text:(NSString *)text {
    if (_awaitingVolume.count == 0) {
        return;
    }
    uint8_t address = message->address;
    BOOL volume = address == QLMAddressBroadcast && message->payload[0] == 0x1F;
    for (NSNumber *session in [_awaitingVolume copy]) {
        if (address != QLMAddressBroadcast && address != QLMAddressMulticast && address != session.unsignedCharValue) {
            continue;
        }
        [_awaitingVolume removeObject:session];
        [_world count:QLMFuzzCountLease];
        if (!volume) {
            NSString *problem = [NSString stringWithFormat:@"the first frame to session %02X after its lease was %@, not the volume",
                                                           session.unsignedCharValue, text];
            [_world violate:5 text:problem];
        }
    }
}

#pragma mark The wire

- (NSError *)write:(const uint8_t *)report {
    QLMFuzzWorld *world = _world;
    const uint8_t *frame = NULL;
    size_t frameLength = 0;
    QLMMessage message;
    if (QLMReportUnpackOutput(report, QLMReportLength, &frame, &frameLength) != QLMReportOK ||
        QLMFrameDecode(frame, frameLength, &message) != QLMFrameOK) {
        [world violate:2 text:@"the link wrote a report that does not decode"];
        return QLMAdapterErrorMake(QLMAdapterErrorBadReply, @"undecodable");
    }
    [self checkWritten:&message];
    if (!_open) {
        [world violate:6 text:[NSString stringWithFormat:@"the link wrote %@ while closed", QLMFuzzHex(&message)]];
        return QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"closed");
    }

    BOOL awaits = QLMReportExpectsReply(&message);
    if (awaits) {
        _waiting = YES;
        _waitingSince = _clock.now;
        _waitingCloses = _closes;
        _waitingText = QLMFuzzHex(&message);
    }
    NSUInteger epoch = _epoch;
    if (self.stray != nil) {
        [self deliver:self.stray after:0.0005 epoch:epoch];
        self.stray = nil;
    }
    // A monitor that wakes from standby loses its lease
    // (docs/protocol.md, When a monitor loses its lease). The bus keeps it.
    NSMutableArray<QLMFakeMonitor *> *asleep = [NSMutableArray array];
    const uint8_t *payload = message.payload;
    if (message.address == QLMAddressBroadcast && message.length == 3 && payload[0] == 0x3A && payload[1] == 0x03 &&
        (payload[2] == QLMPowerStepWakeFirst || payload[2] == QLMPowerStepWakeSecond)) {
        for (QLMFakeMonitor *monitor in world.bus.monitors) {
            if (monitor.present && !monitor.on) {
                [asleep addObject:monitor];
            }
        }
    }
    BOOL toAdapter = message.address == QLMAddressAdapter;
    [world.bus sendMessage:message replyHandler:^(const QLMMessage *reply, NSError *error) {
        for (QLMFakeMonitor *monitor in asleep) {
            if (monitor.on) {
                monitor.session = 0;
            }
        }
        if (awaits) {
            [self answer:reply epoch:epoch toAdapter:toAdapter];
        }
    }];
    return nil;
}

// Rules 1 to 4, and the link's half of 6, on a frame as it goes out.
- (void)checkWritten:(const QLMMessage *)message {
    QLMFuzzWorld *world = _world;
    NSString *text = QLMFuzzHex(message);
    const uint8_t *payload = message->payload;
    if (world.bus.busyReason != nil) {
        [world violate:3 text:[NSString stringWithFormat:@"%@ went out while another host held the adapter", text]];
    }
    NSString *forbidden = QLMFuzzForbidden(message);
    if (forbidden != nil) {
        [world violate:2 text:[NSString stringWithFormat:@"%@ went out: %@", text, forbidden]];
    }
    if (message->address == QLMAddressBroadcast && message->length == 4 && payload[0] == 0x1F) {
        uint32_t word = (uint32_t)payload[1] << 16 | (uint32_t)payload[2] << 8 | payload[3];
        double ceiling = world.ceiling;
        [world count:QLMFuzzCountVolume];
        if (word > QLMFuzzCeilingWord(ceiling)) {
            NSString *problem = [NSString stringWithFormat:@"%@, %.2f dB, went out above the ceiling of %g dB", text,
                                                           QLMVolumeDecibelsForWord(word), ceiling];
            // No frame waits in System's line for more than a few seconds.
            BOOL stale = word <= [world loosestCeilingWordSince:_clock.now - QLMFuzzStaleWindow];
            [world violate:1 text:problem known:stale ? QLMFuzzKnownStaleVolume : nil];
        }
    }
    uint8_t address = message->address;
    BOOL session = address != QLMAddressAdapter && address != QLMAddressBroadcast && address != QLMAddressMulticast;
    if (session && message->length >= 2 && payload[0] == 0x2B) {
        // On the real bus, every monitor holding the session takes it. A
        // 2B whose bit 0 is clear unmutes only a monitor muted now: to one
        // the user's mute has not reached yet, it restates its state.
        BOOL unmutes = (payload[1] & 0x01) == 0;
        for (QLMFakeMonitor *monitor in world.bus.monitors) {
            if (!monitor.present || monitor.session != address) {
                continue;
            }
            NSData *hardwareID = monitor.hardwareID;
            if ([world userMuted:hardwareID]) {
                [world count:QLMFuzzCountMutedRound];
            }
            if (unmutes && [world mutedOnTheWire:hardwareID] && [world userMuted:hardwareID]) {
                NSString *problem = [NSString stringWithFormat:@"%@ unmuted %@, which the user muted", text, hardwareID];
                BOOL stale = [world userUnmuted:hardwareID since:_clock.now - QLMFuzzStaleWindow];
                [world violate:4 text:problem known:stale ? QLMFuzzKnownStaleRound : nil];
            }
            [world setMutedOnTheWire:!unmutes hardwareID:monitor.hardwareID];
        }
    }
    // A reply names no request, so the link takes the next reply as its
    // request's, and a sync drops one that is late (QLMReportLink.h). Its
    // next write waits for a reply, a close, or the timeout. The smaller
    // timeout bounds a sync's own, which is five times as long.
    NSTimeInterval now = _clock.now;
    if (_waiting && _waitingCloses == _closes && now < _waitingSince + 0.1 - 1e-9) {
        NSString *problem = [NSString stringWithFormat:@"the link wrote %@ %.4f s after %@, and no reply came between", text,
                                                       now - _waitingSince, _waitingText];
        [world violate:6 text:problem];
    }
    _waiting = NO;
}

// Each reply comes in order, about as fast as the captures show: a
// monitor's in 1.6 ms, and the adapter's 01 7E in 8.6 ms
// (docs/protocol.md, Timing), unless a fault says otherwise.
- (void)answer:(const QLMMessage *_Nullable)reply epoch:(NSUInteger)epoch toAdapter:(BOOL)toAdapter {
    QLMFuzzWorld *world = _world;
    // Only a reply to a monitor is lost. The adapter answers its own polls
    // always, so a sync is never left waiting for good.
    if (!toAdapter && [world takeLoss]) {
        [world count:QLMFuzzCountLost];
        return;
    }
    NSTimeInterval delay = reply != NULL ? 0.0016 : 0.0086;
    NSTimeInterval late = [world takeDelay];
    if (late > 0) {
        delay = late;
        [world count:QLMFuzzCountLate];
    }
    const uint8_t noAnswerPayload[] = {QLMFrameFlag};
    QLMMessage noAnswer = QLMMessageMake(QLMAddressReply, noAnswerPayload, sizeof noAnswerPayload);
    [self deliver:QLMFuzzReplyFrame(reply != NULL ? reply : &noAnswer) after:delay epoch:epoch];
}

- (void)deliver:(NSData *)frame after:(NSTimeInterval)delay epoch:(NSUInteger)epoch {
    NSTimeInterval now = _clock.now;
    NSTimeInterval due = MAX(now + delay, _lastDue);
    _lastDue = due;
    __weak QLMReportLink *weakLink = _link;
    NSArray<NSData *> *inputs = [QLMCaptureDevice inputReportsForFrame:frame];
    __weak QLMFuzzAdapter *weakSelf = self;
    [_clock after:due - now queue:_queue run:^{
        QLMFuzzAdapter *strongSelf = weakSelf;
        QLMReportLink *link = weakLink;
        if (strongSelf == nil || link == nil || strongSelf->_epoch != epoch || strongSelf->_link != link) {
            return;
        }
        strongSelf->_waiting = NO;
        for (NSData *input in inputs) {
            [link receiveReport:input.bytes length:input.length];
        }
    }];
}

@end

#pragma mark - A run

// A violation's kind: the known bug it comes from, or its check.
static NSString *QLMFuzzKindOf(QLMFuzzViolation *violation) {
    return violation.known ?: [NSString stringWithFormat:@"check %lu", (unsigned long)violation.check];
}

static QLMFuzzViolation *_Nullable QLMFuzzFirstOfKind(NSArray<QLMFuzzViolation *> *violations, NSString *kind) {
    for (QLMFuzzViolation *violation in violations) {
        if ([QLMFuzzKindOf(violation) isEqualToString:kind]) {
            return violation;
        }
    }
    return nil;
}

// The groups an apply picks from: the fixture's, which the 8351B's
// unverified rate refuses, and each of them less its 8351B.
static NSArray<QLMSetupGroup *> *QLMFuzzGroups(void) {
    NSMutableArray<QLMSetupGroup *> *groups = [NSMutableArray array];
    NSArray<QLMSetupGroup *> *fixture = QLMReadFixtureSetup().groups;
    [groups addObjectsFromArray:fixture];
    NSPredicate *verified = [NSPredicate predicateWithBlock:^BOOL(QLMSetupNode *node, NSDictionary *bindings) {
        return node.nodeClass != QLMSetupNodeClassThreeWay;
    }];
    for (QLMSetupGroup *source in fixture) {
        QLMSetupGroup *group = [[QLMSetupGroup alloc] init];
        group.name = [source.name stringByAppendingString:@" less the 8351B"];
        group.groupSensitivity = source.groupSensitivity;
        group.crossover = source.crossover;
        group.crossoverGlobalMode = source.crossoverGlobalMode;
        group.videoDelay = source.videoDelay;
        group.subwooferBypass = source.subwooferBypass;
        group.lowShelf = source.lowShelf;
        group.highShelf = source.highShelf;
        group.nodes = [source.nodes filteredArrayUsingPredicate:verified];
        group.nodesInDeviceOrder = [source.nodesInDeviceOrder filteredArrayUsingPredicate:verified];
        [groups addObject:group];
    }
    return groups;
}

@interface QLMFuzzRun : NSObject
- (instancetype)initWithActions:(NSArray<QLMFuzzAction *> *)actions;
// Runs the actions, then stops System. With `kind`, ends at its first
// violation.
- (void)runStoppingAt:(nullable NSString *)kind;
@property (nonatomic, readonly) QLMFuzzWorld *world;
@property (nonatomic, readonly) NSUInteger applied;
@property (nonatomic, readonly) NSUInteger refused;
@end

@implementation QLMFuzzRun {
    NSArray<QLMFuzzAction *> *_actions;
    NSArray<QLMSetupGroup *> *_groups;
    QLMVirtualClock *_clock;
    QLMFuzzAdapter *_adapter;
    QLMSystem *_system;
    BOOL _running;
    BOOL _dimmed;
    double _volume;
    NSNumber *_knob;  // tenths, nil while out
}

- (instancetype)initWithActions:(NSArray<QLMFuzzAction *> *)actions {
    self = [super init];
    if (self) {
        _actions = [actions copy];
        _groups = QLMFuzzGroups();
        _clock = [[QLMVirtualClock alloc] init];
        _world = [[QLMFuzzWorld alloc] initWithClock:_clock];
        _volume = -30;
        _knob = @(-1004);
    }
    return self;
}

// As the app starts one: the saved mute record, the ceiling, dim, then the
// start.
- (void)launchWithMuted:(NSSet<NSData *> *)muted mutingAll:(BOOL)mutingAll {
    _adapter = [[QLMFuzzAdapter alloc] initWithWorld:_world];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = _clock;
    settings.ceilingDecibels = _world.ceiling;
    settings.mutedHardwareIDs = muted;
    settings.mutingAll = mutingAll;
    _system = [[QLMSystem alloc] initWithAdapter:_adapter settings:settings];
    if (_dimmed) {
        [_system setDimmed:YES];
    }
    [_system start];
    _running = YES;
}

- (void)runStoppingAt:(NSString *)kind {
    [self launchWithMuted:[NSSet set] mutingAll:NO];
    [_clock settle];
    for (NSUInteger i = 0; i < _actions.count; i++) {
        if (kind != nil && QLMFuzzFirstOfKind(_world.violations, kind) != nil) {
            return;
        }
        _world.action = (NSInteger)i;
        [self perform:_actions[i]];
        [_clock settle];
    }
    if (kind == nil || QLMFuzzFirstOfKind(_world.violations, kind) == nil) {
        [self stopAndWait];
        [_clock advanceBy:1];
    }
}

// A stop that never lets go is no safety rule, but the run reports it as
// check 0.
- (void)stopAndWait {
    __block BOOL stopped = NO;
    [_system stopWithCompletion:^{
        stopped = YES;
    }];
    BOOL done = [_clock runUntil:^BOOL {
        return stopped;
    } within:30];
    if (!done) {
        [_world violate:0 text:@"System did not let go of the adapter within 30 s of a stop"];
    }
    _running = NO;
}

- (QLMFakeMonitor *)monitor:(NSInteger)index {
    return _world.bus.monitors[(NSUInteger)index];
}

// On System's queue, which is the bus's.
- (void)onBus:(dispatch_block_t)block {
    [_world.bus perform:block];
}

- (void)setKnob:(nullable NSNumber *)tenths {
    _knob = tenths;
    QLMFakeBus *bus = _world.bus;
    [self onBus:^{
        bus.knobTenths = tenths;
    }];
}

// Moves the knob to `tenths`, then lets the adapter's next poll pair read it.
- (void)knobTo:(NSInteger)tenths wait:(NSTimeInterval)seconds {
    [self setKnob:@(MAX(-1004, MIN(0, tenths)))];
    [_clock advanceBy:seconds];
}

- (void)tellAdapter {
    QLMFuzzAdapter *adapter = _adapter;
    [self onBus:^{
        [adapter hostChanged];
    }];
}

- (void)perform:(QLMFuzzAction *)action {
    QLMFuzzWorld *world = _world;
    QLMFakeBus *bus = world.bus;
    QLMFakeMonitor *monitor = [self monitor:MAX(0, action.index) % QLMFuzzMonitorCount];
    switch (action.kind) {
    case QLMFuzzAdvance: [_clock advanceBy:action.value]; break;
    case QLMFuzzVolume:
        _volume = action.value;
        world.volumeSet = YES;
        [_system setVolumeDecibels:action.value];
        break;
    case QLMFuzzCeiling:
        world.ceiling = action.value;
        [_system setCeilingDecibels:action.value];
        break;
    case QLMFuzzDim:
        _dimmed = action.flag;
        [_system setDimmed:action.flag];
        break;
    case QLMFuzzMute:
        // System takes a mute only while it runs.
        if (_running) {
            [world setMuted:action.flag hardwareID:monitor.hardwareID];
            [_system setMuted:action.flag forMonitorWithHardwareID:monitor.hardwareID];
        }
        break;
    case QLMFuzzMuteAll:
        if (_running) {
            [world setAllMuted:action.flag];
            [_system setAllMuted:action.flag];
        }
        break;
    case QLMFuzzRecordMuted:
        [world setMuted:YES hardwareID:monitor.hardwareID];
        [_system recordMutedHardwareIDs:[NSSet setWithObject:monitor.hardwareID]];
        break;
    case QLMFuzzKnobTurn: {
        if (_knob == nil) {
            break;
        }
        NSInteger position = _knob.integerValue;
        NSInteger target = (NSInteger)action.value;
        NSInteger step = MAX(1, action.count);
        while (position != target) {
            position = position < target ? MIN(target, position + step) : MAX(target, position - step);
            [self knobTo:position wait:0.107];
        }
        break;
    }
    case QLMFuzzKnobDrift:
        for (NSInteger i = 0; i < action.count && _knob != nil; i++) {
            [self knobTo:_knob.integerValue + action.index wait:action.value];
        }
        break;
    case QLMFuzzKnobJitter: {
        if (_knob == nil) {
            break;
        }
        NSInteger rest = _knob.integerValue;
        for (NSInteger i = 0; i < action.count; i++) {
            [self knobTo:rest + action.index * ((i * 7) % 3 - 1) wait:0.107];
        }
        break;
    }
    case QLMFuzzKnobOut: [self setKnob:nil]; break;
    case QLMFuzzKnobIn: [self setKnob:@(action.value)]; break;
    case QLMFuzzSleep: [_system sleep]; break;
    case QLMFuzzWake: [_system wake]; break;
    case QLMFuzzApply: {
        QLMSetupGroup *group = _groups[(NSUInteger)action.index % _groups.count];
        __weak QLMFuzzRun *weakSelf = self;
        void (^done)(NSError *) = ^(NSError *error) {
            QLMFuzzRun *strongSelf = weakSelf;
            if (strongSelf != nil && error == nil) {
                strongSelf->_applied += 1;
            } else if (strongSelf != nil) {
                strongSelf->_refused += 1;
            }
        };
        if (action.flag) {
            [_system switchToGroup:group completion:done];
        } else {
            [_system applyGroup:group completion:done];
        }
        break;
    }
    case QLMFuzzStop:
        if (_running) {
            [self stopAndWait];
        }
        break;
    case QLMFuzzStart:
        [_system start];
        _running = YES;
        break;
    case QLMFuzzRestart:
        [_system stop];
        [_system start];
        _running = YES;
        break;
    case QLMFuzzRelaunch: {
        if (_running) {
            [self stopAndWait];
        }
        // The app keeps the record System last gave. The monitors drop the
        // old run's leases as the user waits between hosts
        // (docs/protocol.md, When the host goes quiet).
        QLMSnapshot *last = _system.snapshot;
        [_clock advanceBy:30];
        [self onBus:^{
            for (QLMFakeMonitor *each in bus.monitors) {
                each.session = 0;
            }
        }];
        world.volumeSet = NO;
        [self launchWithMuted:last.mutedHardwareIDs mutingAll:last.mutingAll];
        if (action.flag) {
            world.volumeSet = YES;
            [_system setVolumeDecibels:_volume];
        }
        break;
    }
    case QLMFuzzDropOff: {
        [self onBus:^{
            monitor.present = NO;
        }];
        break;
    }
    case QLMFuzzComeBack: {
        BOOL keepsLease = action.flag;
        [self onBus:^{
            monitor.present = YES;
            if (!keepsLease) {
                monitor.session = 0;
            }
        }];
        break;
    }
    case QLMFuzzStandby: {
        [self onBus:^{
            monitor.on = NO;
        }];
        break;
    }
    case QLMFuzzSwitchOn: {
        [self onBus:^{
            monitor.present = YES;
            monitor.on = YES;
            monitor.session = 0;
        }];
        break;
    }
    case QLMFuzzLapse: {
        NSInteger index = action.index;
        [self onBus:^{
            for (QLMFakeMonitor *each in bus.monitors) {
                if (index < 0 || each == monitor) {
                    each.session = 0;
                }
            }
        }];
        break;
    }
    case QLMFuzzMonitorDrops: {
        NSUInteger count = (NSUInteger)action.count;
        [self onBus:^{
            monitor.dropReplies = count;
        }];
        break;
    }
    case QLMFuzzUnplug:
        world.plugged = NO;
        [self tellAdapter];
        break;
    case QLMFuzzReplug:
        if (!world.plugged) {
            world.arrival += 1;
            world.plugged = YES;
            [self tellAdapter];
        }
        break;
    case QLMFuzzHostTakes: {
        NSString *host = action.flag ? @"GLM is running (pid 4242). Quit GLM first." : @"Another process has seized the GLM adapter.";
        QLMFuzzAdapter *adapter = _adapter;
        [self onBus:^{
            bus.busyReason = host;
            [adapter hostChanged];
        }];
        break;
    }
    case QLMFuzzHostQuits: {
        if (bus.busyReason == nil) {
            break;
        }
        // The other host leased the monitors meanwhile, and the user waits
        // for those leases to lapse, as between any two hosts.
        QLMFuzzAdapter *adapter = _adapter;
        NSData *stray = QLMFuzzStray(action.index);
        [self onBus:^{
            bus.busyReason = nil;
            for (QLMFakeMonitor *each in bus.monitors) {
                each.session = 0;
            }
            adapter.stray = stray;
            [adapter hostChanged];
        }];
        break;
    }
    case QLMFuzzLateReplies: [world delayReplies:action.count by:action.value]; break;
    case QLMFuzzLostReplies: [world loseReplies:action.count]; break;
    }
}

@end

#pragma mark - The tests

// Fixed seeds, so every run of the tests is the same.
static const uint64_t QLMFuzzSeeds[] = {0x51A7E0001, 0x51A7E0002, 0x51A7E0003, 0x51A7E0004, 0x51A7E0005};
static const NSUInteger QLMFuzzActionCount = 300;
// Each hits only its bug.
static const uint64_t QLMFuzzLateCompletionSeed = 0x207B;
static const uint64_t QLMFuzzStaleVolumeSeed = 0x204E;
static const uint64_t QLMFuzzStaleRoundSeed = 0x2095;

static NSString *_Nullable QLMFuzzEnvironment(NSString *name) {
    NSString *value = NSProcessInfo.processInfo.environment[name];
    return value.length > 0 ? value : nil;
}

static uint64_t QLMFuzzParseSeed(NSString *text) {
    return strtoull(text.UTF8String, NULL, 0);
}

@implementation QLMSafetyFuzzTests

// The list, numbered, through the action `last`.
static NSString *QLMFuzzListing(NSArray<QLMFuzzAction *> *actions, NSInteger last) {
    NSMutableString *listing = [NSMutableString string];
    for (NSInteger i = 0; i <= last && i < (NSInteger)actions.count; i++) {
        [listing appendFormat:@"  %3ld  %@\n", (long)i, actions[(NSUInteger)i]];
    }
    return listing;
}

// Runs the list, and fails the test once for each rule it breaks, and for
// each known bug, at its first violation. A broken rule no known bug
// explains also logs the list up to it.
- (QLMFuzzRun *)runActions:(NSArray<QLMFuzzAction *> *)actions name:(NSString *)name replay:(NSString *)replay {
    QLMFuzzRun *run = [[QLMFuzzRun alloc] initWithActions:actions];
    [run runStoppingAt:nil];
    NSMutableSet<NSString *> *reported = [NSMutableSet set];
    NSInteger last = -1;
    NSMutableString *unknown = [NSMutableString string];
    for (QLMFuzzViolation *violation in run.world.violations) {
        NSString *kind = QLMFuzzKindOf(violation);
        if ([reported containsObject:kind]) {
            continue;
        }
        [reported addObject:kind];
        if (violation.known == nil) {
            [unknown appendFormat:@"  %@\n", violation];
            last = MAX(last, violation.action);
        }
        XCTFail(@"%@: %@. Replay: %@", name, violation, replay);
    }
    if (last >= 0) {
        NSLog(@"QLMSafetyFuzz %@ broke a rule:\n%@Actions:\n%@Replay: %@", name, unknown, QLMFuzzListing(actions, last), replay);
    }
    return run;
}

- (QLMFuzzRun *)runSeed:(uint64_t)seed actions:(NSUInteger)count {
    NSArray<QLMFuzzAction *> *actions = QLMFuzzActionsForSeed(seed, count, (NSInteger)QLMFuzzGroups().count);
    NSString *replay = [NSString stringWithFormat:@"TEST_RUNNER_QLM_FUZZ_SEED=0x%llX TEST_RUNNER_QLM_FUZZ_ACTIONS=%lu", seed,
                                                  (unsigned long)count];
    return [self runActions:actions name:[NSString stringWithFormat:@"seed 0x%llX", seed] replay:replay];
}

// Expects the failures of the System bugs this file names, and no other.
// Not strict, since a run may not reach one.
- (void)expectKnownBugs {
    XCTExpectedFailureOptions *options = [XCTExpectedFailureOptions nonStrictOptions];
    options.issueMatcher = ^BOOL(XCTIssue *issue) {
        return [issue.compactDescription containsString:@"[known: "];
    };
    XCTExpectFailureWithOptions(QLMFuzzKnownBugs, options);
}

// Each seed's run holds every rule, but for the known bugs.
- (void)testEverySeedHoldsTheSafetyRules {
    [self expectKnownBugs];
    NSUInteger applied = 0;
    NSUInteger refused = 0;
    NSCountedSet<NSString *> *counts = [[NSCountedSet alloc] init];
    for (size_t i = 0; i < sizeof QLMFuzzSeeds / sizeof QLMFuzzSeeds[0]; i++) {
        QLMFuzzRun *run = [self runSeed:QLMFuzzSeeds[i] actions:QLMFuzzActionCount];
        applied += run.applied;
        refused += run.refused;
        NSCountedSet<NSString *> *runCounts = run.world.counts;
        for (NSString *what in runCounts) {
            for (NSUInteger n = 0; n < [runCounts countForObject:what]; n++) {
                [counts addObject:what];
            }
        }
    }
    // The runs reach what each check guards, and a group apply that goes
    // through and one refused.
    for (NSString *what in @[QLMFuzzCountVolume, QLMFuzzCountMutedRound, QLMFuzzCountRefused, QLMFuzzCountLease, QLMFuzzCountLate,
                             QLMFuzzCountLost]) {
        XCTAssertGreaterThan([counts countForObject:what], 0u, @"no %@", what);
    }
    XCTAssertGreaterThan(applied, 0u);
    XCTAssertGreaterThan(refused, 0u);
}

#pragma mark The bugs the runs found

// Expects `known` to break the rules, and nothing else to. Strict, so a fix
// fails the test: then drop the bug from this file.
- (void)expectBug:(NSString *)known {
    XCTExpectedFailureOptions *options = [[XCTExpectedFailureOptions alloc] init];
    options.issueMatcher = ^BOOL(XCTIssue *issue) {
        return [issue.compactDescription containsString:known];
    };
    XCTExpectFailureWithOptions([NSString stringWithFormat:@"System bug: %@", known], options);
}

// The seed that found the bug, then the list it shrank to.
- (void)runSeed:(uint64_t)seed shrunkTo:(NSArray<QLMFuzzAction *> *)actions {
    [self runSeed:seed actions:QLMFuzzActionCount];
    NSString *name = [NSString stringWithFormat:@"seed 0x%llX, shrunk", seed];
    [self runActions:actions name:name replay:NSStringFromSelector(self.invocation.selector)];
}

// A stop with no hand-back lets go at once, and a start right after it
// begins a new run while the stopped run's last send still waits for its
// handler. The link fails that send as it closes, and its handler then
// ends the new run's send in flight, so System sends the next one while
// the link still holds the first. System stays a step out: each completion
// after that ends the send after its own. A Debug build stops at
// QLMReportLink's assertion. A Release build refuses each extra send, and
// System counts it as sent, so a volume or a mute may never go out.
// QLMSystem.h lets a start come during a stop.
- (void)testAStartRightAfterAStopKeepsTwoSendsInFlight {
    [self expectBug:QLMFuzzKnownLateCompletion];
    [self runSeed:QLMFuzzLateCompletionSeed shrunkTo:@[QLMFuzzMake(QLMFuzzRestart, 0, 0, 0, NO)]];
}

// System builds a volume frame when it queues it, not when it sends it.
// A ceiling lowered meanwhile does not reach the frames already queued, so
// they go out above it, under the ceiling before. QLMSystem.h says a new
// ceiling caps every volume frame after it. Each frame queued at a wake,
// a dim, a mute all, or an apply can wait behind holds and replies.
- (void)testAVolumeQueuedBeforeACeilingDropGoesOutAboveIt {
    [self expectBug:QLMFuzzKnownStaleVolume];
    [self runSeed:QLMFuzzStaleVolumeSeed
         shrunkTo:@[
             QLMFuzzMake(QLMFuzzCeiling, -0.5, 0, 0, NO), QLMFuzzMake(QLMFuzzVolume, -0.0, 0, 0, NO),
             QLMFuzzMake(QLMFuzzCeiling, -3.5, 0, 0, NO), QLMFuzzMake(QLMFuzzAdvance, 0.2, 0, 0, NO)
         ]];
}

// The same for a round of 2B: each frame says the mutes as they were when
// it was queued. Mute a monitor, unmute all, and mute it again, quicker
// than the rounds go out: the unmute's round reaches the monitor after the
// first mute's, and unmutes it until the second's comes.
- (void)testARoundQueuedBeforeAMuteUnmutesAMutedMonitor {
    [self expectBug:QLMFuzzKnownStaleRound];
    [self runSeed:QLMFuzzStaleRoundSeed
         shrunkTo:@[
             QLMFuzzMake(QLMFuzzAdvance, 1.5, 0, 0, NO), QLMFuzzMake(QLMFuzzMute, 0, 0, 0, YES),
             QLMFuzzMake(QLMFuzzMuteAll, 0, 0, 0, NO), QLMFuzzMake(QLMFuzzMute, 0, 0, 0, YES),
             QLMFuzzMake(QLMFuzzAdvance, 3, 0, 0, NO)
         ]];
}

#pragma mark Replay and soak

// TEST_RUNNER_QLM_FUZZ_SEED replays one seed. TEST_RUNNER_QLM_FUZZ_SHRINK=1
// shrinks it to a short list that breaks the same rule: the first that no
// known bug explains, else the first. A check's number in place of 1 picks
// that check.
- (void)testReplaysASeed {
    NSString *seedText = QLMFuzzEnvironment(@"QLM_FUZZ_SEED");
    if (seedText == nil || QLMFuzzEnvironment(@"QLM_FUZZ_SOAK") != nil) {
        return;
    }
    uint64_t seed = QLMFuzzParseSeed(seedText);
    NSString *countText = QLMFuzzEnvironment(@"QLM_FUZZ_ACTIONS");
    NSUInteger count = countText != nil ? (NSUInteger)countText.integerValue : QLMFuzzActionCount;
    NSArray<QLMFuzzAction *> *actions = QLMFuzzActionsForSeed(seed, count, (NSInteger)QLMFuzzGroups().count);
    NSString *shrink = QLMFuzzEnvironment(@"QLM_FUZZ_SHRINK");
    if (shrink == nil) {
        [self expectKnownBugs];
        QLMFuzzRun *run = [self runSeed:seed actions:count];
        NSInteger last = -1;
        for (QLMFuzzViolation *violation in run.world.violations) {
            last = MAX(last, violation.action);
        }
        NSLog(@"QLMSafetyFuzz seed 0x%llX, through its last violation:\n%@", seed, QLMFuzzListing(actions, last));
        return;
    }
    QLMFuzzRun *run = [[QLMFuzzRun alloc] initWithActions:actions];
    [run runStoppingAt:nil];
    NSString *kind = nil;
    for (QLMFuzzViolation *violation in run.world.violations) {
        BOOL picked = shrink.integerValue > 1 ? violation.check == (NSUInteger)shrink.integerValue : violation.known == nil;
        if (picked) {
            kind = QLMFuzzKindOf(violation);
            break;
        }
    }
    if (kind == nil && shrink.integerValue <= 1 && run.world.violations.count > 0) {
        kind = QLMFuzzKindOf(run.world.violations[0]);
    }
    if (kind == nil) {
        NSLog(@"QLMSafetyFuzz seed 0x%llX breaks no rule to shrink", seed);
        return;
    }
    NSArray<QLMFuzzAction *> *shrunk = [self shrink:actions kind:kind];
    QLMFuzzRun *last = [[QLMFuzzRun alloc] initWithActions:shrunk];
    [last runStoppingAt:kind];
    NSLog(@"QLMSafetyFuzz seed 0x%llX shrinks to %lu actions:\n%@%@", seed, (unsigned long)shrunk.count,
          QLMFuzzListing(shrunk, (NSInteger)shrunk.count), QLMFuzzFirstOfKind(last.world.violations, kind));
}

// Drops actions while the list still breaks the rule, in ever smaller
// chunks, as delta debugging does, and cuts it after the violation.
- (NSArray<QLMFuzzAction *> *)shrink:(NSArray<QLMFuzzAction *> *)actions kind:(NSString *)kind {
    NSArray<QLMFuzzAction *> * (^failing)(NSArray<QLMFuzzAction *> *) = ^NSArray<QLMFuzzAction *> *(NSArray<QLMFuzzAction *> *candidate) {
        QLMFuzzRun *run = [[QLMFuzzRun alloc] initWithActions:candidate];
        [run runStoppingAt:kind];
        QLMFuzzViolation *first = QLMFuzzFirstOfKind(run.world.violations, kind);
        if (first == nil) {
            return nil;
        }
        NSUInteger end = first.action < 0 ? candidate.count : MIN(candidate.count, (NSUInteger)first.action + 1);
        return [candidate subarrayWithRange:NSMakeRange(0, end)];
    };
    NSArray<QLMFuzzAction *> *best = failing(actions) ?: actions;
    NSUInteger chunk = MAX((NSUInteger)1, best.count / 2);
    while (chunk >= 1) {
        BOOL removed = NO;
        NSUInteger start = 0;
        while (start < best.count) {
            NSMutableArray<QLMFuzzAction *> *candidate = [best mutableCopy];
            [candidate removeObjectsInRange:NSMakeRange(start, MIN(chunk, best.count - start))];
            NSArray<QLMFuzzAction *> *smaller = candidate.count > 0 ? failing(candidate) : nil;
            if (smaller != nil) {
                best = smaller;
                removed = YES;
            } else {
                start += chunk;
            }
        }
        if (!removed) {
            if (chunk == 1) {
                break;
            }
            chunk /= 2;
        }
    }
    return best;
}

// TEST_RUNNER_QLM_FUZZ_SOAK runs that many seeds of 2,000 actions, or
// TEST_RUNNER_QLM_FUZZ_ACTIONS, from a random seed or
// TEST_RUNNER_QLM_FUZZ_SEED on, and names each seed that breaks a rule.
- (void)testSoaksWhenAsked {
    NSString *soak = QLMFuzzEnvironment(@"QLM_FUZZ_SOAK");
    if (soak == nil) {
        return;
    }
    [self expectKnownBugs];
    NSString *seedText = QLMFuzzEnvironment(@"QLM_FUZZ_SEED");
    uint64_t base = seedText != nil ? QLMFuzzParseSeed(seedText) : (uint64_t)arc4random() << 32 | arc4random();
    NSString *countText = QLMFuzzEnvironment(@"QLM_FUZZ_ACTIONS");
    NSUInteger count = countText != nil ? (NSUInteger)countText.integerValue : 2000;
    NSInteger runs = soak.integerValue;
    for (NSInteger i = 0; i < runs; i++) {
        [self runSeed:base + (uint64_t)i actions:count];
    }
}

@end
