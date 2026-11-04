#import <Cocoa/Cocoa.h>

#import "QLMKnobControl.h"
#import "QLMSkin.h"
#import "QLMSkinControls.h"
#import "QLMSkinLayout.h"

NS_ASSUME_NONNULL_BEGIN

// The main window's content view, in one skin. It draws the panel, the
// nameplate, the markings, and the panel's own text, and hosts one view per
// element, laid out by the resize pass with no Auto Layout. A controller
// hands each its state and text. It reads no snapshot and drives nothing:
// each control sends its action to the target the controller sets.
@interface QLMSkinView : NSView

- (instancetype)initWithSkin:(QLMSkin *)skin NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) QLMSkin *skin;
@property (nonatomic, readonly) QLMSkinLayout *skinLayout;  // for the view's size

// The panel's text.
@property (nonatomic, copy, nullable) NSString *logo;
@property (nonatomic, copy, nullable) NSString *tagline;
@property (nonatomic, copy, nullable) NSString *groupsTitle;
// In the groups' place while none show: the setup file's name, or its
// error.
@property (nonatomic, copy, nullable) NSString *groupsMessage;
@property (nonatomic, copy, nullable) NSString *knobMin;
@property (nonatomic, copy, nullable) NSString *knobMax;
@property (nonatomic, copy, nullable) NSString *knobCaption;

@property (nonatomic, readonly) QLMSkinStatusView *status;
// One per cell of the groups grid, as QLMSkinGroupButtonCount counts. Those past
// the titles set are hidden.
@property (nonatomic, readonly) NSArray<QLMSkinButtonView *> *groupButtons;
@property (nonatomic, readonly) QLMSkinDisplayView *display;
@property (nonatomic, readonly) QLMSkinButtonView *muteButton;
@property (nonatomic, readonly) QLMSkinButtonView *dimButton;
@property (nonatomic, readonly) QLMKnobControl *knob;
@property (nonatomic, readonly) QLMSkinTextButton *monitorsButton;
@property (nonatomic, readonly) QLMSkinTextButton *powerButton;

// Shows a button per title, in order, each with its prefix if given, and
// hides the rest.
- (void)setGroupTitles:(NSArray<NSString *> *)titles prefixes:(nullable NSArray<NSString *> *)prefixes;

@end

NS_ASSUME_NONNULL_END
