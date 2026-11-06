#import "QLMTestSupport.h"

#include "QLMCommands.h"
#import "QLMTrafficLog.h"

// The rows the traffic window shows. Entries stand in for System's.
@interface QLMTrafficLogTests : XCTestCase
@end

@implementation QLMTrafficLogTests

static QLMTrafficEntry *QLMEntry(uint64_t number, QLMTrafficKind kind, QLMMessage message, uint64_t answers,
                                 const QLMMessage *_Nullable request, NSData *_Nullable hardwareID) {
    return [[QLMTrafficEntry alloc] initWithNumber:number
                                              date:[NSDate dateWithTimeIntervalSinceReferenceDate:0]
                                              kind:kind
                                             bytes:QLMAdapterRecord(&message)
                                           answers:answers
                                           request:request != NULL ? QLMAdapterRecord(request) : nil
                                        hardwareID:hardwareID
                                   ceilingDecibels:-30];
}

// A poll to the fixture's first device and its reply, then a volume frame.
- (NSArray<QLMTrafficEntry *> *)entriesFrom:(uint64_t)first {
    NSData *hardwareID = QLMReadFixtureSetup().devices.firstObject.hardwareID;
    QLMMessage poll = QLMCommandPoll(0x0B);
    return @[
        QLMEntry(first, QLMTrafficRequest, poll, 0, NULL, hardwareID),
        QLMEntry(first + 1, QLMTrafficReply, QLMMakeMessage(0x01, 0x09), first, &poll, hardwareID),
        QLMEntry(first + 2, QLMTrafficRequest, QLMCommandVolume(-30, -30), 0, NULL, nil),
    ];
}

- (void)testARowHasItsWords {
    QLMTrafficLog *log = [[QLMTrafficLog alloc] init];
    log.setup = QLMReadFixtureSetup();
    NSObject *system = [[NSObject alloc] init];
    XCTAssertTrue([log addEntries:[self entriesFrom:1] fromSystem:system]);
    NSArray<QLMTrafficRow *> *rows = log.rows;
    XCTAssertEqual(rows.count, 3u);
    NSString *name = QLMReadFixtureSetup().devices.firstObject.name;
    XCTAssertEqualObjects(rows[0].targetText, ([NSString stringWithFormat:@"session 0B, %@", name]));
    XCTAssertEqualObjects(rows[0].bytesText, @"0B 08");
    XCTAssertEqualObjects(rows[0].descriptionText, @"poll");
    XCTAssertEqualObjects(rows[1].directionText, @"←");
    XCTAssertEqualObjects(rows[1].targetText, rows[0].targetText, @"a reply shows its request's target");
    XCTAssertEqualObjects(rows[1].descriptionText, @"no new telemetry, to #1");
    XCTAssertEqual(rows[1].opcode, 0x08);
    XCTAssertEqualObjects(rows[2].descriptionText, @"volume −30.0 dB, held at the ceiling");
    XCTAssertEqualObjects(rows[2].targetKey, @"FF");
    XCTAssertTrue([rows[2].line hasSuffix:@"→  broadcast FF  FF 1F 04 0C 37  volume −30.0 dB, held at the ceiling"], @"%@", rows[2].line);
}

// A new handler's backlog repeats what the log holds, and a new System
// numbers from 1 again.
- (void)testEntriesAreTakenOnce {
    QLMTrafficLog *log = [[QLMTrafficLog alloc] init];
    NSObject *system = [[NSObject alloc] init];
    [log addEntries:[self entriesFrom:1] fromSystem:system];
    XCTAssertFalse([log addEntries:[self entriesFrom:1] fromSystem:system]);
    XCTAssertEqual(log.rows.count, 3u);
    [log clear];
    XCTAssertFalse([log addEntries:[self entriesFrom:1] fromSystem:system], @"a clear does not bring them back");
    NSObject *next = [[NSObject alloc] init];
    XCTAssertTrue([log addEntries:[self entriesFrom:1] fromSystem:next]);
    XCTAssertEqual(log.rows.count, 3u);
}

- (void)testTheFilters {
    QLMTrafficLog *log = [[QLMTrafficLog alloc] init];
    [log addEntries:[self entriesFrom:1] fromSystem:self];
    XCTAssertEqualObjects(log.opcodes, (@[@0x08, @0x1F]));
    log.direction = QLMTrafficDirectionIn;
    XCTAssertEqual(log.shownRows.count, 1u);
    log.direction = QLMTrafficDirectionOut;
    XCTAssertEqual(log.shownRows.count, 2u);
    log.direction = QLMTrafficDirectionBoth;
    log.opcode = @0x08;
    XCTAssertEqual(log.shownRows.count, 2u, @"a reply goes with its request's opcode");
    log.opcode = nil;
    log.targetKey = @"FF";
    XCTAssertEqual(log.shownRows.count, 1u);
    log.targetKey = log.targets.firstObject[0];
    XCTAssertEqual(log.shownRows.count, 2u);
    [log addEntries:[self entriesFrom:4] fromSystem:self];
    XCTAssertEqual(log.shownRows.count, 4u, @"new rows pass the filters as they come");
}

- (void)testTheLogKeepsItsLimit {
    QLMTrafficLog *log = [[QLMTrafficLog alloc] initWithLimit:10];
    for (uint64_t first = 1; first < 40; first += 3) {
        [log addEntries:[self entriesFrom:first] fromSystem:self];
        XCTAssertLessThanOrEqual(log.rows.count, 10u);
    }
    XCTAssertEqual(log.rows.lastObject.entry.number, 39u);
}

- (void)testTheText {
    QLMTrafficLog *log = [[QLMTrafficLog alloc] init];
    [log addEntries:[self entriesFrom:1] fromSystem:self];
    NSArray<NSString *> *lines = [[QLMTrafficLog textOfRows:log.rows] componentsSeparatedByString:@"\n"];
    XCTAssertEqual(lines.count, 5u, @"a header, three rows, and the last newline");
    XCTAssertTrue([lines[2] containsString:@"#2  ←  session 0B"]);
}

@end
