#import <Cocoa/Cocoa.h>

#import "QLMKnobControl.h"
#import "QLMSkin.h"
#import "QLMSkinControls.h"
#import "QLMSkinLayout.h"

NS_ASSUME_NONNULL_BEGIN

// The main window's content view, in one skin. It draws the panel, the
// nameplate, the markings, and the panel's own text, and hosts one view per
// element, laid out by the resize pass with no Auto Layout. It writes the
// words that are the same in every skin itself: the logo, the titles, the
// unit, MUTE, DIM, and Monitors. A controller hands each view its state and
// the rest of its text. It reads no snapshot and drives nothing: each
// control sends its action to the target the controller sets.
@interface QLMSkinView : NSView

- (instancetype)initWithSkin:(QLMSkin *)skin NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) QLMSkin *skin;
@property (nonatomic, readonly) QLMSkinLayout *skinLayout;  // for the view's size

// In the groups' place while none show: the setup file's name, or its
// error.
@property (nonatomic, copy, nullable) NSString *groupsMessage;
@property (nonatomic, copy, nullable) NSString *knobMin;
@property (nonatomic, copy, nullable) NSString *knobMax;

@property (nonatomic, readonly) QLMSkinStatusView *status;
// One per cell of the groups grid. Those past the titles set are hidden.
@property (nonatomic, readonly) NSArray<QLMSkinButtonView *> *groupButtons;
@property (nonatomic, readonly) QLMSkinDisplayView *display;
@property (nonatomic, readonly) QLMSkinButtonView *muteButton;
@property (nonatomic, readonly) QLMSkinButtonView *dimButton;
@property (nonatomic, readonly) QLMKnobControl *knob;
@property (nonatomic, readonly) QLMSkinTextButton *monitorsButton;
@property (nonatomic, readonly) QLMSkinTextButton *powerButton;

// Shows a button per title, in order, each with its prefix, and hides the
// rest.
- (void)setGroupTitles:(NSArray<NSString *> *)titles prefixes:(NSArray<NSString *> *)prefixes;

@end

// A window in the main window's chrome: its title bar transparent and its
// title hidden, with the content under it, dragged by its background, and
// no smaller than the skin. Its content view is an empty container at the
// skin's size, for QLMSkinHost.
NSWindow *QLMSkinHostWindow(QLMSkin *skin, NSWindowStyleMask style);

// Puts `view` in the window's content view, in place of what was there, and
// keeps it filling the window. TRAP: dump_screenshot draws a content view
// with no layer into an unflipped context, so a flipped content view, as
// the skin views are, comes out upside down. So the window's content view
// is an unflipped container.
void QLMSkinHost(NSWindow *window, NSView *view);

NS_ASSUME_NONNULL_END
