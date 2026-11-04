#import <Cocoa/Cocoa.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// The skin's drawing in AppKit: its colors, images, fonts, and the geometry
// the app draws itself. Every function draws in a flipped view.

NSColor *QLMSkinNSColor(QLMSkinColor color);
BOOL QLMSkinColorIsClear(QLMSkinColor color);

// png/<name>.png with its @2x beside it, sized in points, with no cap
// insets. Nil when either file won't load. Cached.
NSImage *_Nullable QLMSkinImage(QLMSkin *skin, NSString *name);

// An element's material in `rect`: its image for the state, stretched
// through its cap insets, or its draw block. A circle draws the block as
// the rect's inscribed circle, as a knob's body.
void QLMSkinDrawStyle(QLMSkin *skin, QLMSkinStyle *style, QLMSkinState state, NSRect rect, BOOL circle);

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
