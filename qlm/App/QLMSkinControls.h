#import <Cocoa/Cocoa.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// The skin's element views. Each draws its element from the skin and the
// state its controller hands it, by the pack's state rules. None reads a
// snapshot or drives System. A setter given the value it has redraws
// nothing.

// A control that tracks hover, a press, and keyboard focus, and draws its
// own focus ring. A click inside sends the action. Space and Return click
// it while it has focus.
@interface QLMSkinControl : NSControl
- (instancetype)initWithSkin:(QLMSkin *)skin NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@property (nonatomic, readonly) QLMSkin *skin;
// Set by the control's own tracking. Each change redraws it.
@property (nonatomic, getter=isHovered) BOOL hovered;
@property (nonatomic, getter=isPressed) BOOL pressed;
// First responder in the key window.
@property (nonatomic, readonly, getter=isFocused) BOOL focused;
@end

// A face in the skin's button style: a group, Mute, or Dim.
@interface QLMSkinButtonView : QLMSkinControl
@property (nonatomic, copy) NSString *title;
// A group's letter, drawn before the title in the prefix color.
@property (nonatomic, copy, nullable) NSString *prefix;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic) BOOL showsLED;
@property (nonatomic) BOOL ledLit;
@end

// A footer button: an SF Symbol and a title, in a footer slot.
@interface QLMSkinTextButton : QLMSkinControl
- (instancetype)initWithSkin:(QLMSkin *)skin slot:(QLMSkinTextSlot *)slot symbol:(NSString *)symbol;
- (instancetype)initWithSkin:(QLMSkin *)skin NS_UNAVAILABLE;
@property (nonatomic, copy) NSString *title;
// The skin's symbol, or a stand-in where this macOS lacks it.
@property (nonatomic, readonly, copy) NSString *symbolName;
@end

// The status: an LED and the online count, or a bus problem's title.
@interface QLMSkinStatusView : NSView
- (instancetype)initWithSkin:(QLMSkin *)skin;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic) BOOL lit;
@property (nonatomic) BOOL enabled;
@end

// The display: the group's caption, the level and its unit, OUTPUT, and MAX.
@interface QLMSkinDisplayView : NSView
- (instancetype)initWithSkin:(QLMSkin *)skin;
@property (nonatomic, copy, nullable) NSString *caption;
@property (nonatomic, copy, nullable) NSString *level;
@property (nonatomic, copy, nullable) NSString *unit;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *max;
@property (nonatomic) BOOL disabled;
@end

// The OSD's content, at the skin's OSD size. The bar fills from its left by
// `fraction`, 0 to 1.
@interface QLMSkinOSDView : NSView
- (instancetype)initWithSkin:(QLMSkin *)skin;
@property (nonatomic, copy, nullable) NSString *level;
@property (nonatomic, copy, nullable) NSString *unit;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic) double fraction;
@property (nonatomic) BOOL disabled;
@end

NS_ASSUME_NONNULL_END
