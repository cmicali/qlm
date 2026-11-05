#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A Debug build's look at a skin, for the debug channel's skin_preview, so a
// screenshot can check a skin without choosing it. The .m wraps its body in
// #if DEBUG, so a call from Release code fails to link.
//
// Opens a window with a skin view at the skin's size, or the OSD at its
// size, filled with the mockups' sample text, and makes it key. Returns the
// reply: the skin shown, and the refusal it fell back from, if any. A
// disabled look shows every control disabled.
NSDictionary *QLMShowSkinPreview(NSString *name, BOOL osd, BOOL disabled);

NS_ASSUME_NONNULL_END
