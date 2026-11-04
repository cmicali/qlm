#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QLMSkin) {
    QLMSkinVintage,
    QLMSkinRetro,
};

FOUNDATION_EXPORT NSImage * _Nullable QLMSkinImage(QLMSkin skin, NSString *asset);
FOUNDATION_EXPORT void QLMDrawSkinButton(QLMSkin skin, NSRect frame, BOOL selected,
                                        BOOL hovered, BOOL pressed, BOOL enabled,
                                        BOOL focused);
// Draw in a flipped NSView. A fraction of 0 is the minimum; 1 is the ceiling.
FOUNDATION_EXPORT void QLMDrawSkinKnob(QLMSkin skin, NSRect frame, double fraction,
                                      BOOL hovered, BOOL pressed, BOOL enabled,
                                      BOOL focused);

NS_ASSUME_NONNULL_END
