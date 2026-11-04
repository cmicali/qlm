#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A skin, read from its directory's skin.json into values. Foundation only,
// so the hostless tests read it. It loads no image: it only checks that each
// one is there. qlm/App/Skins/README.md gives the file's keys.
//
// Every frame is in points, with the origin at the top left. An element's
// frame is in the window, or in the OSD for the OSD's. A text slot's frame is
// in its element.

extern NSErrorDomain const QLMSkinErrorDomain;

typedef NS_ENUM(NSInteger, QLMSkinError) {
    QLMSkinErrorUnreadable = 1,  // no file, or not JSON
    QLMSkinErrorInvalid,         // anything else the reader refuses
};

// The window's elements, in the order the reader reads them.
NSArray<NSString *> *QLMSkinElementNames(void);

// A skin's or an image's name: a plain file name, with no / and no leading
// dot, so it names nothing outside its directory.
BOOL QLMSkinIsPlainName(NSString *name);

// sRGB components, 0 to 1. A clear color draws nothing.
typedef struct {
    double red, green, blue, alpha;
} QLMSkinColor;

extern const QLMSkinColor QLMSkinColorClear;

// The edges an element, or a slot in it, keeps its distance to as the
// window grows. Both edges of an axis stretch it along that axis. One keeps
// it at that edge. Neither keeps it centered.
typedef NS_OPTIONS(NSUInteger, QLMSkinAnchors) {
    QLMSkinAnchorLeft = 1 << 0,
    QLMSkinAnchorRight = 1 << 1,
    QLMSkinAnchorTop = 1 << 2,
    QLMSkinAnchorBottom = 1 << 3,
};

typedef NS_ENUM(NSInteger, QLMSkinAlignment) {
    QLMSkinAlignmentLeft,
    QLMSkinAlignmentCenter,
    QLMSkinAlignmentRight,
};

typedef NS_ENUM(NSInteger, QLMSkinWeight) {
    QLMSkinWeightUltraLight,
    QLMSkinWeightThin,
    QLMSkinWeightLight,
    QLMSkinWeightRegular,
    QLMSkinWeightMedium,
    QLMSkinWeightSemibold,
    QLMSkinWeightBold,
    QLMSkinWeightHeavy,
    QLMSkinWeightBlack,
};

// The pack's states. A button takes all eight, a knob's body the first
// four but selected, and every other element normal alone. The rule that
// picks one is QLMSkinButtonState.
typedef NS_ENUM(NSInteger, QLMSkinState) {
    QLMSkinStateNormal,
    QLMSkinStateHover,
    QLMSkinStatePressed,
    QLMSkinStateDisabled,
    QLMSkinStateSelected,
    QLMSkinStateSelectedHover,
    QLMSkinStateSelectedPressed,
    QLMSkinStateSelectedDisabled,
};

// Disabled first, then pressed, then hover, then normal. Selection is
// independent. A knob's body is never selected.
QLMSkinState QLMSkinButtonState(BOOL selected, BOOL enabled, BOOL pressed, BOOL hovered);

@interface QLMSkinShadow : NSObject
@property (nonatomic, readonly) QLMSkinColor color;
@property (nonatomic, readonly) CGFloat blur;
@property (nonatomic, readonly) CGSize offset;  // y down
@end

@interface QLMSkinRing : NSObject
@property (nonatomic, readonly) CGFloat inset;
@property (nonatomic, readonly) QLMSkinColor color;
@property (nonatomic, readonly) CGFloat width;
@end

// A draw block, for one state, with its state's overrides merged in.
@interface QLMSkinDraw : NSObject
@property (nonatomic, readonly) QLMSkinColor fill;
@property (nonatomic, readonly) BOOL hasGradient;
@property (nonatomic, readonly) QLMSkinColor gradientTop;
@property (nonatomic, readonly) QLMSkinColor gradientBottom;
@property (nonatomic, readonly) QLMSkinColor border;
@property (nonatomic, readonly) CGFloat borderWidth;
@property (nonatomic, readonly) CGFloat radius;
@property (nonatomic, readonly) CGFloat inset;
@property (nonatomic, readonly) NSArray<QLMSkinRing *> *rings;
@property (nonatomic, readonly, nullable) QLMSkinShadow *shadow;
@end

// An element's material: images, or a draw block per state.
@interface QLMSkinStyle : NSObject
// Nil for a drawn element. For one with states, each state's image is
// "<imageName>-<state>".
@property (nonatomic, readonly, copy, nullable) NSString *imageName;
@property (nonatomic, readonly) NSEdgeInsets capInsets;
// The image file's name for a state, without png/ or the scale.
- (NSString *)imageNameForState:(QLMSkinState)state;
// Nil for an image element.
- (nullable QLMSkinDraw *)drawForState:(QLMSkinState)state;
@end

// A text the app fills. The skin says where and how; the app says what.
@interface QLMSkinTextSlot : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) CGRect frame;  // in its element
@property (nonatomic, readonly) QLMSkinAnchors anchors;
// Scales its frame and its size with its element, from the element's
// origin, by the smaller of its height's and its width's growth. Its anchors
// then don't apply.
@property (nonatomic, readonly) BOOL scales;
// Nil, or a face the Mac lacks: the system font, or the system monospaced
// font for a mono slot.
@property (nonatomic, readonly, copy, nullable) NSString *fontName;
@property (nonatomic, readonly) BOOL mono;
@property (nonatomic, readonly) CGFloat size;
@property (nonatomic, readonly) QLMSkinWeight weight;
@property (nonatomic, readonly) BOOL italic;
@property (nonatomic, readonly) QLMSkinAlignment alignment;
@property (nonatomic, readonly) QLMSkinColor color;
@property (nonatomic, readonly) CGFloat tracking;
// The color of the text's last character when it is the slot's accent
// character, as the logo's period. Clear when unset.
@property (nonatomic, readonly) QLMSkinColor accentColor;
@end

// A box around elements, or a line, drawn in the markings' color.
@interface QLMSkinLine : NSObject
@property (nonatomic, readonly, copy) NSString *element;
@property (nonatomic, readonly) CGFloat y;  // from the element's top
@end

@interface QLMSkinBox : NSObject
@property (nonatomic, readonly, copy) NSString *element;
@property (nonatomic, readonly) NSEdgeInsets outset;
@property (nonatomic, readonly) CGFloat radius;
// A slot of the element the box's top edge breaks around, or nil.
@property (nonatomic, readonly, copy, nullable) NSString *gap;
@end

@interface QLMSkinMarkings : NSObject
@property (nonatomic, readonly) QLMSkinColor color;
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic, readonly) NSArray<QLMSkinLine *> *lines;
@property (nonatomic, readonly) NSArray<QLMSkinBox *> *boxes;
@end

@interface QLMSkinLED : NSObject
@property (nonatomic, readonly) QLMSkinColor on;
@property (nonatomic, readonly) QLMSkinColor off;
@property (nonatomic, readonly) CGFloat glow;
@end

@interface QLMSkinFocus : NSObject
@property (nonatomic, readonly) QLMSkinColor color;
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic, readonly) CGFloat radius;
@property (nonatomic, readonly) CGFloat outset;
@end

// A button's title, centered in its face.
@interface QLMSkinTitle : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *fontName;
@property (nonatomic, readonly) CGFloat size;
@property (nonatomic, readonly) QLMSkinWeight weight;
@property (nonatomic, readonly) CGFloat tracking;
@property (nonatomic, readonly) QLMSkinColor color;
@property (nonatomic, readonly) QLMSkinColor selectedColor;
@property (nonatomic, readonly) QLMSkinColor disabledColor;
// A group's letter, before its name.
@property (nonatomic, readonly) QLMSkinColor prefixColor;
@end

@interface QLMSkinButton : NSObject
@property (nonatomic, readonly) QLMSkinStyle *style;  // eight states
@property (nonatomic, readonly) QLMSkinTitle *title;
@property (nonatomic, readonly) QLMSkinFocus *focus;
@property (nonatomic, readonly) CGFloat ledSize;
// Below 0, the LED sits just before the title, ledGap from it. Else it sits
// this far from the button's left edge, and the title stays centered.
@property (nonatomic, readonly) CGFloat ledX;
@property (nonatomic, readonly) CGFloat ledGap;
@end

@interface QLMSkinKnob : NSObject
@property (nonatomic, readonly) CGFloat bodySize;  // the body's diameter
@property (nonatomic, readonly) QLMSkinStyle *body;  // four states
@property (nonatomic, readonly) NSInteger tickCount;  // 0 for none
@property (nonatomic, readonly) CGFloat tickInner;    // radii from the center
@property (nonatomic, readonly) CGFloat tickOuter;
@property (nonatomic, readonly) CGFloat tickWidth;
@property (nonatomic, readonly) QLMSkinColor tickColor;
@property (nonatomic, readonly) CGFloat pointerInner;
@property (nonatomic, readonly) CGFloat pointerOuter;
@property (nonatomic, readonly) CGFloat pointerWidth;
@property (nonatomic, readonly) QLMSkinColor pointerColor;
@property (nonatomic, readonly) QLMSkinColor pointerDisabledColor;
@property (nonatomic, readonly, nullable) QLMSkinShadow *shadow;
// The radius of the disc that casts the shadow. The body's, less 1, unless
// the skin gives one, as an image body with margin around its knob does.
@property (nonatomic, readonly) CGFloat shadowRadius;
@property (nonatomic, readonly) QLMSkinFocus *focus;
@property (nonatomic, readonly) BOOL hasArc;
@property (nonatomic, readonly) CGFloat arcRadius;
@property (nonatomic, readonly) CGFloat arcWidth;
@property (nonatomic, readonly) QLMSkinColor arcTrack;
@property (nonatomic, readonly) QLMSkinColor arcFill;
@end

// The OSD's level bar.
@interface QLMSkinBar : NSObject
@property (nonatomic, readonly) CGRect frame;  // in the OSD
@property (nonatomic, readonly) QLMSkinColor track;
@property (nonatomic, readonly) QLMSkinColor fill;
@property (nonatomic, readonly) CGFloat radius;
@end

// A placed element. Its extras are its kind's: a grid's cells, the status
// LED, the footer's symbols, the display's and the OSD's overlay.
@interface QLMSkinElement : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly) QLMSkinAnchors anchors;
@property (nonatomic, readonly, nullable) QLMSkinStyle *style;
@property (nonatomic, readonly) NSDictionary<NSString *, QLMSkinTextSlot *> *text;
@property (nonatomic, readonly) NSInteger columns;  // groups and toggles
@property (nonatomic, readonly) NSInteger rows;
@property (nonatomic, readonly) CGSize gap;
@property (nonatomic, readonly) CGRect ledFrame;  // status, in the element
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *symbols;  // footer: slot to SF Symbol
@property (nonatomic, readonly) QLMSkinColor disabledOverlay;  // display and osd
@property (nonatomic, readonly, nullable) QLMSkinBar *bar;  // osd
@end

@interface QLMSkin : NSObject

// Reads <directory>/skin.json. Nil, with the reason in the error's
// description, for anything the reader refuses.
+ (nullable instancetype)skinAtURL:(NSURL *)directory error:(NSError **)error;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSString *name;  // the directory's
@property (nonatomic, readonly) NSURL *directory;
@property (nonatomic, readonly) CGSize windowSize;  // the reference, and the least
// By QLMSkinElementNames.
@property (nonatomic, readonly) NSDictionary<NSString *, QLMSkinElement *> *elements;
// Its frame is the OSD's size, at the origin. The OSD has no layout, so its
// slots have neither anchors nor scales.
@property (nonatomic, readonly) QLMSkinElement *osd;
@property (nonatomic, readonly) QLMSkinButton *button;
@property (nonatomic, readonly) QLMSkinKnob *knob;
@property (nonatomic, readonly) QLMSkinLED *led;
@property (nonatomic, readonly) QLMSkinMarkings *markings;

- (QLMSkinElement *)element:(NSString *)name;
// png/<name>.png, or png/<name>@2x.png at scale 2.
- (NSURL *)imageURLForName:(NSString *)name scale:(NSInteger)scale;

@end

NS_ASSUME_NONNULL_END
