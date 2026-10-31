#import <XCTest/XCTest.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>

#import "QLMCompareApply.h"
#include "QLMReport.h"
#import "QLMSetupReader.h"
#import "QLMTestSupport.h"

// qlmctl compare-apply. Its passes and comparison are the DSP block golden
// tests', so these check the verb around them: its match on a capture and
// the fixture, the one frame a changed band moves, a node two monitors
// match, every generator stop, a pass GLM cut short, its window, and its
// exit codes. A setup or a capture a test changes is a temporary file,
// never committed.
@interface QLMCompareApplyTests : XCTestCase
@end

@implementation QLMCompareApplyTests {
    NSMutableArray<NSString *> *_temporaryFiles;
}

- (void)setUp {
    [super setUp];
    _temporaryFiles = [NSMutableArray array];
}

- (void)tearDown {
    for (NSString *path in _temporaryFiles) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
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

- (NSString *)temporaryFile:(NSString *)text extension:(NSString *)extension {
    NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] stringByAppendingPathExtension:extension];
    XCTAssertTrue([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    [_temporaryFiles addObject:path];
    return path;
}

// A copy of the fixture with one band's gain changed: the first `Gain:old`
// after the group's name, the node's serial, and the band's line.
- (NSString *)fixtureWithGroup:(NSString *)group serial:(NSString *)serial band:(NSString *)band gain:(NSString *)old to:(NSString *)gain {
    NSString *text = [NSString stringWithContentsOfFile:QLMFixturePath(@"Main.sam") encoding:NSUTF8StringEncoding error:NULL];
    NSUInteger at = 0;
    NSString *line = nil;
    for (NSString *mark in @[[@"Group_Name:" stringByAppendingString:group], [@"Serial:" stringByAppendingString:serial], band,
                             [@"Gain:" stringByAppendingString:old]]) {
        line = [mark stringByAppendingString:@"\r\n"];
        at = [text rangeOfString:line options:0 range:NSMakeRange(at, text.length - at)].location;
        XCTAssertNotEqual(at, (NSUInteger)NSNotFound, @"%@", mark);
    }
    text = [text stringByReplacingCharactersInRange:NSMakeRange(at, line.length) withString:[NSString stringWithFormat:@"Gain:%@\r\n", gain]];
    return [self temporaryFile:text extension:@"sam"];
}

// A capture of these frames only, as the address byte, then the payload,
// 1 ms apart. It holds no reply, so no lease and no model. GLM's refused
// frames are among them, so they are framed with no allowlist.
- (NSString *)captureOf:(NSArray<NSData *> *)records {
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < records.count; i++) {
        const uint8_t *bytes = records[i].bytes;
        NSData *frame = QLMUncheckedFrame(QLMMessageMake(bytes[0], bytes + 1, records[i].length - 1));
        uint8_t report[QLMReportLength] = {(uint8_t)(QLMReportOutputPrefix | frame.length)};
        memcpy(report + 1, frame.bytes, frame.length);
        [text appendFormat:@"%.6f out", 1 + i * 0.001];
        for (NSUInteger j = 0; j < sizeof report; j++) {
            [text appendFormat:@" %02X", report[j]];
        }
        [text appendString:@"\n"];
    }
    return [self temporaryFile:text extension:@"txt"];
}

static NSData *QLMRecord(uint8_t session, NSData *payload) {
    NSMutableData *record = [NSMutableData dataWithBytes:&session length:1];
    [record appendData:payload];
    return record;
}

static NSString *QLMHexOf(NSData *payload) {
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSUInteger i = 0; i < payload.length; i++) {
        [pairs addObject:[NSString stringWithFormat:@"%02X", ((const uint8_t *)payload.bytes)[i]]];
    }
    return [pairs componentsJoinedByString:@" "];
}

// startup-idle's pass to the Left 8351B, at session 03.
static QLMCapturedPass *QLMLeftPass(void) {
    QLMCapturedPass *pass = QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY, NULL, NULL)[1];
    return pass;
}

- (void)testACaptureMatchesTheSetupItWasAppliedFrom {
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), QLMStartupIdle(), @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertEqualObjects(errors, @"");
    XCTAssertTrue([output containsString:@"\n6 of 6 generator stops are the known 05 04 00 00 00 FF FF EA 00 01 90 00 02 DA.\n"], @"%@", output);
    XCTAssertTrue([output containsString:@"\n6 of 6 passes match, apart from"], @"%@", output);
    XCTAssertEqual([self lines:output starting:@"  GLM"].count, 0u);
    XCTAssertEqual([self lines:output starting:@"  qlm"].count, 0u);
    XCTAssertEqual([self lines:output starting:@"  left out   43 00 02"].count, 2u);
    XCTAssertEqual([self lines:output starting:@"  left out   4B 00 00 00 01"].count, 2u);
}

- (void)testAChangedBandIsTheOneFrameThatDiffers {
    NSString *copy = [self fixtureWithGroup:@"Main 2x1" serial:@"1000002" band:@"Notch:2" gain:@"-6.27" to:@"-3.27"];
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[copy, QLMStartupIdle(), @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\n5 of 6 passes match. 1 differs, and 0 generator stops differ.\n"], @"%@", output);
    NSArray<NSString *> *glm = [self lines:output starting:@"  GLM"];
    NSArray<NSString *> *qlm = [self lines:output starting:@"  qlm"];
    XCTAssertEqual(glm.count, 1u, @"%@", output);
    XCTAssertEqual(qlm.count, 1u, @"%@", output);
    XCTAssertTrue([glm.firstObject hasPrefix:@"  GLM        10 0E 05 "], @"%@", glm);
    XCTAssertTrue([qlm.firstObject hasPrefix:@"  qlm        10 0E 05 "], @"%@", qlm);
    XCTAssertEqual([self lines:output starting:@"  not sent"].count, 0u);

    QLMSetup *setup = [QLMSetupReader readFileAtPath:copy error:NULL];
    NSArray<QLMPassMatch *> *matches =
        QLMMatchPasses(QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY, NULL, NULL), setup, [setup groupNamed:@"Main 2x1"], NULL);
    NSUInteger differing = 0;
    for (QLMPassMatch *match in matches) {
        if (match.matches) {
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

// Group_4 holds the 7370A's node exactly as Main 4x2 does. A change to Main
// 4x2's alone still differs, since only the named group's nodes count.
- (void)testANearCopyInAnotherGroupHidesNothing {
    NSString *copy = [self fixtureWithGroup:@"Main 4x2" serial:@"1000006" band:@"Notch:1" gain:@"-7.33" to:@"-4.33"];
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[copy, QLMRepositoryPath(@"captures/standby-wake/reports.txt"), @"--group", @"Main 4x2"] output:&output
                    errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"7370A 1000006 \"Sub\": 1 difference\n"], @"%@", output);
    NSArray<NSString *> *glm = [self lines:output starting:@"  GLM"];
    XCTAssertEqual(glm.count, 1u, @"%@", output);
    XCTAssertTrue([glm.firstObject hasPrefix:@"  GLM        10 0E 00 "], @"%@", glm);
}

// Two sessions with one node's block are two monitors given one monitor's
// settings, so the second can't match.
- (void)testTwoMonitorsCannotShareANode {
    NSMutableArray<NSData *> *records = [NSMutableArray array];
    for (NSNumber *session in @[@0x03, @0x06]) {
        for (NSData *payload in QLMLeftPass().payloads) {
            [records addObject:QLMRecord(session.unsignedCharValue, payload)];
        }
    }
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), [self captureOf:records], @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"session 06  8351B 1000002 \"Left\": the same block, but session 03's pass at 1.000 s took this node first\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"\n1 of 2 passes match. 1 differs, and 0 generator stops differ.\n"], @"%@", output);
}

// A stop to a monitor that gets no pass, as a switch sends the monitors off
// in the new group, is checked too.
- (void)testEveryGeneratorStopIsChecked {
    NSData *known = QLMBytes((const uint8_t[]){0x05, 0x04, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xEA, 0x00, 0x01, 0x90, 0x00, 0x02, 0xDA}, 14);
    NSMutableData *odd = [known mutableCopy];
    ((uint8_t *)odd.mutableBytes)[13] = 0xDB;
    NSMutableArray<NSData *> *records = [NSMutableArray arrayWithObjects:QLMRecord(0x08, odd), QLMRecord(0x03, known), nil];
    for (NSData *payload in QLMLeftPass().payloads) {
        [records addObject:QLMRecord(0x03, payload)];
    }
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), [self captureOf:records], @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"   1.000 s  session 08  a generator stop qlm doesn't know\n"
                                         @"  GLM only   05 04 00 00 00 FF FF EA 00 01 90 00 02 DB\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"\n1 of 2 generator stops are the known"], @"%@", output);
    XCTAssertTrue([output containsString:@"\n1 of 1 pass match. 0 differ, and 1 generator stop differs.\n"], @"%@", output);
}

// GLM cut the 7350A's pass at session 10 short when it leased the monitor
// again as 13. The short pass is the block's start, so it matches.
- (void)testAPassGLMCutShortMatchesTheBlocksStart {
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMRepositoryPath(@"captures/setup-b-peq-8351b/setups/1.sam"),
                             QLMRepositoryPath(@"captures/setup-b-peq-8351b/reports.txt"), @"--group", @"Main 4x2", @"--from", @"181",
                             @"--to", @"290"]
                    output:&output
                    errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@" 183.450 s  session 10  7350A 1000007 \"Center 7350A\": cut short by GLM, and matches the block's start\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"\n9 of 9 passes match, apart from"], @"%@", output);
}

// A pass cut short still shows a frame it sent that differs, and no frame
// past the cut.
- (void)testACutPassStillShowsAChangedFrame {
    NSArray<NSData *> *payloads = QLMLeftPass().payloads;
    NSMutableArray<NSData *> *records = [NSMutableArray array];
    for (NSUInteger i = 0; i < 10; i++) {
        NSMutableData *payload = [payloads[i] mutableCopy];
        if (i == 9) {
            ((uint8_t *)payload.mutableBytes)[payload.length - 2] ^= 0x01;
        }
        [records addObject:QLMRecord(0x03, payload)];
    }
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), [self captureOf:records], @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"session 03  8351B 1000002 \"Left\": 1 difference\n"], @"%@", output);
    XCTAssertEqual([self lines:output starting:@"  GLM        10 0E 04"].count, 1u, @"%@", output);
    XCTAssertEqual([self lines:output starting:@"  qlm only"].count, 0u, @"%@", output);
    XCTAssertEqual([self lines:output starting:@"  not sent"].count, 0u, @"%@", output);
}

- (void)testTheWindowPicksThePasses {
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY, NULL, NULL);
    XCTAssertEqual(passes.count, 6u);
    NSString *from = [NSString stringWithFormat:@"%f", passes[1].time];
    NSString *to = [NSString stringWithFormat:@"%f", passes[2].time];
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), QLMStartupIdle(), @"--group", @"Main 2x1", @"--from", from, @"--to", to]
                    output:&output
                    errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\n1 of 1 pass match, apart from"], @"%@", output);
}

// GLM sends each subwoofer its 3B before its pass, with the generator stop
// (startup-idle, 8.841 and 9.133 s). No pass holds it, so it's listed at
// the top, and counts only with --strict-outside.
- (void)testAFrameBeforeAnyPassIsListedAtTheTop {
    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), QLMStartupIdle(), @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\nGLM, outside a pass, before its session's first pass in the window\n"
                                         @"       8.841 s  session 05  3B 00 3C\n"
                                         @"       9.133 s  session 07  3B 00 3C\n\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"\n2 DSP frames outside a pass, 0 of them a band as its block sends it. "
                                         @"They don't count without --strict-outside.\n"],
                  @"%@", output);

    status = [self run:@[QLMFixturePath(@"Main.sam"), QLMStartupIdle(), @"--group", @"Main 2x1", @"--strict-outside"] output:&output
                errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\n6 of 6 passes match. 0 differ, 0 generator stops differ, and 2 outside a pass differ.\n"],
                  @"%@", output);
}

// A band GLM sends after a pass closes, as it does while its editor is
// open, is listed under the pass with its slot. With --strict-outside, one
// that is its slot as the block sends it passes, and one that isn't fails.
- (void)testABandAfterAPassIsListedUnderIt {
    QLMSetupGroup *group = QLMFixtureGroup(@"Main 2x1");
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:[group nodeWithSerial:@"1000002"] inGroup:group error:NULL];
    NSData *band = QLMBlockBand(block, QLMBytes((const uint8_t[]){0x10, 0x0E, 0x05}, 3));
    XCTAssertEqual(band.length, 24u);
    NSMutableData *edited = [band mutableCopy];
    ((uint8_t *)edited.mutableBytes)[edited.length - 2] ^= 0x01;

    for (NSData *sent in @[band, edited]) {
        NSMutableArray<NSData *> *records = [NSMutableArray array];
        for (NSData *payload in QLMLeftPass().payloads) {
            [records addObject:QLMRecord(0x03, payload)];
        }
        [records addObject:QLMRecord(0x03, sent)];
        BOOL same = [sent isEqualToData:band];
        NSString *output = nil;
        NSString *errors = nil;
        int status = [self run:@[QLMFixturePath(@"Main.sam"), [self captureOf:records], @"--group", @"Main 2x1", @"--strict-outside"]
                        output:&output
                        errors:&errors];
        XCTAssertEqual(status, same ? 0 : QLMCompareApplyDiffers, @"%@%@", output, errors);
        NSString *listed = [NSString stringWithFormat:@"  GLM, outside a pass\n  %10.3f s  slot 05, %@\n                %@\n",
                                                      1 + QLMLeftPass().payloads.count * 0.001,
                                                      same ? @"as the block sends it" : @"not as the block sends it", QLMHexOf(sent)];
        NSRange at = [output rangeOfString:listed];
        XCTAssertNotEqual(at.location, (NSUInteger)NSNotFound, @"%@\n%@", listed, output);
        XCTAssertLessThan([output rangeOfString:@"session 03  8351B 1000002 \"Left\": matches\n"].location, at.location, @"%@", output);
        status = [self run:@[QLMFixturePath(@"Main.sam"), [self captureOf:records], @"--group", @"Main 2x1"] output:&output errors:&errors];
        XCTAssertEqual(status, 0, @"%@%@", output, errors);
    }
}

// Phase 0's captures lease monitors again at new sessions, so a session's
// model holds only for a while. A window whose 39 replies give one session
// two models is refused. This copy of startup-idle adds, at 200 s, the
// 8330A's reply to 39 at 8.497 s, as session 03's, the Left 8351B's. A
// window that ends before it shows one model, and is compared.
- (void)testASessionWithTwoModelsIsRefused {
    NSString *text = [NSString stringWithContentsOfFile:QLMStartupIdle() encoding:NSUTF8StringEncoding error:NULL];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger ask = [lines indexOfObjectPassingTest:^BOOL(NSString *line, NSUInteger i, BOOL *stop) {
        return [line containsString:@" out 85 03 39 "];
    }];
    NSUInteger other = [lines indexOfObjectPassingTest:^BOOL(NSString *line, NSUInteger i, BOOL *stop) {
        return [line containsString:@" out 85 02 39 "];
    }];
    XCTAssertTrue([lines[other + 1] containsString:@" in 3F 01 09 63 2D 32 3B 6D 6F 64 65 6C 2D 38 33 33 30 41 "]);
    XCTAssertTrue([lines[other + 2] containsString:@" in "]);
    NSMutableString *doctored = [text mutableCopy];
    NSArray<NSString *> *added = @[lines[ask], lines[other + 1], lines[other + 2]];
    for (NSUInteger i = 0; i < added.count; i++) {
        NSString *line = added[i];
        [doctored appendFormat:@"%.6f%@\n", 200 + i * 0.001, [line substringFromIndex:[line rangeOfString:@" "].location]];
    }
    NSString *path = [self temporaryFile:doctored extension:@"txt"];

    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), path, @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, EX_DATAERR, @"%@%@", output, errors);
    XCTAssertEqualObjects(output, @"");
    XCTAssertTrue([errors containsString:@"session 03 answers 39 as the 8351B at 8.502 s and as the 8330A at 200.000 s"], @"%@", errors);

    NSString *problem = nil;
    QLMCapture *capture = [QLMCapture captureWithContentsOfFile:path error:NULL];
    XCTAssertNil(QLMPassesInCapture(capture, 0, INFINITY, NULL, &problem));
    XCTAssertNotNil(problem);
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(capture, 0, 199, NULL, &problem);
    XCTAssertEqual(passes.count, 6u);
    XCTAssertEqualObjects(passes[1].model, @"8351B");
    passes = QLMPassesInCapture(capture, 8.6, 8.7, NULL, &problem);
    XCTAssertEqual(passes.count, 1u);
    XCTAssertEqualObjects(passes[0].model, @"8351B", @"a window with no reply takes the nearest, at 8.735 s");

    status = [self run:@[QLMFixturePath(@"Main.sam"), path, @"--group", @"Main 2x1", @"--to", @"199"] output:&output errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
}

// A wrong flag, a bus's among them, or no group refuses before either file
// is read.
- (void)testAnArgumentItDoesNotKnowIsAUsageError {
    NSString *setup = QLMFixturePath(@"Main.sam");
    NSString *capture = QLMStartupIdle();
    NSArray<NSArray<NSString *> *> *cases = @[
        @[],
        @[setup],
        @[setup, capture],
        @[setup, capture, @"--from", @"1"],
        @[setup, capture, capture, @"--group", @"Main 2x1"],
        @[setup, capture, @"--group", @"Main 2x1", @"--fake"],
        @[setup, @"--replay", capture, @"--group", @"Main 2x1"],
        @[setup, capture, @"--group", @"Main 2x1", @"--dry-run"],
        @[setup, capture, @"--group", @"Main 2x1", @"--ceiling", @"-40"],
        @[setup, capture, @"--group", @"Main 2x1", @"--unverified-rate"],
        @[setup, capture, @"--group", @"Main 2x1", @"--strict-outside", @"--strict-outside"],
        @[setup, capture, @"--group"],
        @[setup, capture, @"--group", @"Main 2x1", @"--from", @"1", @"--from", @"2"],
        @[setup, capture, @"--group", @"Main 2x1", @"--from", @"soon"],
        @[setup, capture, @"--group", @"Main 2x1", @"--to", @"-1"],
        @[setup, capture, @"--group", @"Main 2x1", @"--from", @"9", @"--to", @"8"],
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
        @[QLMFixturePath(@"Missing.sam"), capture, @"--group", @"Main 2x1"],
        @[capture, capture, @"--group", @"Main 2x1"],
        @[setup, QLMRepositoryPath(@"captures/missing/reports.txt"), @"--group", @"Main 2x1"],
        @[setup, setup, @"--group", @"Main 2x1"],
        @[setup, capture, @"--group", @"Main 9x9"],
        @[setup, capture, @"--group", @"Main 2x1", @"--from", @"100000"],
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
