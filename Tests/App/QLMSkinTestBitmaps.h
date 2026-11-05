#ifndef QLMSKINTESTBITMAPS_H
#define QLMSKINTESTBITMAPS_H

#import <Cocoa/Cocoa.h>

#import "QLMSkinDrawing.h"

NS_ASSUME_NONNULL_BEGIN

// The skin's tests draw at 2x, as a view on a Retina display does.
static const CGFloat QLMTestScale = 2;

static inline NSBitmapImageRep *QLMTestBitmapAtScale(NSSize points, CGFloat scale) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                   pixelsWide:(NSInteger)(points.width * scale)
                                                   pixelsHigh:(NSInteger)(points.height * scale)
                                                bitsPerSample:8
                                              samplesPerPixel:4
                                                     hasAlpha:YES
                                                     isPlanar:NO
                                               colorSpaceName:NSDeviceRGBColorSpace
                                                  bytesPerRow:0
                                                 bitsPerPixel:0];
}

static inline NSBitmapImageRep *QLMTestBitmap(NSSize points) {
    return QLMTestBitmapAtScale(points, QLMTestScale);
}

// Draws in points, y down, as a flipped view's drawRect: does, its shadows
// falling as they do on the screen.
static inline NSBitmapImageRep *QLMTestDrawFlippedAtScale(NSSize points, CGFloat scale, void (^draw)(void)) {
    NSBitmapImageRep *bitmap = QLMTestBitmapAtScale(points, scale);
    CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
    CGContextScaleCTM(cg, scale, scale);
    CGContextTranslateCTM(cg, 0, points.height);
    CGContextScaleCTM(cg, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = QLMSkinBitmapGraphicsContext(cg, scale);
    draw();
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

static inline NSBitmapImageRep *QLMTestDrawFlipped(NSSize points, void (^draw)(void)) {
    return QLMTestDrawFlippedAtScale(points, QLMTestScale, draw);
}

// The rows of pixels with ink of more than `alpha`, top first.
static inline NSRange QLMTestInkRows(NSBitmapImageRep *bitmap, CGFloat alpha) {
    NSInteger first = -1;
    NSInteger last = -1;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            if ([bitmap colorAtX:x y:y].alphaComponent > alpha) {
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

NS_ASSUME_NONNULL_END

#endif
