#import <Cocoa/Cocoa.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// The skin's drawing in AppKit: its colors, images, fonts, and the geometry
// the app draws itself. Every function draws in a flipped view.

// What a disabled control's drawn geometry and text keep of their alpha.
extern const CGFloat QLMSkinDisabledAlpha;

// Two texts read the same, both nil included, so a setter given the text
// it has redraws nothing.
static inline BOOL QLMSkinSameText(NSString *_Nullable a, NSString *_Nullable b) {
    return a == b || [a isEqualToString:b];
}

NSColor *QLMSkinNSColor(QLMSkinColor color);

// An element's material in `rect`: its image for the state, stretched
// through its cap insets, or its draw block. A circle draws the block as
// the rect's inscribed circle, as a knob's body.
void QLMSkinDrawStyle(QLMSkin *skin, QLMSkinStyle *style, QLMSkinState state, NSRect rect, BOOL circle);

// An image in `rect`, right side up in a flipped view, whatever its size
// and cap insets. Every image the skin draws goes through here.
void QLMSkinDrawImage(NSImage *_Nullable image, NSRect rect);

// Decodes every image the skin's styles name, at the main screen's scale,
// on a background queue, so the first show finds them decoded. The other
// scale decodes when first asked for.
void QLMSkinWarmImages(QLMSkin *skin);

// What `draw` draws in `size` points at `scale`, in a flipped context.
CGImageRef _Nullable QLMSkinRenderImage(NSSize size, CGFloat scale, void (^draw)(void)) CF_RETURNS_RETAINED;

// A flipped context for a bitmap at `scale`, in which the skin's shadows
// fall as they do in a view on the screen.
NSGraphicsContext *QLMSkinBitmapGraphicsContext(CGContextRef context, CGFloat scale);

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
// Where a slot's text may ink, for one slot's redraw: its frame and its
// line, with a margin for the glyphs' overhang.
NSRect QLMSkinSlotInk(QLMSkinTextSlot *slot, NSRect frame, CGFloat scale);
// QLMSkinDrawSlot clipped to the slot's ink, so a change that redraws only
// that rect leaves none of the old text behind, however far it inked.
void QLMSkinDrawSlotInInk(NSString *_Nullable text, QLMSkinTextSlot *slot, NSRect frame, CGFloat scale, BOOL monoDigits,
                          CGFloat alpha);
// Where a button's label goes on a face `faceWidth` wide: the LED, `led`
// wide, then `gap`, then the title, centered as one block. A title too long
// for the face, inside its padding, is cut short, never pushed off it.
typedef struct {
    CGFloat ledX;
    CGFloat textX;
    CGFloat textWidth;
} QLMSkinLabel;
extern const CGFloat QLMSkinLabelPadding;
QLMSkinLabel QLMSkinLabelLayout(CGFloat faceWidth, CGFloat titleWidth, CGFloat led, CGFloat gap);

// A label's ink, from its origin on the baseline, and its advance past the
// ink. A label centers by its ink, not its advance, which a glyph's side
// bearings and the last one's tracking would push off center.
typedef struct {
    CGFloat x;
    CGFloat width;
    CGFloat bearings;
} QLMSkinInk;
QLMSkinInk QLMSkinLabelInk(NSAttributedString *text);
// Draws `text` with its ink from `x`, cut short past `width`, its capitals
// centered on `frame`'s height.
void QLMSkinDrawLabel(NSAttributedString *text, QLMSkinInk ink, CGFloat x, CGFloat width, NSRect frame);

// A button's label, its capitals centered on the frame's height.
void QLMSkinDrawCenteredCaps(NSAttributedString *text, NSRect frame);

NS_ASSUME_NONNULL_END
