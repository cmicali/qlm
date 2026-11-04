#import <Cocoa/Cocoa.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// The skin's drawing in AppKit: its colors, images, fonts, and the geometry
// the app draws itself. Every function draws in a flipped view.

// What a disabled control's drawn geometry and text keep of their alpha.
extern const CGFloat QLMSkinDisabledAlpha;

NSColor *QLMSkinNSColor(QLMSkinColor color);
BOOL QLMSkinColorIsClear(QLMSkinColor color);

// An element's material in `rect`: its image for the state, stretched
// through its cap insets, or its draw block. A circle draws the block as
// the rect's inscribed circle, as a knob's body. Images are kept on the
// skin, so a skin read again loads its files again.
void QLMSkinDrawStyle(QLMSkin *skin, QLMSkinStyle *style, QLMSkinState state, NSRect rect, BOOL circle);

// The shadow `path` casts, filled with `fill`.
void QLMSkinDrawShadow(QLMSkinShadow *shadow, NSBezierPath *path, NSColor *fill);

// Draws `content`. Dimmed, it lays `overlay` over what `content` drew, in
// its shape, so an image's corners stay round.
void QLMSkinDrawDimmed(BOOL dimmed, QLMSkinColor overlay, NSRect bounds, void (^content)(void));

// An LED in `rect`: lit with its glow, unlit, or dim when disabled.
void QLMSkinDrawLED(QLMSkinLED *led, NSRect rect, BOOL lit, BOOL enabled);

// A focus ring around `rect`.
void QLMSkinDrawFocus(QLMSkinFocus *focus, NSRect rect, BOOL circle);

// A face the Mac has, else the system font, or the system monospaced one
// for mono. monoDigits makes the digits monospaced in any face.
NSFont *QLMSkinFont(NSString *_Nullable name, BOOL mono, CGFloat size, QLMSkinWeight weight, BOOL italic, BOOL monoDigits);
NSFont *QLMSkinSlotFont(QLMSkinTextSlot *slot, CGFloat scale, BOOL monoDigits);

// The slot's text attributes, in `color`.
NSDictionary<NSAttributedStringKey, id> *QLMSkinTextAttributes(NSFont *font, NSColor *color, QLMSkinAlignment alignment,
                                                               CGFloat tracking);

// A one-line text, centered on the frame's height, cut short with an
// ellipsis where it overflows. A slot's accent colors its trailing period.
void QLMSkinDrawSlot(NSString *_Nullable text, QLMSkinTextSlot *slot, NSRect frame, CGFloat scale, BOOL monoDigits,
                     CGFloat alpha);
void QLMSkinDrawAttributed(NSAttributedString *text, NSRect frame);

NS_ASSUME_NONNULL_END
