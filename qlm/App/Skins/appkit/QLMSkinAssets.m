#import "QLMSkinAssets.h"
#import <math.h>

NSImage *QLMSkinImage(QLMSkin skin, NSString *asset) {
    NSString *prefix = skin == QLMSkinRetro ? @"QLMRetro" : @"QLMVintage";
    return [NSImage imageNamed:[NSString stringWithFormat:@"%@_%@", prefix, asset]];
}

static void QLMDrawAsset(QLMSkin skin, NSString *name, NSRect frame) {
    NSImage *image = QLMSkinImage(skin, name);
    [image drawInRect:frame fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
             fraction:1 respectFlipped:YES hints:nil];
}

void QLMDrawSkinButton(QLMSkin skin, NSRect frame, BOOL selected, BOOL hovered,
                       BOOL pressed, BOOL enabled, BOOL focused) {
    NSString *state;
    if (!enabled) {
        state = selected ? @"selected-disabled" : @"disabled";
    } else if (pressed) {
        state = selected ? @"selected-pressed" : @"pressed";
    } else if (hovered) {
        state = selected ? @"selected-hover" : @"hover";
    } else {
        state = selected ? @"selected" : @"normal";
    }
    NSString *name = [@"button-" stringByAppendingString:state];
    NSImage *image = [QLMSkinImage(skin, name) copy];
    image.capInsets = skin == QLMSkinRetro ? NSEdgeInsetsMake(9, 12, 10, 12)
                                                 : NSEdgeInsetsMake(8, 8, 9, 8);
    image.resizingMode = NSImageResizingModeStretch;
    [image drawInRect:frame fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
             fraction:1 respectFlipped:YES hints:nil];
    if (focused && enabled) {
        NSImage *ring = [QLMSkinImage(skin, @"button-focus-ring") copy];
        ring.capInsets = NSEdgeInsetsMake(8, 8, 8, 8);
        ring.resizingMode = NSImageResizingModeStretch;
        [ring drawInRect:frame fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                fraction:1 respectFlipped:YES hints:nil];
    }
}

void QLMDrawSkinKnob(QLMSkin skin, NSRect frame, double fraction, BOOL hovered,
                     BOOL pressed, BOOL enabled, BOOL focused) {
    fraction = isfinite(fraction) ? fmax(0, fmin(1, fraction)) : 0;
    NSString *state = !enabled ? @"disabled" : pressed ? @"pressed" : hovered ? @"hover" : @"normal";
    QLMDrawAsset(skin, @"knob-shadow", frame);
    QLMDrawAsset(skin, [@"knob-body-" stringByAppendingString:state], frame);
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMidX(frame) yBy:NSMidY(frame)];
    [transform rotateByDegrees:-135 + fraction * 270];
    [transform translateXBy:-NSMidX(frame) yBy:-NSMidY(frame)];
    [transform concat];
    QLMDrawAsset(skin, enabled ? @"knob-pointer" : @"knob-pointer-disabled", frame);
    [NSGraphicsContext restoreGraphicsState];
    if (focused && enabled) {
        QLMDrawAsset(skin, @"knob-focus-ring", frame);
    }
}
