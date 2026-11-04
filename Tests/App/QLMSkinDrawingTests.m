#import <XCTest/XCTest.h>

#import "QLMSkinDrawing.h"

// The skin's drawing, in a flipped bitmap at 2x, as a view on a Retina
// display draws it.
@interface QLMSkinDrawingTests : XCTestCase
@end

static const CGFloat QLMTestScale = 2;

static NSColor *QLMTestRed(void) {
    return [NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1];
}

static NSColor *QLMTestBlue(void) {
    return [NSColor colorWithDeviceRed:0 green:0 blue:1 alpha:1];
}

static NSBitmapImageRep *QLMTestBitmap(NSSize points) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                   pixelsWide:(NSInteger)(points.width * QLMTestScale)
                                                   pixelsHigh:(NSInteger)(points.height * QLMTestScale)
                                                bitsPerSample:8
                                              samplesPerPixel:4
                                                     hasAlpha:YES
                                                     isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace
                                                  bytesPerRow:0
                                                 bitsPerPixel:0];
}

// Draws in points, y down, as a flipped view's drawRect: does.
static NSBitmapImageRep *QLMTestDrawFlipped(NSSize points, void (^draw)(void)) {
    NSBitmapImageRep *bitmap = QLMTestBitmap(points);
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
    CGContextScaleCTM(cg, QLMTestScale, QLMTestScale);
    CGContextTranslateCTM(cg, 0, points.height);
    CGContextScaleCTM(cg, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
    draw();
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

// 20 by 20 points: red over blue, as its file has it.
static NSImage *QLMTestTwoToneImage(NSEdgeInsets insets) {
    NSBitmapImageRep *rep = QLMTestBitmap(NSMakeSize(20, 20));
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        for (NSInteger x = 0; x < rep.pixelsWide; x++) {
            [rep setColor:y < rep.pixelsHigh / 2 ? QLMTestRed() : QLMTestBlue() atX:x y:y];
        }
    }
    rep.size = NSMakeSize(20, 20);
    NSImage *image = [[NSImage alloc] initWithSize:rep.size];
    [image addRepresentation:rep];
    image.capInsets = insets;
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}

static BOOL QLMTestIsRed(NSColor *color) {
    return color.redComponent > 0.5 && color.blueComponent < 0.5;
}

// The rows of pixels with any ink, top first.
static NSRange QLMTestInkRows(NSBitmapImageRep *bitmap) {
    NSInteger first = -1;
    NSInteger last = -1;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            if ([bitmap colorAtX:x y:y].alphaComponent > 0.5) {
                if (first < 0) {
                    first = y;
                }
                last = y;
                break;
            }
        }
    }
    return first < 0 ? NSMakeRange(NSNotFound, 0) : NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
}

@implementation QLMSkinDrawingTests

// TRAP: AppKit draws an image with cap insets upside down in a flipped view
// at any size but its own, so vintage's and retro's panel and glass turned
// over when the window grew. Every size here keeps red on top.
- (void)testAStretchedImageStaysRightSideUp {
    NSImage *image = QLMTestTwoToneImage(NSEdgeInsetsMake(4, 4, 4, 4));
    NSArray<NSValue *> *sizes = @[
        [NSValue valueWithSize:NSMakeSize(20, 20)],
        [NSValue valueWithSize:NSMakeSize(40, 60)],
        [NSValue valueWithSize:NSMakeSize(20, 60)],
        [NSValue valueWithSize:NSMakeSize(90, 20)],
    ];
    for (NSValue *value in sizes) {
        NSSize size = value.sizeValue;
        NSBitmapImageRep *bitmap = QLMTestDrawFlipped(size, ^{
            QLMSkinDrawImage(image, NSMakeRect(0, 0, size.width, size.height));
        });
        NSInteger x = bitmap.pixelsWide / 2;
        XCTAssertTrue(QLMTestIsRed([bitmap colorAtX:x y:1]), @"%@", NSStringFromSize(size));
        XCTAssertFalse(QLMTestIsRed([bitmap colorAtX:x y:bitmap.pixelsHigh - 2]), @"%@", NSStringFromSize(size));
    }
}

// Off the origin, too: the flip maps the rect onto itself.
- (void)testAStretchedImageLandsInItsRect {
    NSImage *image = QLMTestTwoToneImage(NSEdgeInsetsMake(4, 4, 4, 4));
    NSRect rect = NSMakeRect(10, 30, 50, 60);
    NSBitmapImageRep *bitmap = QLMTestDrawFlipped(NSMakeSize(100, 100), ^{
        QLMSkinDrawImage(image, rect);
    });
    NSInteger x = (NSInteger)(NSMidX(rect) * QLMTestScale);
    NSInteger top = (NSInteger)(NSMinY(rect) * QLMTestScale);
    NSInteger bottom = (NSInteger)(NSMaxY(rect) * QLMTestScale);
    XCTAssertTrue(QLMTestIsRed([bitmap colorAtX:x y:top + 2]));
    XCTAssertFalse(QLMTestIsRed([bitmap colorAtX:x y:bottom - 4]));
    XCTAssertEqual([bitmap colorAtX:x y:top - 2].alphaComponent, 0);
    XCTAssertEqual([bitmap colorAtX:x y:bottom + 2].alphaComponent, 0);
}

// The LED, the gap, and the title center as one block on the face.
- (void)testALabelCentersAsOneBlock {
    QLMSkinLabel label = QLMSkinLabelLayout(174, 40, 6, 8);
    XCTAssertEqual(label.ledX, 60);
    XCTAssertEqual(label.textX, 74);
    XCTAssertEqual(label.textWidth, 40);
    // No LED, the title alone.
    label = QLMSkinLabelLayout(174, 40, 0, 8);
    XCTAssertEqual(label.textX, 67);
}

// A long title on a narrow face is cut short inside the padding, and the LED
// stays on the face.
- (void)testALongLabelStaysOnTheFace {
    QLMSkinLabel label = QLMSkinLabelLayout(100, 300, 6, 8);
    XCTAssertEqual(label.ledX, QLMSkinLabelPadding);
    XCTAssertEqual(label.textWidth, 100 - 2 * QLMSkinLabelPadding - 14);
    XCTAssertEqual(label.textX + label.textWidth, 100 - QLMSkinLabelPadding);
    // A face too narrow for the LED itself draws no title.
    label = QLMSkinLabelLayout(20, 300, 6, 8);
    XCTAssertEqual(label.textWidth, 0);
}

// A label too long for its frame is cut short inside it.
- (void)testALongLabelIsCutShort {
    NSFont *font = QLMSkinFont(nil, NO, 11, QLMSkinWeightRegular, NO, NO);
    NSAttributedString *label = [[NSAttributedString alloc]
        initWithString:@"A  A VERY LONG LISTENING SETUP NAME"
            attributes:QLMSkinTextAttributes(font, NSColor.blackColor, QLMSkinAlignmentLeft, 0)];
    NSRect frame = NSMakeRect(10, 0, 60, 40);
    NSBitmapImageRep *bitmap = QLMTestDrawFlipped(NSMakeSize(300, 40), ^{
        QLMSkinDrawCenteredCaps(label, frame);
    });
    NSInteger last = -1;
    for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
        for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
            if ([bitmap colorAtX:x y:y].alphaComponent > 0.5) {
                last = x;
                break;
            }
        }
    }
    XCTAssertGreaterThan(last, (NSInteger)(NSMidX(frame) * QLMTestScale));
    XCTAssertLessThanOrEqual(last, (NSInteger)(NSMaxX(frame) * QLMTestScale));
}

// A button's label: its capitals sit as far from the face's top as from its
// bottom, within a pixel at 2x, in every skin's size.
- (void)testALabelsCapitalsAreCentered {
    for (NSNumber *size in @[@11, @13]) {
        NSFont *font = QLMSkinFont(nil, NO, size.doubleValue, QLMSkinWeightMedium, NO, NO);
        NSAttributedString *label = [[NSAttributedString alloc]
            initWithString:@"A  MAIN"
                attributes:QLMSkinTextAttributes(font, NSColor.blackColor, QLMSkinAlignmentLeft, 0)];
        for (NSNumber *height in @[@34, @40]) {
            NSSize face = NSMakeSize(120, height.doubleValue);
            NSBitmapImageRep *bitmap = QLMTestDrawFlipped(face, ^{
                QLMSkinDrawCenteredCaps(label, NSMakeRect(0, 0, face.width, face.height));
            });
            NSRange ink = QLMTestInkRows(bitmap);
            XCTAssertNotEqual(ink.location, NSNotFound);
            double above = (double)ink.location;
            double below = (double)bitmap.pixelsHigh - (double)NSMaxRange(ink);
            XCTAssertEqualWithAccuracy(above, below, 1, @"%@ pt on %@", size, height);
        }
    }
}

@end
