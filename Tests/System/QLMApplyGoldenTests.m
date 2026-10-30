#import <XCTest/XCTest.h>

#import "QLMAdapter.h"
#import "QLMApplySequence.h"
#import "QLMDSPBlock.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the six group switches in captures/group-switch-*, the apply at
// launch in captures/startup-idle, and the apply after a wake in
// captures/standby-wake, each with its notes.md, and Fixtures/Main.sam.
//
// Each test builds what System sends for one captured apply, at the
// capture's own sessions, and diffs it against what GLM sent. Both sides
// leave out GLM's cycle, which runs beside its apply: the adapter's polls,
// the probes, the leases, the polls, the volume after a probe, and each new
// monitor's 39 and 19 01 before its block. GLM's side also leaves out the
// frames qlm skips: 05 04, which is never-send, and the 8351B's 43 00 02 and
// 4B 00 00 00 01, refused while its rate is unverified. What remains must
// match byte for byte, but for the differences each test lists and explains.
@interface QLMApplyGoldenTests : XCTestCase
@end

// The serial each captured hardware ID has in Main.sam: the leases in
// captures/startup-idle at 8.43 to 8.48 s, and the DSP passes that
// QLMDSPBlockGoldenTests matches to each node.
static NSString *QLMSerialForCapturedID(const uint8_t *hardwareID) {
    NSDictionary<NSString *, NSString *> *serials = @{
        @"122FAB": @"1000005", @"114BAB": @"1000002", @"122FD1": @"1000004",
        @"115326": @"1000006", @"114BEA": @"1000003", @"122698": @"1000007",
    };
    return serials[[NSString stringWithFormat:@"%02X%02X%02X", hardwareID[0], hardwareID[1], hardwareID[2]]];
}

static NSString *QLMHexOf(NSData *record) {
    NSMutableArray<NSString *> *bytes = [NSMutableArray array];
    const uint8_t *raw = record.bytes;
    for (NSUInteger i = 0; i < record.length; i++) {
        [bytes addObject:[NSString stringWithFormat:@"%02X", raw[i]]];
    }
    return [bytes componentsJoinedByString:@" "];
}

// One captured frame, kept for the diff.
@interface QLMCapturedFrame : NSObject
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) NSData *record;
@end

@implementation QLMCapturedFrame
@end

// What a capture shows of GLM's monitors at one moment.
@interface QLMCapturedBus : NSObject
@property (nonatomic) NSMutableDictionary<NSNumber *, NSString *> *serials;  // session to serial
@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *on;       // session to its last status
@property (nonatomic) NSMutableArray<NSNumber *> *leaseOrder;
@end

@implementation QLMCapturedBus
@end

@implementation QLMApplyGoldenTests

// `seed` names the sessions GLM leased before the capture began, as
// "03:1000002 06:1000003". Leases and telemetry update the bus up to `time`.
- (QLMCapturedBus *)busOf:(QLMCapture *)capture seed:(NSString *)seed before:(NSTimeInterval)time {
    QLMCapturedBus *bus = [[QLMCapturedBus alloc] init];
    bus.serials = [NSMutableDictionary dictionary];
    bus.on = [NSMutableDictionary dictionary];
    bus.leaseOrder = [NSMutableArray array];
    for (NSString *entry in [seed componentsSeparatedByString:@" "]) {
        NSArray<NSString *> *parts = [entry componentsSeparatedByString:@":"];
        if (parts.count == 2) {
            NSNumber *session = @(strtoul(parts[0].UTF8String, NULL, 16));
            bus.serials[session] = parts[1];
            [bus.leaseOrder addObject:session];
        }
    }
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        if (exchange.time >= time) {
            break;
        }
        QLMMessage message = exchange.message;
        if (message.address == QLMAddressMulticast && message.length == 5 && message.payload[0] == 0x02) {
            // A monitor leased again has lost its old lease.
            NSNumber *session = @(message.payload[4]);
            NSString *serial = QLMSerialForCapturedID(message.payload + 1);
            for (NSNumber *old in [bus.serials allKeysForObject:serial]) {
                [bus.serials removeObjectForKey:old];
                [bus.leaseOrder removeObject:old];
            }
            bus.serials[session] = serial;
            [bus.leaseOrder removeObject:session];
            [bus.leaseOrder addObject:session];
            [bus.on removeObjectForKey:session];
        }
        if (QLMAddressIsLeasable(message.address) && message.length == 1 && message.payload[0] == 0x08 && exchange.answered) {
            QLMMessage reply = exchange.reply;
            QLMTelemetry telemetry;
            QLMTelemetryStatus status = QLMReplyTelemetry(&reply, &telemetry);
            if ((status == QLMTelemetryOK || status == QLMTelemetryErrorUnknownTag) && telemetry.status != QLMTelemetryAbsent) {
                bus.on[@(message.address)] = @(telemetry.status == QLMTelemetryStatusOn);
            }
        }
    }
    return bus;
}

// The monitor at `session`, with the fixture's hardware ID for its node.
- (QLMApplyMonitor *)monitorAt:(uint8_t)session of:(QLMCapturedBus *)bus {
    QLMSetupDevice *device = [QLMReadFixtureSetup() deviceWithSerial:bus.serials[@(session)]];
    XCTAssertNotNil(device, @"session %02X", session);
    QLMApplyMonitor *monitor = [[QLMApplyMonitor alloc] initWithHardwareID:device.hardwareID session:session];
    monitor.on = bus.on[@(session)].boolValue;
    return monitor;
}

// Every monitor on the bus, in lease order.
- (NSMutableArray<QLMApplyMonitor *> *)monitorsOf:(QLMCapturedBus *)bus {
    NSMutableArray<QLMApplyMonitor *> *monitors = [NSMutableArray array];
    for (NSNumber *session in bus.leaseOrder) {
        [monitors addObject:[self monitorAt:session.unsignedCharValue of:bus]];
    }
    return monitors;
}

- (NSDictionary<NSData *, QLMDSPBlock *> *)blocksFor:(QLMSetupGroup *)group {
    NSError *error = nil;
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = [QLMDSPBlock blocksByHardwareIDForGroup:group error:&error];
    XCTAssertEqual(blocks.count, group.nodes.count, @"%@", error);
    return blocks;
}

static BOOL QLMIsSkipped(const QLMMessage *message) {
    uint8_t opcode = message->payload[0];
    return opcode == 0x05 || (opcode == 0x43 && message->length == 3) || (opcode == 0x4B && message->length == 5);
}

// GLM's frames from `from` to `to`, less its cycle and the frames qlm skips.
- (NSArray<QLMCapturedFrame *> *)glmFramesOf:(QLMCapture *)capture from:(NSTimeInterval)from to:(NSTimeInterval)to {
    NSMutableArray<QLMCapturedFrame *> *frames = [NSMutableArray array];
    QLMApplyFilter *filter = [[QLMApplyFilter alloc] init];
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        if (exchange.time > to) {
            break;
        }
        QLMMessage message = exchange.message;
        NSData *record = QLMAdapterRecord(&message);
        if (![filter keeps:record] || exchange.time < from || QLMIsSkipped(&message)) {
            continue;
        }
        QLMCapturedFrame *frame = [[QLMCapturedFrame alloc] init];
        frame.time = exchange.time;
        frame.record = record;
        [frames addObject:frame];
    }
    return frames;
}

// The longest common subsequence's leftovers: what only GLM sent, with its
// time, and what only qlm sends.
static NSArray<NSString *> *QLMDiff(NSArray<QLMCapturedFrame *> *glm, NSArray<NSData *> *qlm) {
    NSUInteger n = glm.count, m = qlm.count;
    NSMutableData *table = [NSMutableData dataWithLength:(n + 1) * (m + 1) * sizeof(uint16_t)];
    uint16_t *lengths = table.mutableBytes;
    for (NSInteger i = (NSInteger)n - 1; i >= 0; i--) {
        for (NSInteger j = (NSInteger)m - 1; j >= 0; j--) {
            uint16_t *cell = &lengths[(NSUInteger)i * (m + 1) + (NSUInteger)j];
            if ([glm[(NSUInteger)i].record isEqualToData:qlm[(NSUInteger)j]]) {
                *cell = lengths[(NSUInteger)(i + 1) * (m + 1) + (NSUInteger)(j + 1)] + 1;
            } else {
                *cell = MAX(lengths[(NSUInteger)(i + 1) * (m + 1) + (NSUInteger)j], lengths[(NSUInteger)i * (m + 1) + (NSUInteger)(j + 1)]);
            }
        }
    }
    NSMutableArray<NSString *> *differences = [NSMutableArray array];
    NSUInteger i = 0, j = 0;
    while (i < n || j < m) {
        if (i < n && j < m && [glm[i].record isEqualToData:qlm[j]]) {
            i++;
            j++;
        } else if (j < m && (i == n || lengths[i * (m + 1) + j + 1] >= lengths[(i + 1) * (m + 1) + j])) {
            [differences addObject:[NSString stringWithFormat:@"qlm only: %@", QLMHexOf(qlm[j])]];
            j++;
        } else {
            [differences addObject:[NSString stringWithFormat:@"GLM only at %.3f: %@", glm[i].time, QLMHexOf(glm[i].record)]];
            i++;
        }
    }
    return differences;
}

// Every window holds a whole apply: at least its DSP pass.
- (NSArray<NSString *> *)diff:(QLMCapture *)capture from:(NSTimeInterval)from to:(NSTimeInterval)to against:(NSArray<NSData *> *)qlm {
    NSArray<QLMCapturedFrame *> *glm = [self glmFramesOf:capture from:from to:to];
    XCTAssertGreaterThan(glm.count, 100u);
    XCTAssertGreaterThan(qlm.count, 100u);
    return QLMDiff(glm, qlm);
}

- (void)assertDifferences:(NSArray<NSString *> *)differences are:(NSArray<NSString *> *)expected scenario:(NSString *)scenario {
    XCTAssertEqualObjects(differences, expected, @"%@:\n%@", scenario, [differences componentsJoinedByString:@"\n"]);
}

#pragma mark - Group switches

// A group switch with every monitor leased throughout. `seed` names the
// sessions leased before the capture. The restore's volume is GLM's level
// in every capture, -56.5 dB.
- (NSArray<NSString *> *)switchIn:(NSString *)scenario
                               to:(NSString *)groupName
                             seed:(NSString *)seed
                             from:(NSTimeInterval)from
                               to:(NSTimeInterval)to {
    QLMCapture *capture = QLMReadCapture(scenario, NULL);
    XCTAssertNotNil(capture);
    QLMSetupGroup *group = QLMFixtureGroup(groupName);
    QLMCapturedBus *bus = [self busOf:capture seed:seed before:from];
    QLMApplySequence *sequence = [[QLMApplySequence alloc] initWithGroup:group monitors:[self monitorsOf:bus] adapterMuted:NO];
    NSArray<NSData *> *qlm = [sequence switchWithBlocks:[self blocksFor:group] volume:QLMCommandVolumeWord(0x003107, QLMVolumeWordMax)];
    return [self diff:capture from:from to:to against:qlm];
}

// Every monitor was on before the switch, and GLM's cycle stayed out of it,
// so GLM sent exactly what System sends.
- (void)testSwitchFrom4x2To2x1 {
    NSArray<NSString *> *differences = [self switchIn:@"group-switch-main-4x2-main-2x1" to:@"Main 2x1"
                                                 seed:@"08:1000005 03:1000002 09:1000004 05:1000006 06:1000003 0A:1000007"
                                                 from:12.35 to:13.5];
    [self assertDifferences:differences are:@[] scenario:@"4x2 to 2x1"];
}

// GLM sent the adapter 01 2B 00 a second time, mid-round; no capture says
// why. Its cycle ran inside the tail, and its polls found 02 at 14.249 s
// and 04 at 14.274 s in standby, after the routing pass sent each 3A 03 02.
// So GLM left 02 out of the tail's second round, and both out of the
// restore's round. System's cycle waits behind the apply, so its rounds
// keep both.
- (void)testSwitchFrom4x2To2x2 {
    NSArray<NSString *> *differences = [self switchIn:@"group-switch-main-4x2-main-2x2" to:@"Main 2x2"
                                                 seed:@"02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"
                                                 from:13.07 to:14.5];
    [self assertDifferences:differences are:@[
        @"GLM only at 14.230: 01 2B 00",
        @"qlm only: 02 2B 05", @"qlm only: 02 2B 07",
        @"qlm only: 04 2B 05", @"qlm only: 04 2B 07", @"qlm only: 02 2B 05", @"qlm only: 02 2B 07",
    ] scenario:@"4x2 to 2x2"];
}

// GLM left out the restore's round and the pair here, though it sent them
// in the other five switches. 02 and 04 were in standby before the switch,
// so neither gets a 2B.
- (void)testSwitchFrom2x2To2x1 {
    NSArray<NSString *> *differences = [self switchIn:@"group-switch-main-2x2-main-2x1" to:@"Main 2x1"
                                                 seed:@"02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"
                                                 from:13.99 to:15.5];
    [self assertDifferences:differences are:@[
        @"qlm only: 03 2B 04", @"qlm only: 06 2B 04", @"qlm only: 05 2B 04", @"qlm only: 07 2B 05", @"qlm only: 07 2B 07",
        @"qlm only: FF 2D 00", @"qlm only: FF 3D 00 00",
    ] scenario:@"2x2 to 2x1"];
}

#pragma mark - Switches that wake monitors

// A switch that wakes monitors from standby. Each loses its lease, so GLM's
// frames to its old session get 01 7E, and GLM applies its block again at
// its new session once the probe finds it. System sends the switch whole,
// then the new monitors' blocks, then each one's state after its next poll.
- (NSArray<NSString *> *)wakingSwitchIn:(NSString *)scenario
                                     to:(NSString *)groupName
                                   seed:(NSString *)seed
                                  fresh:(NSString *)fresh
                                   from:(NSTimeInterval)from
                                     to:(NSTimeInterval)to {
    QLMCapture *capture = QLMReadCapture(scenario, NULL);
    QLMSetupGroup *group = QLMFixtureGroup(groupName);
    NSDictionary<NSData *, QLMDSPBlock *> *blocks = [self blocksFor:group];
    QLMCapturedBus *before = [self busOf:capture seed:seed before:from];
    QLMApplySequence *switching = [[QLMApplySequence alloc] initWithGroup:group monitors:[self monitorsOf:before] adapterMuted:NO];
    NSMutableArray<NSData *> *qlm = [[switching switchWithBlocks:blocks volume:QLMCommandVolumeWord(0x003107, QLMVolumeWordMax)] mutableCopy];

    // After the switch: the old leases of the woken monitors are gone, and
    // the new ones are on by their first poll.
    QLMCapturedBus *after = [self busOf:capture seed:seed before:to];
    NSMutableArray<QLMApplyMonitor *> *leased = [NSMutableArray array];
    NSMutableArray<QLMApplyMonitor *> *added = [NSMutableArray array];
    NSArray<NSString *> *freshSessions = [fresh componentsSeparatedByString:@" "];
    for (NSNumber *session in after.leaseOrder) {
        QLMApplyMonitor *monitor = [self monitorAt:session.unsignedCharValue of:after];
        if ([freshSessions containsObject:[NSString stringWithFormat:@"%02X", session.unsignedCharValue]]) {
            monitor.on = NO;
            [added addObject:monitor];
        } else {
            monitor.on = before.on[session].boolValue;
            [leased addObject:monitor];
        }
    }
    [leased addObjectsFromArray:added];
    QLMApplySequence *enumerating = [[QLMApplySequence alloc] initWithGroup:group monitors:leased adapterMuted:NO];
    [qlm addObjectsFromArray:[enumerating enumerationOf:added blocks:blocks]];
    for (QLMApplyMonitor *monitor in added) {
        [qlm addObjectsFromArray:[enumerating stateOf:monitor firstOfTwo:NO]];
    }
    return [self diff:capture from:from to:to against:qlm];
}

// GLM's restore ran beside its apply to the two woken 8330A, 0C and 0D:
// two of its three volumes came during their blocks, and the third after
// their round and pair. Then came its round and pair. System sends the
// restore whole, then their blocks.
- (void)testSwitchFrom2x2To4x2 {
    NSArray<NSString *> *differences = [self wakingSwitchIn:@"group-switch-main-2x2-main-4x2" to:@"Main 4x2"
                                                       seed:@"08:1000005 03:1000002 09:1000004 05:1000006 06:1000003 0B:1000007"
                                                      fresh:@"0C 0D"
                                                       from:10.15 to:12.81];
    [self assertDifferences:differences are:@[
        @"qlm only: FF 1F 00 31 07", @"qlm only: FF 1F 00 31 07", @"qlm only: FF 1F 00 31 07",
        @"qlm only: 03 2B 04", @"qlm only: 06 2B 04", @"qlm only: 05 2B 04", @"qlm only: 0B 2B 04",
        @"qlm only: FF 2D 00", @"qlm only: FF 3D 00 00",
        @"GLM only at 12.000: FF 1F 00 31 07", @"GLM only at 12.027: FF 1F 00 31 07", @"GLM only at 12.219: FF 1F 00 31 07",
        @"GLM only at 12.310: 03 2B 04", @"GLM only at 12.312: 06 2B 04", @"GLM only at 12.314: 05 2B 04",
        @"GLM only at 12.316: 0B 2B 04", @"GLM only at 12.318: FF 2D 00", @"GLM only at 12.319: FF 3D 00 00",
    ] scenario:@"2x2 to 4x2"];
}

// As above, with three woken monitors, 08, 09, and 0A.
- (void)testSwitchFrom2x1To4x2 {
    NSArray<NSString *> *differences = [self wakingSwitchIn:@"group-switch-main-2x1-main-4x2" to:@"Main 4x2"
                                                       seed:@"02:1000005 03:1000002 04:1000004 05:1000006 06:1000003 07:1000007"
                                                      fresh:@"08 09 0A"
                                                       from:35.0 to:38.25];
    [self assertDifferences:differences are:@[
        @"qlm only: FF 1F 00 31 07", @"qlm only: FF 1F 00 31 07", @"qlm only: FF 1F 00 31 07",
        @"qlm only: 03 2B 04", @"qlm only: 06 2B 04", @"qlm only: 05 2B 04",
        @"qlm only: FF 2D 00", @"qlm only: FF 3D 00 00",
        @"GLM only at 37.277: FF 1F 00 31 07", @"GLM only at 37.307: FF 1F 00 31 07", @"GLM only at 37.681: FF 1F 00 31 07",
        @"GLM only at 37.767: 03 2B 04", @"GLM only at 37.769: 06 2B 04", @"GLM only at 37.771: 05 2B 04",
        @"GLM only at 37.773: FF 2D 00", @"GLM only at 37.773: FF 3D 00 00",
    ] scenario:@"2x1 to 4x2"];
}

// The 7350A at 0A woke into the group and lost its lease. GLM sent the
// adapter 01 2B 00 twice, as in the switch from 4x2 to 2x2. It ducked again
// at 10.231 s, before its restore's round and pair, and then ran the whole
// switch a second time, beside its apply to the 7350A at 0B. Only the first
// pass is compared. System sends a switch once.
- (void)testSwitchFrom2x1To2x2 {
    NSArray<NSString *> *differences = [self wakingSwitchIn:@"group-switch-main-2x1-main-2x2" to:@"Main 2x2"
                                                       seed:@"08:1000005 03:1000002 09:1000004 05:1000006 06:1000003 0A:1000007"
                                                      fresh:@""
                                                       from:8.80 to:10.31];
    [self assertDifferences:differences are:@[
        @"GLM only at 10.181: 01 2B 00",
        @"GLM only at 10.231: FF 1F 00 00 08", @"GLM only at 10.232: FF 1F 00 00 02",
    ] scenario:@"2x1 to 2x2"];
}

#pragma mark - Startup and wake

// GLM's apply to every monitor it finds: at launch and after a wake. None
// has telemetry yet, so the round before the pair is empty, and each gets
// its state after its first poll.
- (NSArray<NSString *> *)enumerationIn:(NSString *)scenario
                                 group:(NSString *)groupName
                                  from:(NSTimeInterval)from
                                    to:(NSTimeInterval)to {
    QLMCapture *capture = QLMReadCapture(scenario, NULL);
    QLMSetupGroup *group = QLMFixtureGroup(groupName);
    NSArray<QLMApplyMonitor *> *fresh = [self monitorsOf:[self busOf:capture seed:@"" before:from]];
    QLMApplySequence *sequence = [[QLMApplySequence alloc] initWithGroup:group monitors:fresh adapterMuted:NO];
    NSMutableArray<NSData *> *qlm = [[sequence enumerationOf:fresh blocks:[self blocksFor:group]] mutableCopy];
    for (QLMApplyMonitor *monitor in fresh) {
        [qlm addObjectsFromArray:[sequence stateOf:monitor firstOfTwo:NO]];
    }
    return [self diff:capture from:from to:to against:qlm];
}

- (void)testStartupApply {
    NSArray<NSString *> *differences = [self enumerationIn:@"startup-idle" group:@"Main 2x1" from:8.53 to:9.91];
    [self assertDifferences:differences are:@[] scenario:@"startup"];
}

- (void)testWakeApply {
    NSArray<NSString *> *differences = [self enumerationIn:@"standby-wake" group:@"Main 4x2" from:47.70 to:49.09];
    [self assertDifferences:differences are:@[] scenario:@"wake"];
}

@end
