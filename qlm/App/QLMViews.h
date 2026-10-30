#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A wrapping label in the small system font and the secondary color. A
// width of 0 leaves the wrap to Auto Layout.
NSTextField *QLMNoteLabel(NSString *text, CGFloat width);

// A monitor's status dot. The caller tints it.
NSImageView *QLMDotView(void);

// Pins the view to the container's four edges.
void QLMPinToEdges(NSView *view, NSView *container);

NS_ASSUME_NONNULL_END
