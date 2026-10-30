#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMFakeBus.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: the captures each test names, and their notes.md. Each test runs
// one action through System over a fake bus of six monitors, and checks the
// frames System sends against the frames GLM sent for it, byte for byte. The
// session IDs differ, so the capture's are mapped to System's in the order
// each first appears. A frame the allowlist refuses is left out. The
// adapter's 01 08 polls run on their own timer, so both sides leave them out.
@interface QLMSystemGoldenTests : XCTestCase
@end

@implementation QLMSystemGoldenTests {
    QLMFakeBus *_bus;
    QLMSystemSettings *_settings;
    QLMSystem *_system;
}

- (void)setUp {
    [super setUp];
    NSMutableArray<QLMFakeMonitor *> *monitors = [NSMutableArray array];
    for (uint8_t i = 0; i < 6; i++) {
        const uint8_t hardwareID[3] = {0x12, 0x2F, (uint8_t)(0xA0 + i)};
        NSString *serial = [NSString stringWithFormat:@"8330AP2100000%u", i];
        [monitors addObject:[[QLMFakeMonitor alloc] initWithHardwareID:QLMBytes(hardwareID, 3) serialNumber:serial
                                                            systemInfo:@"c-2;model-8330A" deviceClass:QLMTelemetryClassTwoWay]];
    }
    _bus = [[QLMFakeBus alloc] initWithMonitors:monitors];
    _settings = [[QLMSystemSettings alloc] init];
    // No cycle may fire inside an action.
    _settings.cycleInterval = 10;
    _settings.ceilingDecibels = 0;
    _settings.adapterPollInterval = 0;
}

- (void)tearDown {
    [_system stop];
    [super tearDown];
}

// Waits until the condition holds, polling.
- (void)waitUntil:(BOOL (^)(void))condition {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] < 0) {
            XCTFail(@"timed out");
            return;
        }
        [NSThread sleepForTimeInterval:0.005];
    }
}

// Starts System, finds all six monitors, and sets GLM's level in mute-dim.
- (NSArray<QLMMonitorState *> *)startSystem {
    _system = [[QLMSystem alloc] initWithAdapter:_bus settings:_settings];
    [_system start];
    [self waitUntil:^BOOL {
        QLMSnapshot *snapshot = self->_system.snapshot;
        return snapshot.monitors.count == 6 && snapshot.allIdentified && snapshot.idle;
    }];
    [_system setVolumeDecibels:-56.5];
    const uint8_t levelBytes[] = {QLMAddressBroadcast, 0x1F, 0x00, 0x31, 0x07};
    NSData *level = QLMBytes(levelBytes, sizeof levelBytes);
    [self waitUntil:^BOOL {
        return [self->_bus.sentMessages containsObject:level];
    }];
    return _system.snapshot.monitors;
}

static BOOL QLMIsAdapterPoll(NSData *record) {
    const uint8_t *bytes = record.bytes;
    return record.length == 2 && bytes[0] == QLMAddressAdapter && bytes[1] == 0x08;
}

// What System sent from `start` on, less the adapter's polls.
- (NSArray<NSData *> *)sentFrom:(NSUInteger)start {
    NSArray<NSData *> *sent = _bus.sentMessages;
    NSMutableArray<NSData *> *found = [NSMutableArray array];
    for (NSUInteger i = start; i < sent.count; i++) {
        if (!QLMIsAdapterPoll(sent[i])) {
            [found addObject:sent[i]];
        }
    }
    return found;
}

// `count` frames of captures/<scenario>, from the one at `time` to the half
// millisecond, less the adapter's polls.
- (NSArray<QLMCaptureExchange *> *)frames:(NSUInteger)count of:(NSString *)scenario from:(NSTimeInterval)time {
    NSMutableArray<QLMCaptureExchange *> *run = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
        if (run.count == 0 && fabs(exchange.time - time) >= 0.0005) {
            continue;
        }
        QLMMessage message = exchange.message;
        if (QLMIsAdapterPoll(QLMAdapterRecord(&message))) {
            continue;
        }
        [run addObject:exchange];
        if (run.count == count) {
            return run;
        }
    }
    XCTFail(@"%@ has %lu of %lu frames from %.6f s", scenario, (unsigned long)run.count, (unsigned long)count, time);
    return @[];
}

static BOOL QLMIsSession(uint8_t address) {
    return address >= QLMAddressSessionFirst && address <= QLMAddressSessionLast && address != QLMAddressMulticast;
}

// The captured frames less the ones the allowlist refuses, which must be
// `refused`, with each session ID mapped to System's.
- (NSArray<NSData *> *)expectedFrom:(NSArray<QLMCaptureExchange *> *)captured
                            refused:(NSArray<NSData *> *)refused
                           sessions:(NSArray<QLMMonitorState *> *)monitors
                          inOrderOf:(NSArray<NSData *> *)sent {
    NSMutableArray<NSData *> *kept = [NSMutableArray array];
    NSMutableArray<NSData *> *dropped = [NSMutableArray array];
    for (QLMCaptureExchange *exchange in captured) {
        QLMMessage message = exchange.message;
        NSData *record = QLMAdapterRecord(&message);
        if (QLMFrameAllows(message.payload, message.length)) {
            [kept addObject:record];
        } else {
            [dropped addObject:record];
        }
    }
    XCTAssertEqualObjects(dropped, refused);

    // Each captured session maps to the session System sent to in the same
    // place, so the mapping comes from the first frame to each.
    NSMutableDictionary<NSNumber *, NSNumber *> *map = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *leased = [NSMutableSet set];
    for (QLMMonitorState *monitor in monitors) {
        [leased addObject:@(monitor.session)];
    }
    NSMutableArray<NSData *> *expected = [NSMutableArray array];
    for (NSUInteger i = 0; i < kept.count; i++) {
        NSMutableData *frame = [kept[i] mutableCopy];
        uint8_t *bytes = frame.mutableBytes;
        if (QLMIsSession(bytes[0])) {
            NSNumber *mapped = map[@(bytes[0])];
            if (mapped == nil && i < sent.count) {
                uint8_t to = ((const uint8_t *)sent[i].bytes)[0];
                if ([leased containsObject:@(to)] && ![map.allValues containsObject:@(to)]) {
                    mapped = @(to);
                    map[@(bytes[0])] = mapped;
                }
            }
            XCTAssertNotNil(mapped, @"no session for %02X at %lu", bytes[0], (unsigned long)i);
            bytes[0] = (uint8_t)mapped.unsignedCharValue;
        }
        [expected addObject:frame];
    }
    return expected;
}

- (void)assertSentFrom:(NSUInteger)start
             isCapture:(NSString *)scenario
                  from:(NSTimeInterval)time
                 count:(NSUInteger)count
               refused:(NSArray<NSData *> *)refused
              monitors:(NSArray<QLMMonitorState *> *)monitors {
    NSArray<QLMCaptureExchange *> *captured = [self frames:count of:scenario from:time];
    NSUInteger kept = captured.count - refused.count;
    [self waitUntil:^BOOL {
        return [self sentFrom:start].count >= kept;
    }];
    // Long enough for a frame too many to show.
    [NSThread sleepForTimeInterval:0.05];
    NSArray<NSData *> *sent = [self sentFrom:start];
    NSArray<NSData *> *expected = [self expectedFrom:captured refused:refused sessions:monitors inOrderOf:sent];
    XCTAssertEqualObjects(sent, expected, @"%@ from %.6f s", scenario, time);
}

#pragma mark - Mute

// Mute one monitor, mute-dim, 19.19 s, and unmute it, 22.74 s: two rounds of
// 2B to every monitor, 03 to the muted one and 04 to the rest. GLM muted
// 0B, last in its round.
- (void)testMutingOneMonitorIsGLMs {
    NSArray<QLMMonitorState *> *monitors = [self startSystem];
    NSData *last = monitors.lastObject.hardwareID;

    NSUInteger before = _bus.sentMessages.count;
    [_system setMuted:YES forMonitorWithHardwareID:last];
    [self assertSentFrom:before isCapture:@"mute-dim" from:19.186196 count:12 refused:@[] monitors:monitors];

    before = _bus.sentMessages.count;
    [_system setMuted:NO forMonitorWithHardwareID:last];
    [self assertSentFrom:before isCapture:@"mute-dim" from:22.739597 count:12 refused:@[] monitors:monitors];
}

// Mute all, mute-dim, 46.19 s, and unmute all, 48.60 s: the level, then
// `2B 01` or `2B 00` to the adapter at 01, then two rounds of 2B to every
// monitor.
- (void)testMutingAllIsGLMs {
    NSArray<QLMMonitorState *> *monitors = [self startSystem];

    NSUInteger before = _bus.sentMessages.count;
    [_system setAllMuted:YES];
    [self assertSentFrom:before isCapture:@"mute-dim" from:46.188342 count:14 refused:@[] monitors:monitors];
    XCTAssertTrue(_system.snapshot.allMuted);

    before = _bus.sentMessages.count;
    [_system setAllMuted:NO];
    [self assertSentFrom:before isCapture:@"mute-dim" from:48.595249 count:14 refused:@[] monitors:monitors];
    XCTAssertFalse(_system.snapshot.allMuted);
}

#pragma mark - Dim

// Dim, mute-dim, 51.24 s on and 54.77 s off: the level twice, one round of
// 2B to every monitor, then broadcast `2D 00` and `3D 00 00`. 2D is refused.
- (void)testDimIsGLMs {
    NSArray<QLMMonitorState *> *monitors = [self startSystem];
    const uint8_t duckBytes[] = {QLMAddressBroadcast, 0x2D, 0x00};
    NSArray<NSData *> *refused = @[QLMBytes(duckBytes, 3)];

    NSUInteger before = _bus.sentMessages.count;
    [_system setDimmed:YES];
    [self assertSentFrom:before isCapture:@"mute-dim" from:51.240592 count:10 refused:refused monitors:monitors];
    XCTAssertTrue(_system.snapshot.dimmed);

    before = _bus.sentMessages.count;
    [_system setDimmed:NO];
    [self assertSentFrom:before isCapture:@"mute-dim" from:54.774959 count:10 refused:refused monitors:monitors];
    XCTAssertFalse(_system.snapshot.dimmed);
}

@end
