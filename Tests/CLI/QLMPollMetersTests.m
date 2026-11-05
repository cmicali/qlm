#import <XCTest/XCTest.h>

#include <stdio.h>

#include "QLMReplies.h"
#import "QLMTestSupport.h"

// captures/qlm-poll-meters: what qlmctl poll printed on all six monitors,
// with nothing playing, then with music. Its notes.md, docs/telemetry.md's
// With music, and docs/protocol.md's A host that sends no level cite these.
@interface QLMPollMetersTests : XCTestCase
@end

// One monitor's line of qlmctl poll's output.
@interface QLMPollLine : NSObject
@property (nonatomic) double seconds;
@property (nonatomic, copy) NSString *model;
@property (nonatomic) NSInteger input;
@property (nonatomic) NSInteger hf;
@property (nonatomic) NSInteger lf;
@property (nonatomic) NSInteger sub;  // QLMTelemetryAbsent but on a subwoofer
@property (nonatomic) NSInteger temperature;
// HF, LF, and the subwoofer's sub meter when it has one.
@property (nonatomic, readonly) NSArray<NSNumber *> *outputs;
@end

@implementation QLMPollLine

- (NSArray<NSNumber *> *)outputs {
    return self.sub == QLMTelemetryAbsent ? @[@(self.hf), @(self.lf)] : @[@(self.hf), @(self.lf), @(self.sub)];
}

@end

// Every monitor's line in the run, in order, read once per file. The
// knob's and the mic's lines are left out.
static NSArray<QLMPollLine *> *QLMPollLines(NSString *name) {
    static NSMutableDictionary<NSString *, NSArray<QLMPollLine *> *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSMutableDictionary dictionary];
    });
    @synchronized(cache) {
        if (cache[name] != nil) {
            return cache[name];
        }
        NSString *path = QLMRepositoryPath([@"captures/qlm-poll-meters/" stringByAppendingString:name]);
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        NSMutableArray<QLMPollLine *> *lines = [NSMutableArray array];
        for (NSString *row in [text componentsSeparatedByString:@"\n"]) {
            double seconds = 0;
            unsigned session = 0;
            unsigned long hardwareID = 0;
            char model[16] = "";
            char status[16] = "";
            long temperature = 0, input = 0, hf = 0, lf = 0, sub = 0;
            int read = sscanf(row.UTF8String, " %lf s %x %lu %15s %15s %ld C in %ld hf %ld lf %ld sub %ld", &seconds, &session,
                              &hardwareID, model, status, &temperature, &input, &hf, &lf, &sub);
            if (read != 10 || strcmp(status, "on") != 0) {
                continue;
            }
            QLMPollLine *line = [[QLMPollLine alloc] init];
            line.seconds = seconds;
            line.model = @(model);
            line.temperature = temperature;
            line.input = input;
            line.hf = hf;
            line.lf = lf;
            line.sub = sub;
            [lines addObject:line];
        }
        cache[name] = lines;
        return lines;
    }
}

@implementation QLMPollMetersTests

- (NSArray<QLMPollLine *> *)linesOf:(NSString *)name {
    NSArray<QLMPollLine *> *lines = QLMPollLines(name);
    // Six monitors, 18 frames each, over 10 s.
    XCTAssertEqual(lines.count, 108u, @"%@", name);
    return lines;
}

// With nothing playing, every output reads its floor, but the first 8330A's
// HF, 2 or 3 counts above it. Each input rests at its model's floor, all
// at 161 or below, under QLMTelemetryInputSignal.
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
        XCTAssertLessThan(line.input, QLMTelemetryInputSignal);
        for (NSNumber *output in line.outputs) {
            XCTAssertGreaterThanOrEqual(output.integerValue, QLMTelemetryOutputSilent);
            XCTAssertLessThanOrEqual(output.integerValue, QLMTelemetryOutputSilent + 3);
            aboveFloor += output.integerValue > QLMTelemetryOutputSilent ? 1 : 0;
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
        XCTAssertGreaterThanOrEqual(line.input, QLMTelemetryInputSignal);
        NSArray<NSNumber *> *outputs = line.outputs;
        BOOL early = [line.model isEqualToString:@"8351B"] || [line.model isEqualToString:@"7370A"];
        if (line.seconds >= (early ? 1.77 : 2.38)) {
            for (NSNumber *output in outputs) {
                XCTAssertEqual(output.integerValue, QLMTelemetryOutputSilent, @"%@ at %.2f s", line.model, line.seconds);
            }
            continue;
        }
        // The subwoofers send music on LF alone.
        NSArray<NSNumber *> *playing = line.sub == QLMTelemetryAbsent ? outputs : @[@(line.lf)];
        for (NSNumber *output in playing) {
            highest = MAX(highest, output.integerValue);
            lowestPlaying = MIN(lowestPlaying, output.integerValue);
        }
    }
    XCTAssertEqual(highest, 240);
    XCTAssertEqual(lowestPlaying, 221);
    XCTAssertLessThanOrEqual(highest, 0xFF);
    XCTAssertGreaterThanOrEqual(highest - QLMTelemetryOutputSilent, 100);
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
