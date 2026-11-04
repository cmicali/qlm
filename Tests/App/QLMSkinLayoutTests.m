#import <XCTest/XCTest.h>

#import "QLMSkin.h"
#import "QLMSkinLayout.h"
#import "QLMTestSupport.h"

// The resize pass, over the fixture skin. Source: docs/ui.md, Resizing: the
// extra width goes to the display and the button rows, the extra height to
// the display row, and the knob column keeps its width, anchored right and
// centered in the display row.
@interface QLMSkinLayoutTests : XCTestCase
@end

#define QLMAssertRect(actual, x, y, w, h)                                                     \
    do {                                                                                      \
        CGRect a_ = (actual);                                                                 \
        XCTAssertTrue(CGRectEqualToRect(a_, CGRectMake((x), (y), (w), (h))), @"%@ is not %@", \
                      NSStringFromRect(a_), NSStringFromRect(CGRectMake((x), (y), (w), (h)))); \
    } while (0)

static CGRect QLMCell(NSArray<NSValue *> *cells, NSUInteger index) {
    CGRect rect = CGRectZero;
    [cells[index] getValue:&rect size:sizeof rect];
    return rect;
}

static NSArray<NSString *> *QLMElementNames(void) {
    return @[@"panel", @"nameplate", @"status", @"groups", @"display", @"toggles", @"knob", @"footer"];
}

@implementation QLMSkinLayoutTests {
    QLMSkin *_skin;
}

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    _skin = [QLMSkin skinAtURL:[NSURL fileURLWithPath:QLMRepositoryPath(@"Tests/App/Fixtures/Skins/fixture")] error:&error];
    XCTAssertNotNil(_skin, @"%@", error.localizedDescription);
}

- (void)testTheReferenceSizeGivesTheDeclaredFrames {
    QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:_skin size:CGSizeMake(640, 480)];
    for (NSString *name in QLMElementNames()) {
        XCTAssertTrue(CGRectEqualToRect([layout frameOfElement:name], [_skin element:name].frame), @"%@", name);
        for (NSString *slot in [_skin element:name].text) {
            XCTAssertTrue(CGRectEqualToRect([layout frameOfSlot:slot inElement:name], [_skin element:name].text[slot].frame),
                          @"%@.%@", name, slot);
            XCTAssertEqual([layout scaleOfSlot:slot inElement:name], 1, @"%@.%@", name, slot);
        }
    }
    NSArray<NSValue *> *cells = [layout cellsOfElement:@"groups"];
    XCTAssertEqual(cells.count, 3u);
    QLMAssertRect(QLMCell(cells, 0), 48, 120, 174, 40);
    QLMAssertRect(QLMCell(cells, 1), 234, 120, 174, 40);
    QLMAssertRect(QLMCell(cells, 2), 420, 120, 174, 40);
    NSArray<NSValue *> *toggles = [layout cellsOfElement:@"toggles"];
    QLMAssertRect(QLMCell(toggles, 0), 48, 338, 174, 40);
    QLMAssertRect(QLMCell(toggles, 1), 230, 338, 174, 40);
}

// A size below the skin's is the skin's.
- (void)testASmallerSizeIsTheReference {
    QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:_skin size:CGSizeMake(500, 400)];
    XCTAssertTrue(CGSizeEqualToSize(layout.size, CGSizeMake(640, 480)));
    QLMAssertRect([layout frameOfElement:@"display"], 48, 184, 356, 132);
}

- (void)testAWiderWindow {
    QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:_skin size:CGSizeMake(760, 480)];
    QLMAssertRect([layout frameOfElement:@"panel"], 0, 0, 760, 480);
    // The header: the count moves right.
    QLMAssertRect([layout frameOfElement:@"nameplate"], 48, 27, 78, 38);
    QLMAssertRect([layout frameOfElement:@"status"], 634, 37, 85, 16);
    // The groups and the mute and dim pair stretch, and their buttons fill
    // their columns.
    QLMAssertRect([layout frameOfElement:@"groups"], 48, 120, 666, 40);
    NSArray<NSValue *> *cells = [layout cellsOfElement:@"groups"];
    QLMAssertRect(QLMCell(cells, 0), 48, 120, 214, 40);
    QLMAssertRect(QLMCell(cells, 2), 500, 120, 214, 40);
    QLMAssertRect([layout frameOfElement:@"toggles"], 48, 338, 476, 40);
    QLMAssertRect(QLMCell([layout cellsOfElement:@"toggles"], 1), 290, 338, 234, 40);
    // The display stretches, and its height, and so its level, stays.
    QLMAssertRect([layout frameOfElement:@"display"], 48, 184, 476, 132);
    XCTAssertEqual([layout scaleOfSlot:@"level" inElement:@"display"], 1);
    QLMAssertRect([layout frameOfSlot:@"max" inElement:@"display"], 400, 95, 63, 15);
    QLMAssertRect([layout frameOfSlot:@"output" inElement:@"display"], 19, 95, 140, 15);
    // The knob column keeps its width, anchored right.
    QLMAssertRect([layout frameOfElement:@"knob"], 540, 162, 176, 176);
    QLMAssertRect([layout frameOfSlot:@"caption" inElement:@"knob"], 54, 189, 69, 18);
    // The footer: Standby moves right.
    QLMAssertRect([layout frameOfElement:@"footer"], 48, 400, 666, 40);
    QLMAssertRect([layout frameOfSlot:@"monitors" inElement:@"footer"], 18, 11, 94, 21);
    QLMAssertRect([layout frameOfSlot:@"power" inElement:@"footer"], 598, 11, 64, 21);
}

- (void)testATallerWindow {
    QLMSkinLayout *layout = [[QLMSkinLayout alloc] initWithSkin:_skin size:CGSizeMake(640, 546)];
    QLMAssertRect([layout frameOfElement:@"panel"], 0, 0, 640, 546);
    // The header and the groups stay.
    QLMAssertRect([layout frameOfElement:@"nameplate"], 48, 27, 78, 38);
    QLMAssertRect([layout frameOfElement:@"status"], 514, 37, 85, 16);
    QLMAssertRect([layout frameOfElement:@"groups"], 48, 120, 546, 40);
    // The display row takes the height. The level scales with it, from the
    // display's origin.
    QLMAssertRect([layout frameOfElement:@"display"], 48, 184, 356, 198);
    XCTAssertEqual([layout scaleOfSlot:@"level" inElement:@"display"], 1.5);
    XCTAssertEqual([layout scaleOfSlot:@"unit" inElement:@"display"], 1.5);
    XCTAssertEqual([layout scaleOfSlot:@"caption" inElement:@"display"], 1);
    QLMAssertRect([layout frameOfSlot:@"level" inElement:@"display"], 28.5, 52.5, 319.5, 97.5);
    QLMAssertRect([layout frameOfSlot:@"caption" inElement:@"display"], 19, 13, 90, 16);
    QLMAssertRect([layout frameOfSlot:@"output" inElement:@"display"], 19, 161, 140, 15);
    // The pair below it and the footer move down.
    QLMAssertRect([layout frameOfElement:@"toggles"], 48, 404, 356, 40);
    QLMAssertRect([layout frameOfElement:@"footer"], 48, 466, 546, 40);
    // The knob centers in the display row.
    QLMAssertRect([layout frameOfElement:@"knob"], 420, 195, 176, 176);
    CGRect display = [layout frameOfElement:@"display"];
    XCTAssertEqual(CGRectGetMidY([layout frameOfElement:@"knob"]), CGRectGetMidY(display));
}

- (void)testTheSpring {
    CGRect frame = CGRectMake(10, 20, 30, 40);
    CGSize extra = CGSizeMake(100, 50);
    QLMAssertRect(QLMSkinSpring(frame, QLMSkinAnchorLeft | QLMSkinAnchorTop, extra), 10, 20, 30, 40);
    QLMAssertRect(QLMSkinSpring(frame, QLMSkinAnchorRight | QLMSkinAnchorBottom, extra), 110, 70, 30, 40);
    QLMAssertRect(QLMSkinSpring(frame, 0, extra), 60, 45, 30, 40);
    QLMAssertRect(QLMSkinSpring(frame, QLMSkinAnchorLeft | QLMSkinAnchorRight | QLMSkinAnchorTop | QLMSkinAnchorBottom, extra),
                  10, 20, 130, 90);
}

- (void)testTwoRowsOfThree {
    NSArray<NSValue *> *cells = QLMSkinGridCells(CGRectMake(28, 106, 584, 70), 3, 2, CGSizeMake(8, 6));
    XCTAssertEqual(cells.count, 6u);
    QLMAssertRect(QLMCell(cells, 0), 28, 106, 189.33333333333334, 32);
    XCTAssertEqualWithAccuracy(QLMCell(cells, 4).origin.x, 28 + 568.0 / 3 + 8, 1e-9);
    XCTAssertEqual(QLMCell(cells, 4).origin.x, QLMCell(cells, 1).origin.x);
    XCTAssertEqual(QLMCell(cells, 4).origin.y, 144);
}

@end
