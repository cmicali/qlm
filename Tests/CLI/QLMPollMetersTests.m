#import <XCTest/XCTest.h>

#import "QLMFormat.h"
#import "QLMTestSupport.h"

// captures/qlm-poll-meters: what qlmctl poll printed on all six monitors,
// with nothing playing, then with music. Its notes.md, docs/telemetry.md's
// The meters, and docs/protocol.md's A host that sends no level cite these.
@interface QLMPollMetersTests : XCTestCase
@end

// One monitor's line of qlmctl poll's output.
@interface QLMPollLine : NSObject
@property (nonatomic) double seconds;
@property (nonatomic, copy) NSString *model;
@property (nonatomic) NSInteger input;
@property (nonatomic) NSInteger hf;
@property (nonatomic) NSInteger lf;
@property (nonatomic) NSInteger sub;
@property (nonatomic) NSInteger temperature;
@end

@implementation QLMPollLine
@end

@implementation QLMPollMetersTests

// Every monitor's line in the run, in order. The knob's and the mic's lines
// are left out.
- (NSArray<QLMPollLine *> *)linesOf:(NSString *)name {
    NSString *path = QLMRepositoryPath([@"captures/qlm-poll-meters/" stringByAppendingString:name]);
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(text, @"%@", path);
    NSMutableArray<QLMPollLine *> *lines = [NSMutableArray array];
    for (NSString *row in [text componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *fields = [[row componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (fields.count < 18 || ![fields[5] isEqualToString:@"on"]) {
            continue;
        }
        XCTAssertEqualObjects(fields[8], @"in", @"%@", row);
        XCTAssertEqualObjects(fields[10], @"hf", @"%@", row);
        XCTAssertEqualObjects(fields[12], @"lf", @"%@", row);
        XCTAssertEqualObjects(fields[14], @"sub", @"%@", row);
        QLMPollLine *line = [[QLMPollLine alloc] init];
        line.seconds = fields[0].doubleValue;
        line.model = fields[4];
        line.temperature = fields[6].integerValue;
        line.input = fields[9].integerValue;
        line.hf = fields[11].integerValue;
        line.lf = fields[13].integerValue;
        line.sub = fields[15].integerValue;
        [lines addObject:line];
    }
    // Six monitors, 18 frames each, over 10 s.
    XCTAssertEqual(lines.count, 108u, @"%@", name);
    return lines;
}

- (NSArray<NSNumber *> *)outputsOf:(QLMPollLine *)line {
    NSMutableArray<NSNumber *> *outputs = [NSMutableArray arrayWithObjects:@(line.hf), @(line.lf), nil];
    if (line.sub != QLMMonitorValueAbsent) {
        [outputs addObject:@(line.sub)];
    }
    return outputs;
}

// With nothing playing, every output reads its floor, 80, but the first
// 8330A's HF, 2 or 3 counts above it. Each input rests at its model's
// floor, all at 161 or below.
- (void)testWithNothingPlayingEachMeterRestsAtItsFloor {
    NSDictionary<NSString *, NSArray<NSNumber *> *> *floors = @{
        @"8330A": @[@157, @160],
        @"8351B": @[@158, @161],
        @"7370A": @[@147, @149],
        @"7350A": @[@146, @148],
    };
    NSUInteger aboveFloor = 0;
    for (QLMPollLine *line in [self linesOf:@"poll-silent.txt"]) {
        NSArray<NSNumber *> *range = floors[line.model];
        XCTAssertNotNil(range, @"%@", line.model);
        XCTAssertGreaterThanOrEqual(line.input, range[0].integerValue, @"%@ at %.2f s", line.model, line.seconds);
        XCTAssertLessThanOrEqual(line.input, range[1].integerValue, @"%@ at %.2f s", line.model, line.seconds);
        XCTAssertEqual(QLMInputSignalOf(line.input), QLMInputSignalNone);
        for (NSNumber *output in [self outputsOf:line]) {
            XCTAssertGreaterThanOrEqual(output.integerValue, 128);
            XCTAssertLessThanOrEqual(output.integerValue, 131);
            aboveFloor += output.integerValue > 128 ? 1 : 0;
        }
    }
    XCTAssertEqual(aboveFloor, 18u);  // the first 8330A's HF, in every frame
}

// With music, the outputs read up to 240, about 100 counts over the floor,
// and the input 252 in every frame. Then every output falls to its floor,
// from the frame at 1.77 s on the 8351Bs and the 7370A, and from 2.38 s on
// the rest, while the input still reads the music.
- (void)testWithMusicTheOutputsFallSilentWhileTheInputStaysAt252 {
    NSInteger highest = 0;
    NSInteger lowestPlaying = 255;
    for (QLMPollLine *line in [self linesOf:@"poll-music.txt"]) {
        XCTAssertEqual(line.input, 252, @"%@ at %.2f s", line.model, line.seconds);
        XCTAssertEqual(QLMInputSignalOf(line.input), QLMInputSignalPresent);
        BOOL early = [line.model isEqualToString:@"8351B"] || [line.model isEqualToString:@"7370A"];
        BOOL silent = line.seconds >= (early ? 1.77 : 2.38);
        if (silent) {
            XCTAssertEqualObjects([self outputsOf:line], [self outputsOf:line].count == 3 ? (@[@128, @128, @128]) : (@[@128, @128]),
                                  @"%@ at %.2f s", line.model, line.seconds);
            continue;
        }
        // The subwoofers send music on LF alone.
        NSArray<NSNumber *> *playing = line.sub == QLMMonitorValueAbsent ? [self outputsOf:line] : @[@(line.lf)];
        for (NSNumber *output in playing) {
            highest = MAX(highest, output.integerValue);
            lowestPlaying = MIN(lowestPlaying, output.integerValue);
        }
    }
    XCTAssertEqual(highest, 240);
    XCTAssertEqual(lowestPlaying, 221);
    XCTAssertLessThanOrEqual(highest - 0x80, QLMOutputMeterSpan);
    XCTAssertGreaterThanOrEqual(highest - 0x80, 100);
}

// The temperatures held: 29 to 31 °C on the 8330As, 43 to 47 °C on the rest.
- (void)testTheTemperaturesWereSteady {
    for (NSString *name in @[@"poll-silent.txt", @"poll-music.txt"]) {
        for (QLMPollLine *line in [self linesOf:name]) {
            BOOL small = [line.model isEqualToString:@"8330A"];
            XCTAssertGreaterThanOrEqual(line.temperature, small ? 29 : 43, @"%@", line.model);
            XCTAssertLessThanOrEqual(line.temperature, small ? 31 : 47, @"%@", line.model);
        }
    }
}

@end
