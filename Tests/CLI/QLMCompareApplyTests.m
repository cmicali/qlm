#import <XCTest/XCTest.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>

#import "QLMCompareApply.h"
#import "QLMSetupReader.h"
#import "QLMTestSupport.h"

// qlmctl compare-apply. Its passes and comparison are the DSP block golden
// tests', so these check the verb around them: its match on a capture and
// the fixture, the one frame a changed band moves, its window, and its exit
// codes. Every capture here is Main 2x1's apply at startup, in startup-idle.
@interface QLMCompareApplyTests : XCTestCase
@end

@implementation QLMCompareApplyTests {
    NSString *_changedCopy;
}

- (void)tearDown {
    if (_changedCopy != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:_changedCopy error:NULL];
    }
    [super tearDown];
}

static NSString *QLMStartupIdle(void) {
    return QLMRepositoryPath(@"captures/startup-idle/reports.txt");
}

- (int)run:(NSArray<NSString *> *)arguments output:(NSString **)output errors:(NSString **)errors {
    char *outText = NULL;
    char *errText = NULL;
    size_t outLength = 0;
    size_t errLength = 0;
    FILE *out = open_memstream(&outText, &outLength);
    FILE *err = open_memstream(&errText, &errLength);
    int status = QLMCompareApply(arguments, out, err);
    fclose(out);
    fclose(err);
    *output = [[NSString alloc] initWithBytes:outText length:outLength encoding:NSUTF8StringEncoding];
    *errors = [[NSString alloc] initWithBytes:errText length:errLength encoding:NSUTF8StringEncoding];
    free(outText);
    free(errText);
    return status;
}

- (NSArray<NSString *> *)lines:(NSString *)text starting:(NSString *)prefix {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:prefix]) {
            [lines addObject:line];
        }
    }
    return lines;
}

// A temporary copy of the fixture with Main 2x1's Left 8351B's second
// peaking band at -3.27 dB, not -6.27 dB. It goes to slot 5.
- (NSString *)changedCopy {
    NSString *text = [NSString stringWithContentsOfFile:QLMFixturePath(@"Main.sam") encoding:NSUTF8StringEncoding error:NULL];
    NSUInteger at = [text rangeOfString:@"Group_Name:Main 2x1\r\n"].location;
    XCTAssertNotEqual(at, (NSUInteger)NSNotFound);
    for (NSString *mark in @[@"Serial:1000002\r\n", @"Notch:2\r\n", @"Gain:-6.27\r\n"]) {
        at = [text rangeOfString:mark options:0 range:NSMakeRange(at, text.length - at)].location;
        XCTAssertNotEqual(at, (NSUInteger)NSNotFound, @"%@", mark);
    }
    NSString *changed = [text stringByReplacingCharactersInRange:NSMakeRange(at, 10) withString:@"Gain:-3.27"];
    _changedCopy = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    _changedCopy = [_changedCopy stringByAppendingPathExtension:@"sam"];
    XCTAssertTrue([changed writeToFile:_changedCopy atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    return _changedCopy;
}

- (void)testACaptureMatchesTheSetupItWasAppliedFrom {
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), QLMStartupIdle()] output:&output errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertEqualObjects(errors, @"");
    XCTAssertTrue([output containsString:@"\n6 of 6 passes match, apart from"], @"%@", output);
    XCTAssertEqual([self lines:output starting:@"  GLM"].count, 0u);
    XCTAssertEqual([self lines:output starting:@"  qlm"].count, 0u);
    XCTAssertEqual([self lines:output starting:@"  left out   05 04 00 00 00 FF FF EA 00 01 90 00 02 DA"].count, 6u);
    XCTAssertEqual([self lines:output starting:@"  left out   43 00 02"].count, 2u);
    XCTAssertEqual([self lines:output starting:@"  left out   4B 00 00 00 01"].count, 2u);
}

- (void)testAChangedBandIsTheOneFrameThatDiffers {
    NSString *copy = [self changedCopy];
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[copy, QLMStartupIdle(), @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\n5 of 6 passes match. 1 differs.\n"], @"%@", output);
    NSArray<NSString *> *glm = [self lines:output starting:@"  GLM"];
    NSArray<NSString *> *qlm = [self lines:output starting:@"  qlm"];
    XCTAssertEqual(glm.count, 1u, @"%@", output);
    XCTAssertEqual(qlm.count, 1u, @"%@", output);
    XCTAssertTrue([glm.firstObject hasPrefix:@"  GLM        10 0E 05 "], @"%@", glm);
    XCTAssertTrue([qlm.firstObject hasPrefix:@"  qlm        10 0E 05 "], @"%@", qlm);
    XCTAssertEqual([self lines:output starting:@"  not sent"].count, 0u);

    QLMSetup *setup = [QLMSetupReader readFileAtPath:copy error:NULL];
    QLMSetupGroup *group = [setup groupNamed:@"Main 2x1"];
    XCTAssertNotNil(group);
    NSArray<QLMPassMatch *> *matches =
        QLMMatchPasses(QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY), setup, @[group], NULL);
    NSUInteger differing = 0;
    for (QLMPassMatch *match in matches) {
        if (match.comparison.matches) {
            continue;
        }
        differing += 1;
        XCTAssertEqualObjects(match.node.serial, @"1000002");
        QLMBlockComparison *comparison = match.comparison;
        XCTAssertEqual(comparison.differenceCount, 1u);
        XCTAssertEqualObjects([comparison.changed.firstObject.firstObject subdataWithRange:NSMakeRange(0, 3)],
                              QLMBytes((const uint8_t[]){0x10, 0x0E, 0x05}, 3));
    }
    XCTAssertEqual(differing, 1u);
}

- (void)testTheWindowPicksThePasses {
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY);
    XCTAssertEqual(passes.count, 6u);
    NSString *from = [NSString stringWithFormat:@"%f", passes[1].time];
    NSString *to = [NSString stringWithFormat:@"%f", passes[2].time];
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), QLMStartupIdle(), @"--from", from, @"--to", to] output:&output errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\n1 of 1 pass match, apart from"], @"%@", output);
}

// A wrong flag, a bus's among them, refuses before either file is read.
- (void)testAnArgumentItDoesNotKnowIsAUsageError {
    NSString *setup = QLMFixturePath(@"Main.sam");
    NSString *capture = QLMStartupIdle();
    NSArray<NSArray<NSString *> *> *cases = @[
        @[],
        @[setup],
        @[setup, capture, capture],
        @[setup, capture, @"--fake"],
        @[setup, @"--replay", capture],
        @[setup, capture, @"--dry-run"],
        @[setup, capture, @"--ceiling", @"-40"],
        @[setup, capture, @"--unverified-rate"],
        @[setup, capture, @"--group"],
        @[setup, capture, @"--from", @"1", @"--from", @"2"],
        @[setup, capture, @"--from", @"soon"],
        @[setup, capture, @"--to", @"-1"],
        @[setup, capture, @"--from", @"9", @"--to", @"8"],
    ];
    for (NSArray<NSString *> *arguments in cases) {
        NSString *output = nil;
        NSString *errors = nil;
        XCTAssertEqual([self run:arguments output:&output errors:&errors], EX_USAGE, @"%@", arguments);
        XCTAssertEqualObjects(output, @"", @"%@", arguments);
        XCTAssertTrue([errors containsString:@"opens no bus"], @"%@: %@", arguments, errors);
    }
}

- (void)testAFileItCannotUseIsADataError {
    NSString *setup = QLMFixturePath(@"Main.sam");
    NSString *capture = QLMStartupIdle();
    NSArray<NSArray<NSString *> *> *cases = @[
        @[QLMFixturePath(@"Missing.sam"), capture],
        @[capture, capture],
        @[setup, QLMRepositoryPath(@"captures/missing/reports.txt")],
        @[setup, setup],
        @[setup, capture, @"--group", @"Main 9x9"],
        @[setup, capture, @"--from", @"100000"],
    ];
    for (NSArray<NSString *> *arguments in cases) {
        NSString *output = nil;
        NSString *errors = nil;
        XCTAssertEqual([self run:arguments output:&output errors:&errors], EX_DATAERR, @"%@", arguments);
        XCTAssertEqualObjects(output, @"", @"%@", arguments);
        XCTAssertTrue([errors hasPrefix:@"qlmctl: "], @"%@: %@", arguments, errors);
    }
}

@end
