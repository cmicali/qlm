#ifndef QLMSKINTESTBITMAPS_H
#define QLMSKINTESTBITMAPS_H

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#import "QLMSkinDrawing.h"

NS_ASSUME_NONNULL_BEGIN

// The skin's tests draw at 2x, as a view on a Retina display does.
static const CGFloat QLMTestScale = 2;

static inline NSBitmapImageRep *QLMTestBitmapAtScale(NSSize points, CGFloat scale) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                   pixelsWide:(NSInteger)ceil(points.width * scale)
                                                   pixelsHigh:(NSInteger)ceil(points.height * scale)
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

// Draws in points, y down, through QLMSkinRenderImage, as the app draws a
// material, its shadows falling as they do on the screen.
static inline NSBitmapImageRep *QLMTestDrawFlippedAtScale(NSSize points, CGFloat scale, void (^draw)(void)) {
    NSBitmapImageRep *bitmap = QLMTestBitmapAtScale(points, scale);
    CGImageRef image = QLMSkinRenderImage(points, scale, draw);
    if (image != NULL) {
        CGContextRef cg = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap].CGContext;
        CGContextSetBlendMode(cg, kCGBlendModeCopy);
        CGContextDrawImage(cg, CGRectMake(0, 0, bitmap.pixelsWide, bitmap.pixelsHigh), image);
        CGImageRelease(image);
    }
    return bitmap;
}

static inline NSBitmapImageRep *QLMTestDrawFlipped(NSSize points, void (^draw)(void)) {
    return QLMTestDrawFlippedAtScale(points, QLMTestScale, draw);
}

// The bounds, in pixels, top first, where `pass` holds for a pixel of `a`
// and the same pixel of `b`, each four bytes with alpha last. Zero where
// it holds for none.
static inline NSRect QLMTestPixelBounds(NSBitmapImageRep *a, NSBitmapImageRep *b,
                                        BOOL (^pass)(const uint8_t *u, const uint8_t *v)) {
    NSInteger minX = NSIntegerMax, minY = NSIntegerMax, maxX = -1, maxY = -1;
    for (NSInteger y = 0; y < a.pixelsHigh; y++) {
        for (NSInteger x = 0; x < a.pixelsWide; x++) {
            if (pass(a.bitmapData + y * a.bytesPerRow + x * 4, b.bitmapData + y * b.bytesPerRow + x * 4)) {
                minX = MIN(minX, x);
                minY = MIN(minY, y);
                maxX = MAX(maxX, x);
                maxY = MAX(maxY, y);
            }
        }
    }
    return maxX < 0 ? NSZeroRect : NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

// The rows of pixels with ink of more than `alpha`, top first.
static inline NSRange QLMTestInkRows(NSBitmapImageRep *bitmap, CGFloat alpha) {
    NSRect ink = QLMTestPixelBounds(bitmap, bitmap, ^BOOL(const uint8_t *u, const uint8_t *v) {
        return u[3] > alpha * 255;
    });
    return NSIsEmptyRect(ink) ? NSMakeRange(NSNotFound, 0) : NSMakeRange((NSUInteger)NSMinY(ink), (NSUInteger)ink.size.height);
}

// An offscreen window, as the screen's: it draws without being shown.
static inline NSWindow *QLMTestOffscreenWindow(NSSize size) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:(NSRect){NSZeroPoint, size} styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView.wantsLayer = YES;  // as on the screen
    return window;
}

// What a window on the screen does at its next frame. TRAP: here, a
// window's displayIfNeeded draws nothing. The transaction's commit draws,
// and gives each layer its presentation.
static inline void QLMTestPumpWindow(NSWindow *window) {
    [window displayIfNeeded];
    [CATransaction flush];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

NS_ASSUME_NONNULL_END

#endif
