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

// These frames as a capture's output reports, each the address byte, then
// the payload, 1 ms apart from `start`. They hold no reply. GLM's refused
// frames are among them, so they are framed with no allowlist.
static NSString *QLMReportLines(NSArray<NSData *> *records, NSTimeInterval start) {
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < records.count; i++) {
        const uint8_t *bytes = records[i].bytes;
        NSData *frame = QLMUncheckedFrame(QLMMessageMake(bytes[0], bytes + 1, records[i].length - 1));
        uint8_t report[QLMReportLength] = {(uint8_t)(QLMReportOutputPrefix | frame.length)};
        memcpy(report + 1, frame.bytes, frame.length);
        [text appendFormat:@"%.6f out", start + i * 0.001];
        for (NSUInteger j = 0; j < sizeof report; j++) {
            [text appendFormat:@" %02X", report[j]];
        }
        [text appendString:@"\n"];
    }
    return text;
}

// A capture of these frames only, from 1 s, so no lease and no model.
- (NSString *)captureOf:(NSArray<NSData *> *)records {
    return [self temporaryFile:QLMReportLines(records, 1) extension:@"txt"];
}

// startup-idle with these frames after its end, from 200 s.
- (NSString *)startupIdleThen:(NSString *)lines {
    NSString *text = [NSString stringWithContentsOfFile:QLMStartupIdle() encoding:NSUTF8StringEncoding error:NULL];
    return [self temporaryFile:[text stringByAppendingString:lines] extension:@"txt"];
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
    QLMCapturedPass *pass = QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY, NULL)[1];
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
    XCTAssertEqual([self lines:output starting:@"  GLM "].count, 0u);
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
    NSArray<NSString *> *glm = [self lines:output starting:@"  GLM "];
    NSArray<NSString *> *qlm = [self lines:output starting:@"  qlm"];
    XCTAssertEqual(glm.count, 1u, @"%@", output);
    XCTAssertEqual(qlm.count, 1u, @"%@", output);
    XCTAssertTrue([glm.firstObject hasPrefix:@"  GLM        10 0E 05 "], @"%@", glm);
    XCTAssertTrue([qlm.firstObject hasPrefix:@"  qlm        10 0E 05 "], @"%@", qlm);
    XCTAssertEqual([self lines:output starting:@"  not sent"].count, 0u);

    QLMSetup *setup = [QLMSetupReader readFileAtPath:copy error:NULL];
    NSArray<QLMPassMatch *> *matches =
        QLMMatchPasses(QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY, NULL), setup, [setup groupNamed:@"Main 2x1"], NULL);
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
    NSArray<NSString *> *glm = [self lines:output starting:@"  GLM "];
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
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(QLMReadCapture(@"startup-idle", NULL), 0, INFINITY, NULL);
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
// (startup-idle, 8.841 and 9.133 s). No pass holds it, so it's listed
// before the pass it's for, and it's explained when it's that pass's own.
- (void)testAFrameBeforeAPassIsListedBeforeIt {
    NSString *output = nil;
    NSString *errors = nil;
    for (NSArray<NSString *> *check in @[@[], @[@"--check-outside"]]) {
        NSArray<NSString *> *arguments = @[QLMFixturePath(@"Main.sam"), QLMStartupIdle(), @"--group", @"Main 2x1"];
        int status = [self run:[arguments arrayByAddingObjectsFromArray:check] output:&output errors:&errors];
        XCTAssertEqual(status, 0, @"%@%@", output, errors);
        XCTAssertTrue([output containsString:@"   8.846 s  session 05  7370A 1000006 \"Sub\": matches\n"
                                             @"  GLM, outside a pass, before it\n"
                                             @"       8.841 s  as the pass after it sends it\n"
                                             @"                3B 00 3C\n"],
                      @"%@", output);
        XCTAssertTrue([output containsString:@"\n2 DSP frames outside a pass: 2 explained, 0 passed through, and 0 not explained.\n"],
                      @"%@", output);
    }
}

// A switch routes the monitors it leaves off, and they get no pass then. In
// setup-a-baseline, the switch to Main 2x1 routes the 7350A at 40.049 s,
// with Main 2x1's crossover, and the switch back routes it again at
// 46.534 s, before its pass at 46.940 s. Only the second is that pass's.
- (void)testARoutingFrameIsOnlyItsOwnPasses {
    NSString *output = nil;
    NSString *errors = nil;
    [self run:@[QLMFixturePath(@"Main.sam"), QLMRepositoryPath(@"captures/setup-a-baseline/reports.txt"), @"--group", @"Main 4x2"]
        output:&output
        errors:&errors];
    XCTAssertTrue([output containsString:@"  46.940 s  session 07  7350A 1000007 \"Center 7350A\": matches\n"
                                         @"  GLM, outside a pass, before it\n"
                                         @"      40.049 s  routing, to a monitor with no pass right after it\n"
                                         @"                3B 00 3C\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"      46.534 s  as the pass after it sends it\n"
                                         @"                3B 00 55\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@" 0 not explained.\n"], @"%@", output);
}

// A band GLM sends after a pass closes, as it does while its editor is
// open, is listed after the pass with its slot. Only a slot's last counts,
// and it must be the slot as the block sends it. The ones before it are
// values the editor passed through.
- (void)testABandAfterAPassIsListedAfterIt {
    QLMSetupGroup *group = QLMFixtureGroup(@"Main 2x1");
    QLMDSPBlock *block = [QLMDSPBlock blockForNode:[group nodeWithSerial:@"1000002"] inGroup:group error:NULL];
    NSData *band = QLMBlockSetting(block, QLMBytes((const uint8_t[]){0x10, 0x0E, 0x05}, 3));
    XCTAssertEqual(band.length, 24u);
    NSMutableData *edited = [band mutableCopy];
    ((uint8_t *)edited.mutableBytes)[edited.length - 2] ^= 0x01;
    NSTimeInterval first = 1 + QLMLeftPass().payloads.count * 0.001;

    for (NSArray<NSData *> *edits in @[@[edited, band], @[band, edited]]) {
        NSMutableArray<NSData *> *records = [NSMutableArray array];
        for (NSData *payload in QLMLeftPass().payloads) {
            [records addObject:QLMRecord(0x03, payload)];
        }
        for (NSData *edit in edits) {
            [records addObject:QLMRecord(0x03, edit)];
        }
        BOOL lastIsTheBlocks = edits.lastObject == band;
        NSString *capture = [self captureOf:records];
        NSString *output = nil;
        NSString *errors = nil;
        int status = [self run:@[QLMFixturePath(@"Main.sam"), capture, @"--group", @"Main 2x1", @"--check-outside"] output:&output
                        errors:&errors];
        XCTAssertEqual(status, lastIsTheBlocks ? 0 : QLMCompareApplyDiffers, @"%@%@", output, errors);
        NSString *listed = [NSString stringWithFormat:@"  GLM, outside a pass, after it\n"
                                                      @"  %10.3f s  slot 05, passed through\n                %@\n"
                                                      @"  %10.3f s  slot 05, %@\n                %@\n",
                                                      first, QLMHexOf(edits[0]), first + 0.001,
                                                      lastIsTheBlocks ? @"as the block sends it" : @"not as the block sends it",
                                                      QLMHexOf(edits[1])];
        NSRange at = [output rangeOfString:listed];
        XCTAssertNotEqual(at.location, (NSUInteger)NSNotFound, @"%@\n%@", listed, output);
        XCTAssertLessThan([output rangeOfString:@"session 03  8351B 1000002 \"Left\": matches\n"].location, at.location, @"%@", output);
        status = [self run:@[QLMFixturePath(@"Main.sam"), capture, @"--group", @"Main 2x1"] output:&output errors:&errors];
        XCTAssertEqual(status, 0, @"%@%@", output, errors);
    }
}

// With no pass at its session in the window, a frame's node is the one
// node of the group of the session's model. In Main 2x1 that's the 7370A
// for session 05, but no one node for 03, an 8351B like the Right. Only
// --check-outside runs on a window with no pass.
- (void)testAFrameWithNoPassComparesWithTheOneNodeOfItsModel {
    QLMSetupGroup *group = QLMFixtureGroup(@"Main 2x1");
    QLMDSPBlock *sub = [QLMDSPBlock blockForNode:[group nodeWithSerial:@"1000006"] inGroup:group error:NULL];
    NSData *subBand = QLMBlockSetting(sub, QLMBytes((const uint8_t[]){0x10, 0x0E, 0x01}, 3));
    NSData *flat = QLMBytes((const uint8_t[]){0x10, 0x0E, 0x13, 0x00, 0x00, 0x80, 0x3F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 24);
    NSString *both = [self startupIdleThen:QLMReportLines(@[QLMRecord(0x05, subBand), QLMRecord(0x03, flat)], 200)];
    NSString *subOnly = [self startupIdleThen:QLMReportLines(@[QLMRecord(0x05, subBand)], 200)];
    NSString *output = nil;
    NSString *errors = nil;

    int status = [self run:@[QLMFixturePath(@"Main.sam"), both, @"--group", @"Main 2x1", @"--from", @"199", @"--check-outside"]
                    output:&output
                    errors:&errors];
    XCTAssertEqual(status, QLMCompareApplyDiffers, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@"\nGLM, outside a pass, to session 05, which has no pass in the window\n"
                                         @"     200.000 s  slot 01, as the block sends it\n"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"\nGLM, outside a pass, to session 03, which has no pass in the window\n"
                                         @"     200.001 s  slot 13, no node to compare\n"],
                  @"%@", output);

    status = [self run:@[QLMFixturePath(@"Main.sam"), subOnly, @"--group", @"Main 2x1", @"--from", @"199", @"--check-outside"]
                output:&output
                errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    status = [self run:@[QLMFixturePath(@"Main.sam"), subOnly, @"--group", @"Main 2x1", @"--from", @"199"] output:&output errors:&errors];
    XCTAssertEqual(status, EX_DATAERR, @"%@%@", output, errors);
}

// A pass's model and hardware ID come from its session's last lease before
// it, and the 39 reply that follows that lease. qlm's runs reuse sessions
// for other monitors (qlm-control-all, 26 and 192 s). This copy of
// startup-idle leases the Rear Right 8330A again at 200 s, at session 03,
// the Left 8351B's, with the 8330A's 39 reply at 8.497 s, then sends its
// block there. Each pass at 03 takes its own lease's model.
- (void)testEachPassTakesItsOwnLeasesModel {
    QLMCapture *startup = QLMReadCapture(@"startup-idle", NULL);
    NSArray<QLMCapturedPass *> *passes = QLMPassesInCapture(startup, 0, INFINITY, NULL);
    QLMCapturedPass *rearRight = passes[0];
    XCTAssertEqual(rearRight.session, 0x02);
    XCTAssertEqualObjects(rearRight.model, @"8330A");
    XCTAssertEqual(rearRight.hardwareID.length, 3u);

    NSMutableData *lease = [QLMBytes((const uint8_t[]){0x02}, 1) mutableCopy];
    [lease appendData:rearRight.hardwareID];
    [lease appendBytes:(const uint8_t[]){0x03} length:1];
    NSMutableString *lines = [QLMReportLines(@[QLMRecord(QLMAddressMulticast, lease)], 200) mutableCopy];
    NSArray<NSString *> *text = [[NSString stringWithContentsOfFile:QLMStartupIdle() encoding:NSUTF8StringEncoding error:NULL]
        componentsSeparatedByString:@"\n"];
    NSUInteger ask = [text indexOfObjectPassingTest:^BOOL(NSString *line, NSUInteger i, BOOL *stop) {
        return [line containsString:@" out 85 03 39 "];
    }];
    NSUInteger asked = [text indexOfObjectPassingTest:^BOOL(NSString *line, NSUInteger i, BOOL *stop) {
        return [line containsString:@" out 85 02 39 "];
    }];
    XCTAssertTrue([text[asked + 1] containsString:@" in 3F 01 09 63 2D 32 3B 6D 6F 64 65 6C 2D 38 33 33 30 41 "]);
    NSArray<NSString *> *exchange = @[text[ask], text[asked + 1], text[asked + 2]];
    for (NSUInteger i = 0; i < exchange.count; i++) {
        [lines appendFormat:@"%.6f%@\n", 200.004 + i * 0.001, [exchange[i] substringFromIndex:[exchange[i] rangeOfString:@" "].location]];
    }
    NSMutableArray<NSData *> *block = [NSMutableArray array];
    for (NSData *payload in rearRight.payloads) {
        [block addObject:QLMRecord(0x03, payload)];
    }
    [lines appendString:QLMReportLines(block, 200.010)];
    NSString *path = [self startupIdleThen:lines];

    passes = QLMPassesInCapture([QLMCapture captureWithContentsOfFile:path error:NULL], 0, INFINITY, NULL);
    XCTAssertEqual(passes.count, 7u);
    XCTAssertEqual(passes[1].session, 0x03);
    XCTAssertEqualObjects(passes[1].model, @"8351B");
    XCTAssertEqual(passes[6].session, 0x03);
    XCTAssertEqualObjects(passes[6].model, @"8330A");
    XCTAssertEqualObjects(passes[6].hardwareID, rearRight.hardwareID);

    NSString *output = nil;
    NSString *errors = nil;
    int status = [self run:@[QLMFixturePath(@"Main.sam"), path, @"--group", @"Main 2x1"] output:&output errors:&errors];
    XCTAssertEqual(status, 0, @"%@%@", output, errors);
    XCTAssertTrue([output containsString:@" 200.010 s  session 03  8330A 1000005 \"Rear Right 8330A\": matches\n"], @"%@", output);
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
        @[setup, capture, @"--group", @"Main 2x1", @"--check-outside", @"--check-outside"],
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
