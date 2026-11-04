#import <XCTest/XCTest.h>

#import "QLMSkin.h"
#import "QLMSkinLibrary.h"
#import "QLMTestSupport.h"

// The skin reader: the shipped modern skin, the image fixture, and each
// refusal. Source: docs/ui.md, How skins work, and qlm/App/Skins/README.md.
@interface QLMSkinTests : XCTestCase
@end

#define QLMAssertColor(color, r, g, b, a)                       \
    do {                                                        \
        QLMSkinColor c_ = (color);                              \
        XCTAssertEqualWithAccuracy(c_.red, (r) / 255.0, 1e-9);   \
        XCTAssertEqualWithAccuracy(c_.green, (g) / 255.0, 1e-9); \
        XCTAssertEqualWithAccuracy(c_.blue, (b) / 255.0, 1e-9);  \
        XCTAssertEqualWithAccuracy(c_.alpha, (a) / 255.0, 1e-9); \
    } while (0)

@implementation QLMSkinTests {
    NSURL *_work;
}

- (void)setUp {
    [super setUp];
    _work = [NSURL fileURLWithPath:QLMScratchPath() isDirectory:YES];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_work error:NULL];
    [super tearDown];
}

// A copy of the skin at `source`, its JSON changed by `change`, read. The
// copy's directory is named "changed".
- (nullable QLMSkin *)skin:(NSURL *)source
                 changedBy:(void (^_Nullable)(NSMutableDictionary *json))change
                     error:(NSError **)error {
    NSURL *directory = [_work URLByAppendingPathComponent:@"changed" isDirectory:YES];
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES
                                                          attributes:nil error:NULL]);
    NSURL *png = [source URLByAppendingPathComponent:@"png"];
    if ([NSFileManager.defaultManager fileExistsAtPath:png.path]) {
        XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:png toURL:[directory URLByAppendingPathComponent:@"png"]
                                                            error:NULL]);
    }
    NSData *data = [NSData dataWithContentsOfURL:[source URLByAppendingPathComponent:@"skin.json"]];
    NSMutableDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    if (change) {
        change(json);
    }
    NSData *changed = [NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
    XCTAssertTrue([changed writeToURL:[directory URLByAppendingPathComponent:@"skin.json"] atomically:NO]);
    return [QLMSkin skinAtURL:directory error:error];
}

- (nullable QLMSkin *)fixtureChangedBy:(void (^_Nullable)(NSMutableDictionary *json))change error:(NSError **)error {
    return [self skin:QLMFixtureSkinURL() changedBy:change error:error];
}

// The skin at `source`, changed, is refused, and the reason contains
// `reason`.
- (void)assertChangeTo:(NSURL *)source change:(void (^)(NSMutableDictionary *json))change refusedWith:(NSString *)reason {
    NSError *error = nil;
    QLMSkin *skin = [self skin:source changedBy:change error:&error];
    XCTAssertNil(skin);
    XCTAssertEqualObjects(error.domain, QLMSkinErrorDomain);
    XCTAssertEqual(error.code, QLMSkinErrorInvalid);
    XCTAssertTrue([error.localizedDescription hasPrefix:@"The skin changed is refused. "], @"%@", error.localizedDescription);
    XCTAssertTrue([error.localizedDescription containsString:reason], @"%@ lacks %@", error.localizedDescription, reason);
}

- (void)assertChange:(void (^)(NSMutableDictionary *json))change refusedWith:(NSString *)reason {
    [self assertChangeTo:QLMFixtureSkinURL() change:change refusedWith:reason];
}

#pragma mark - The shipped skin

- (void)testModernLoads {
    NSError *error = nil;
    QLMSkin *skin = [QLMSkin skinAtURL:QLMModernSkinURL() error:&error];
    XCTAssertNotNil(skin, @"%@", error.localizedDescription);
    XCTAssertEqualObjects(skin.name, @"modern");
    XCTAssertTrue(CGSizeEqualToSize(skin.windowSize, CGSizeMake(640, 480)));
    XCTAssertTrue(CGRectEqualToRect(skin.osd.frame, CGRectMake(0, 0, 480, 150)));
    // The palette's accent, through the LED that names it.
    QLMAssertColor(skin.led.on, 0xfd, 0xa0, 0x6c, 0xff);
}

// Modern ships no image: every element draws.
- (void)testModernDrawsEveryElement {
    QLMSkin *skin = [QLMSkin skinAtURL:QLMModernSkinURL() error:NULL];
    for (QLMSkinStyle *style in @[[skin element:@"panel"].style, [skin element:@"nameplate"].style,
                                  [skin element:@"display"].style, skin.osd.style, skin.button.style, skin.knob.body]) {
        XCTAssertNil(style.imageName);
        XCTAssertNotNil([style drawForState:QLMSkinStateNormal]);
    }
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:[QLMModernSkinURL() URLByAppendingPathComponent:@"png"].path]);
}

// A selected state takes selected's overrides, then its own. Modern's
// selected border is the accent, and stays so on hover.
- (void)testModernsButtonStatesMergeOverSelected {
    QLMSkin *skin = [QLMSkin skinAtURL:QLMModernSkinURL() error:NULL];
    QLMSkinStyle *style = skin.button.style;
    QLMAssertColor([style drawForState:QLMSkinStateNormal].fill, 0x3e, 0x3f, 0x3a, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateNormal].border, 0x56, 0x58, 0x4f, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateHover].fill, 0x45, 0x46, 0x3f, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateHover].border, 0x56, 0x58, 0x4f, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateSelected].border, 0xfd, 0xa0, 0x6c, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateSelectedHover].fill, 0x61, 0x40, 0x2e, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateSelectedHover].border, 0xfd, 0xa0, 0x6c, 0xff);
    QLMAssertColor([style drawForState:QLMSkinStateSelectedDisabled].border, 0x76, 0x56, 0x3f, 0xff);
    XCTAssertEqual([style drawForState:QLMSkinStateSelectedPressed].radius, 6);
    XCTAssertNotNil([style drawForState:QLMSkinStatePressed].shadow);
}

- (void)testModernsKnobHasAnArcAndNoTicks {
    QLMSkinKnob *knob = [QLMSkin skinAtURL:QLMModernSkinURL() error:NULL].knob;
    XCTAssertTrue(knob.hasArc);
    XCTAssertEqual(knob.tickCount, 0);
    XCTAssertEqual(knob.bodySize, 136);
    XCTAssertGreaterThan(knob.arcRadius, knob.bodySize / 2);
    XCTAssertLessThan(knob.pointerOuter, knob.bodySize / 2);
}

#pragma mark - The built-in skins

// Each skin the app ships loads with no refusal. The reader checks that each
// image it names is there at 1x and 2x, so loading is the test.
- (void)testEveryBuiltInSkinLoads {
    QLMSkinLibrary *library = [[QLMSkinLibrary alloc] initWithBuiltIn:QLMBuiltInSkinsURL() user:nil];
    NSArray<NSString *> *names = [library skinNames];
    XCTAssertEqualObjects(names, (@[@"modern", @"retro", @"vintage"]));
    for (NSString *name in names) {
        NSString *refusal = nil;
        QLMSkin *skin = [library loadSkinNamed:name refusal:&refusal];
        XCTAssertNil(refusal, @"%@", refusal);
        XCTAssertEqualObjects(skin.name, name);
    }
}

// Vintage and retro draw from the pack's sixteen images, and every other
// part from colors and metrics. The repository's png/ holds the pack's
// thirty, and the app ships the sixteen, so a skin that named a drawn part
// would load here and be refused in the app.
- (void)testVintageAndRetroUseTheSixteenImages {
    NSSet<NSString *> *sixteen = [NSSet setWithArray:@[
        @"panel-background", @"nameplate", @"display-glass", @"osd-background",
        @"button-normal", @"button-hover", @"button-pressed", @"button-disabled",
        @"button-selected", @"button-selected-hover", @"button-selected-pressed", @"button-selected-disabled",
        @"knob-body-normal", @"knob-body-hover", @"knob-body-pressed", @"knob-body-disabled",
    ]];
    NSURL *skins = QLMBuiltInSkinsURL();
    for (NSString *name in @[@"vintage", @"retro"]) {
        NSError *error = nil;
        QLMSkin *skin = [QLMSkin skinAtURL:[skins URLByAppendingPathComponent:name isDirectory:YES] error:&error];
        XCTAssertNotNil(skin, @"%@", error.localizedDescription);
        NSMutableSet<NSString *> *used = [NSMutableSet set];
        for (QLMSkinStyle *style in @[[skin element:@"panel"].style, [skin element:@"nameplate"].style,
                                      [skin element:@"display"].style, skin.osd.style]) {
            [used addObject:[style imageNameForState:QLMSkinStateNormal]];
        }
        for (NSInteger state = QLMSkinStateNormal; state <= QLMSkinStateSelectedDisabled; state++) {
            [used addObject:[skin.button.style imageNameForState:(QLMSkinState)state]];
        }
        for (NSInteger state = QLMSkinStateNormal; state <= QLMSkinStateDisabled; state++) {
            [used addObject:[skin.knob.body imageNameForState:(QLMSkinState)state]];
        }
        XCTAssertEqualObjects(used, sixteen, @"%@", name);
        XCTAssertEqual(skin.knob.tickCount, 11);
        XCTAssertEqual(skin.markings.boxes.count, 2u);
        XCTAssertNotNil([skin element:@"groups"].text[@"message"]);
    }
}

#pragma mark - The image fixture

- (void)testTheFixtureLoadsWithEveryImage {
    NSError *error = nil;
    QLMSkin *skin = [QLMSkin skinAtURL:QLMFixtureSkinURL() error:&error];
    XCTAssertNotNil(skin, @"%@", error.localizedDescription);
    XCTAssertEqualObjects([skin element:@"panel"].style.imageName, @"panel-background");
    XCTAssertNil([[skin element:@"panel"].style drawForState:QLMSkinStateNormal]);
    XCTAssertEqualObjects([[skin element:@"panel"].style imageNameForState:QLMSkinStateNormal], @"panel-background");
    XCTAssertEqualObjects([skin imageURLForName:@"nameplate" scale:2].lastPathComponent, @"nameplate@2x.png");
    XCTAssertEqualObjects([skin imageURLForName:@"nameplate" scale:1].lastPathComponent, @"nameplate.png");
}

// The pack's eight button faces and four knob bodies, by its names.
- (void)testTheFixturesStatesNameThePacksImages {
    QLMSkin *skin = [QLMSkin skinAtURL:QLMFixtureSkinURL() error:NULL];
    NSArray *buttons = @[@"button-normal", @"button-hover", @"button-pressed", @"button-disabled", @"button-selected",
                         @"button-selected-hover", @"button-selected-pressed", @"button-selected-disabled"];
    for (NSInteger state = QLMSkinStateNormal; state <= QLMSkinStateSelectedDisabled; state++) {
        XCTAssertEqualObjects([skin.button.style imageNameForState:(QLMSkinState)state], buttons[(NSUInteger)state]);
    }
    NSArray *bodies = @[@"knob-body-normal", @"knob-body-hover", @"knob-body-pressed", @"knob-body-disabled"];
    for (NSInteger state = QLMSkinStateNormal; state <= QLMSkinStateDisabled; state++) {
        XCTAssertEqualObjects([skin.knob.body imageNameForState:(QLMSkinState)state], bodies[(NSUInteger)state]);
    }
}

// Cap insets are top, left, bottom, right, as the pack's manifest orders
// them. One number is all four.
- (void)testTheFixturesCapInsets {
    QLMSkin *skin = [QLMSkin skinAtURL:QLMFixtureSkinURL() error:NULL];
    NSEdgeInsets panel = [skin element:@"panel"].style.capInsets;
    XCTAssertEqual(panel.top, 22);
    XCTAssertEqual(panel.left, 24);
    XCTAssertEqual(panel.bottom, 30);
    XCTAssertEqual(panel.right, 24);
    NSEdgeInsets button = skin.button.style.capInsets;
    XCTAssertEqual(button.bottom, 9);
    NSEdgeInsets display = [skin element:@"display"].style.capInsets;
    XCTAssertTrue(display.top == 6 && display.left == 6 && display.bottom == 6 && display.right == 6);
    XCTAssertEqual(skin.osd.style.capInsets.left, 9);
}

- (void)testTheFixturesGeometryAndText {
    QLMSkin *skin = [QLMSkin skinAtURL:QLMFixtureSkinURL() error:NULL];
    QLMSkinKnob *knob = skin.knob;
    XCTAssertEqual(knob.tickCount, 11);
    XCTAssertEqual(knob.tickInner, 73);
    XCTAssertEqual(knob.pointerOuter, 38);
    XCTAssertFalse(knob.hasArc);
    XCTAssertEqual(knob.shadow.offset.height, 4);

    QLMSkinTextSlot *logo = [skin element:@"nameplate"].text[@"logo"];
    XCTAssertEqualObjects(logo.fontName, @"Helvetica Neue");
    XCTAssertEqual(logo.weight, QLMSkinWeightBold);
    XCTAssertTrue(logo.italic);
    XCTAssertEqual(logo.alignment, QLMSkinAlignmentCenter);
    QLMAssertColor(logo.color, 0x34, 0x35, 0x2b, 0xff);
    XCTAssertTrue([skin element:@"display"].text[@"level"].scales);
    XCTAssertEqual([skin element:@"display"].text[@"max"].anchors, QLMSkinAnchorRight | QLMSkinAnchorBottom);
    XCTAssertEqual([skin element:@"nameplate"].anchors, QLMSkinAnchorLeft | QLMSkinAnchorTop);
    XCTAssertEqual([skin element:@"knob"].anchors, QLMSkinAnchorRight);

    XCTAssertEqual(skin.button.ledX, 28);
    XCTAssertEqual(skin.markings.boxes.count, 2u);
    XCTAssertEqualObjects(skin.markings.boxes[0].gap, @"groupsTitle");
    XCTAssertEqual(skin.markings.boxes[1].outset.left, 8);
    QLMAssertColor(skin.markings.color, 0xdf, 0xd4, 0xb9, 0xcc);
    XCTAssertTrue(CGRectEqualToRect(skin.osd.bar.frame, CGRectMake(145, 52, 130, 3)));
    XCTAssertEqual(skin.osd.text.count, 4u);
}

- (void)testTheStateRule {
    XCTAssertEqual(QLMSkinButtonState(YES, NO, YES, YES), QLMSkinStateSelectedDisabled);
    XCTAssertEqual(QLMSkinButtonState(NO, NO, YES, YES), QLMSkinStateDisabled);
    XCTAssertEqual(QLMSkinButtonState(YES, YES, YES, YES), QLMSkinStateSelectedPressed);
    XCTAssertEqual(QLMSkinButtonState(NO, YES, NO, YES), QLMSkinStateHover);
    XCTAssertEqual(QLMSkinButtonState(YES, YES, NO, NO), QLMSkinStateSelected);
    XCTAssertEqual(QLMSkinButtonState(NO, YES, NO, NO), QLMSkinStateNormal);
}

#pragma mark - Refusals

- (void)testNoFileIsRefused {
    NSError *error = nil;
    XCTAssertNil([QLMSkin skinAtURL:[_work URLByAppendingPathComponent:@"none"] error:&error]);
    XCTAssertEqual(error.code, QLMSkinErrorUnreadable);
    XCTAssertTrue([error.localizedDescription containsString:@"There is no skin.json"], @"%@", error.localizedDescription);
}

- (void)testAFileThatIsNotJSONIsRefused {
    NSURL *directory = [_work URLByAppendingPathComponent:@"broken"];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    [[@"{ \"format\": 1," dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[directory URLByAppendingPathComponent:@"skin.json"]
                                                                  atomically:NO];
    NSError *error = nil;
    XCTAssertNil([QLMSkin skinAtURL:directory error:&error]);
    XCTAssertEqual(error.code, QLMSkinErrorUnreadable);
    XCTAssertTrue([error.localizedDescription containsString:@"is not JSON"], @"%@", error.localizedDescription);
}

- (void)testAnotherFormatIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"format"] = @2;
    } refusedWith:@"format is 2"];
}

- (void)testAnUnknownKeyIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"layers"] = @[];
    } refusedWith:@"skin.json has an unknown key, layers"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"glow"] = @1;
    } refusedWith:@"elements.display has an unknown key, glow"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"level"][@"text"] = @"-42.0";
    } refusedWith:@"elements.display.text.level has an unknown key, text"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"LEVEL"] = json[@"elements"][@"display"][@"text"][@"caption"];
    } refusedWith:@"elements.display.text has an unknown key, LEVEL"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"logo"] = json[@"elements"][@"nameplate"];
    } refusedWith:@"elements has an unknown key, logo"];
}

- (void)testAMissingElementIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        [json[@"elements"] removeObjectForKey:@"knob"];
    } refusedWith:@"elements has no knob"];
    [self assertChange:^(NSMutableDictionary *json) {
        [json removeObjectForKey:@"osd"];
    } refusedWith:@"skin.json has no osd"];
}

- (void)testAMissingSlotIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        [json[@"elements"][@"display"][@"text"] removeObjectForKey:@"level"];
    } refusedWith:@"elements.display.text has no level"];
    [self assertChange:^(NSMutableDictionary *json) {
        [json[@"osd"][@"text"] removeObjectForKey:@"subtitle"];
    } refusedWith:@"osd.text has no subtitle"];
}

- (void)testAFrameOutsideTheWindowIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"frame"] = @[@300, @184, @356, @132];
    } refusedWith:@"elements.display.frame is outside the window, 640 by 480"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"text"][@"caption"][@"frame"] = @[@54, @320, @69, @18];
    } refusedWith:@"elements.knob.text.caption is outside the window"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"osd"][@"text"][@"title"][@"frame"] = @[@145, @60, @136, @18];
    } refusedWith:@"osd.text.title is outside the OSD, 300 by 72"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"markings"][@"boxes"][0][@"outset"] = @60;
    } refusedWith:@"markings.boxes[0] is outside the window"];
}

- (void)testAMissingImageIsRefused {
    for (NSString *file in @[@"button-selected-hover@2x.png", @"knob-body-disabled.png", @"panel-background@2x.png"]) {
        NSError *error = nil;
        XCTAssertNil([self fixtureChangedBy:^(NSMutableDictionary *json) {
            NSURL *image = [self->_work URLByAppendingPathComponent:[@"changed/png" stringByAppendingPathComponent:file]];
            XCTAssertTrue([NSFileManager.defaultManager removeItemAtURL:image error:NULL]);
        } error:&error]);
        NSString *wanted = [@"but the skin has no png/" stringByAppendingString:file];
        XCTAssertTrue([error.localizedDescription containsString:wanted], @"%@", error.localizedDescription);
    }
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"nameplate"][@"image"] = @"badge";
    } refusedWith:@"elements.nameplate names the image badge, but the skin has no png/badge.png"];
}

- (void)testAnImageAndADrawTogetherAreRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"draw"] = [@{@"fill": @"#000000"} mutableCopy];
    } refusedWith:@"elements.display has both an image and a draw"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"button"][@"draw"] = [@{} mutableCopy];
    } refusedWith:@"button has both an image and a draw"];
    [self assertChange:^(NSMutableDictionary *json) {
        [json[@"elements"][@"display"] removeObjectForKey:@"image"];
    } refusedWith:@"elements.display has neither an image nor a draw"];
}

- (void)testABadColorIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"level"][@"color"] = @"#ec917";
    } refusedWith:@"elements.display.text.level.color is #ec917, which is not #RRGGBB or #RRGGBBAA"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"led"][@"on"] = @"#gg0000";
    } refusedWith:@"led.on is #gg0000"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"palette"][@"label"] = @"beige";
    } refusedWith:@"palette.label is beige, which is not #RRGGBB or #RRGGBBAA"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"led"][@"off"] = @"amber";
    } refusedWith:@"led.off names amber, which the palette lacks"];
}

- (void)testASizeBelowTheReferenceIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"size"] = @[@600, @480];
    } refusedWith:@"size is 600 by 480, below the reference, 640 by 480"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"osd"][@"size"] = @[@300, @60];
    } refusedWith:@"osd.size is 300 by 60, below the reference, 300 by 72"];
}

- (void)testABadValueIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"groups"][@"anchors"] = @[@"left", @"middle"];
    } refusedWith:@"elements.groups.anchors has middle"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"level"][@"size"] = @"large";
    } refusedWith:@"elements.display.text.level.size is not a number"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"max"][@"alignment"] = @"justified";
    } refusedWith:@"elements.display.text.max.alignment is not one of left, center, right"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"toggles"][@"columns"] = @1;
    } refusedWith:@"elements.toggles has 1 cells, fewer than its 2 buttons"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"markings"][@"boxes"][0][@"gap"] = @"title";
    } refusedWith:@"markings.boxes[0].gap names title, which is not a slot of groups"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"panel"][@"image"] = [NSNull null];
    } refusedWith:@"elements.panel.image is not a name"];
}

// A user's skin is read at launch, so no shape may crash the reader.
- (void)testAnElementThatIsNotAnObjectIsRefused {
    // Each element by one shape, then each shape on one element.
    for (NSString *name in QLMSkinElementNames()) {
        [self assertChange:^(NSMutableDictionary *json) {
            json[@"elements"][name] = @1;
        } refusedWith:[NSString stringWithFormat:@"elements.%@ is not an object", name]];
    }
    for (id value in @[@[], @"display", [NSNull null]]) {
        [self assertChange:^(NSMutableDictionary *json) {
            json[@"elements"][@"display"] = value;
        } refusedWith:@"elements.display is not an object"];
    }
    for (NSString *key in @[@"palette", @"elements", @"button", @"led", @"markings", @"osd"]) {
        [self assertChange:^(NSMutableDictionary *json) {
            json[key] = @[];
        } refusedWith:[key stringByAppendingString:@" is not an object"]];
    }
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"level"] = @7;
    } refusedWith:@"elements.display.text.level is not an object"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"body"] = @"round";
    } refusedWith:@"elements.knob.body is not an object"];
}

- (void)testAnImageNameOutsidePngIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"panel"][@"image"] = @"../panel-background";
    } refusedWith:@"elements.panel.image is ../panel-background, which is not a file name in png/"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"panel"][@"image"] = @".hidden";
    } refusedWith:@"elements.panel.image is .hidden, which is not a file name in png/"];
}

- (void)testBadCapInsetsAreRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"panel"][@"capInsets"] = @[@22, @-1, @30, @24];
    } refusedWith:@"elements.panel.capInsets has an inset below 0"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"nameplate"][@"capInsets"] = @[@6, @40, @6, @40];
    } refusedWith:@"elements.nameplate.capInsets is larger than its frame, 78 by 38"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"button"][@"capInsets"] = @[@8, @100, @9, @100];
    } refusedWith:@"button.capInsets is larger than its frame, 174 by 40"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"osd"][@"capInsets"] = @40;
    } refusedWith:@"osd.capInsets is larger than its frame, 300 by 72"];
}

// The fixture's knob frame is 176 points, so 88 from its center.
- (void)testAKnobRadiusPastItsFrameIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"body"][@"size"] = @180;
    } refusedWith:@"elements.knob.body.size reaches past half the knob's frame, 88"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"pointer"][@"outer"] = @90;
    } refusedWith:@"elements.knob.pointer.outer reaches past half the knob's frame"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"ticks"][@"outer"] = @89;
    } refusedWith:@"elements.knob.ticks.outer reaches past half the knob's frame"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"arc"] = [@{@"radius": @87, @"width": @4, @"track": @"label", @"fill": @"display"} mutableCopy];
    } refusedWith:@"elements.knob.arc.radius reaches past half the knob's frame"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"body"] = [@{
            @"size": @144,
            @"draw": @{@"fill": @"label", @"rings": @[@{@"inset": @-20, @"color": @"label"}]},
        } mutableCopy];
    } refusedWith:@"elements.knob.body.draw.rings[0] reaches past half the knob's frame"];
}

- (void)testAGapThatLeavesNoCellIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"groups"][@"gap"] = @[@273, @0];
    } refusedWith:@"elements.groups's gap leaves its cells no room"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"toggles"][@"rows"] = @2;
        json[@"elements"][@"toggles"][@"gap"] = @[@8, @40];
    } refusedWith:@"elements.toggles's gap leaves its cells no room"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"groups"][@"gap"] = @[@-4, @0];
    } refusedWith:@"elements.groups.gap is below 0"];
}

- (void)testAnLEDPastTheButtonIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"button"][@"led"][@"x"] = @160;
    } refusedWith:@"button.led.x puts the LED past the button's width, 174"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"button"][@"led"][@"size"] = @41;
    } refusedWith:@"button.led.size is taller than the button, 40"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"button"][@"led"] = [@{@"size": @16, @"gap": @170} mutableCopy];
    } refusedWith:@"button.led leaves the title no room in the button's width, 174"];
}

// The strokes' round caps, and the focus ring, count toward a radius.
- (void)testAKnobStrokePastItsFrameIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"pointer"][@"outer"] = @87;
        json[@"elements"][@"knob"][@"pointer"][@"width"] = @4;
    } refusedWith:@"elements.knob.pointer.outer reaches past half the knob's frame, 88"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"ticks"][@"outer"] = @87.6;
        json[@"elements"][@"knob"][@"ticks"][@"width"] = @2;
    } refusedWith:@"elements.knob.ticks.outer reaches past half the knob's frame, 88"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"knob"][@"focus"][@"outset"] = @20;
    } refusedWith:@"elements.knob.focus reaches past half the knob's frame, 88"];
}

// A scaled slot grows from its element's origin, so it must start inside.
- (void)testAScaledSlotOutsideItsElementIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"level"][@"frame"] = @[@300, @35, @213, @65];
    } refusedWith:@"elements.display.text.level is outside the element display, 356 by 132"];
    // Unscaled, the same frame is fine: it stays where it is.
    NSError *error = nil;
    QLMSkin *skin = [self fixtureChangedBy:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"text"][@"output"][@"frame"] = @[@300, @95, @213, @15];
    } error:&error];
    XCTAssertNotNil(skin, @"%@", error.localizedDescription);
}

// A drawn element's states are its kind's: none for one with one state.
- (void)testStatesOnAOneStateElementAreRefused {
    [self assertChangeTo:QLMModernSkinURL() change:^(NSMutableDictionary *json) {
        json[@"elements"][@"display"][@"draw"][@"states"] = [@{@"hover": @{}} mutableCopy];
    } refusedWith:@"elements.display.draw has states, but its element takes one"];
}

// The OSD keeps its size, so its slots have nothing to place them by.
- (void)testAnOSDSlotThatWouldMoveIsRefused {
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"osd"][@"text"][@"level"][@"scales"] = @YES;
    } refusedWith:@"osd.text.level has scales, but the OSD keeps its size"];
    [self assertChange:^(NSMutableDictionary *json) {
        json[@"osd"][@"text"][@"title"][@"anchors"] = @[@"right"];
    } refusedWith:@"osd.text.title has anchors, but the OSD keeps its size"];
}

#pragma mark - The library

- (void)testTheLibraryListsTheAppsSkinsFirstAndFallsBackToModern {
    NSURL *builtIn = [_work URLByAppendingPathComponent:@"app"];
    NSURL *user = [_work URLByAppendingPathComponent:@"user"];
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtURL:builtIn withIntermediateDirectories:YES attributes:nil error:NULL];
    [files createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:NULL];
    XCTAssertTrue([files copyItemAtURL:QLMModernSkinURL() toURL:[builtIn URLByAppendingPathComponent:@"modern"] error:NULL]);
    XCTAssertTrue([files copyItemAtURL:QLMFixtureSkinURL() toURL:[user URLByAppendingPathComponent:@"fixture"] error:NULL]);
    XCTAssertTrue([files copyItemAtURL:QLMModernSkinURL() toURL:[user URLByAppendingPathComponent:@"modern"] error:NULL]);
    [files createDirectoryAtURL:[user URLByAppendingPathComponent:@"broken"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [[@"[]" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[user URLByAppendingPathComponent:@"broken/skin.json"] atomically:NO];
    [files createDirectoryAtURL:[user URLByAppendingPathComponent:@"empty"] withIntermediateDirectories:YES attributes:nil error:NULL];

    QLMSkinLibrary *library = [[QLMSkinLibrary alloc] initWithBuiltIn:builtIn user:user];
    XCTAssertEqualObjects([library skinNames], (@[@"modern", @"broken", @"fixture"]));
    XCTAssertTrue([library isBuiltIn:@"modern"]);
    XCTAssertFalse([library isBuiltIn:@"fixture"]);

    NSString *refusal = @"stale";
    QLMSkin *fixture = [library loadSkinNamed:@"fixture" refusal:&refusal];
    XCTAssertEqualObjects(fixture.name, @"fixture");
    XCTAssertNil(refusal);

    QLMSkin *fallback = [library loadSkinNamed:@"broken" refusal:&refusal];
    XCTAssertEqualObjects(fallback.name, @"modern");
    XCTAssertEqualObjects(fallback.directory.URLByDeletingLastPathComponent.lastPathComponent, @"app");
    XCTAssertTrue([refusal hasPrefix:@"The skin broken is refused. skin.json is not an object"], @"%@", refusal);

    XCTAssertEqualObjects([library loadSkinNamed:@"vintage" refusal:&refusal].name, @"modern");
    XCTAssertTrue([refusal containsString:@"There is no skin.json"], @"%@", refusal);
    XCTAssertEqualObjects([library loadSkinNamed:@"../app/modern" refusal:&refusal].name, @"modern");
    XCTAssertEqualObjects(refusal, @"There is no skin named ../app/modern.");
}

// Only Settings' Show in Finder makes the user's folder.
- (void)testTheLibraryMakesNoFolder {
    NSURL *builtIn = [_work URLByAppendingPathComponent:@"app"];
    NSURL *user = [_work URLByAppendingPathComponent:@"user"];
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtURL:builtIn withIntermediateDirectories:YES attributes:nil error:NULL];
    XCTAssertTrue([files copyItemAtURL:QLMModernSkinURL() toURL:[builtIn URLByAppendingPathComponent:@"modern"] error:NULL]);

    QLMSkinLibrary *library = [[QLMSkinLibrary alloc] initWithBuiltIn:builtIn user:user];
    XCTAssertEqualObjects([library skinNames], @[@"modern"]);
    NSString *refusal = nil;
    XCTAssertEqualObjects([library loadSkinNamed:@"fixture" refusal:&refusal].name, @"modern");
    XCTAssertEqualObjects(library.userDirectory, user);
    XCTAssertFalse([files fileExistsAtPath:user.path]);
}

- (void)testSettingsNoteSaysWhyOrWhereSkinsGo {
    XCTAssertEqualObjects(QLMSkinNote(@"The skin broken is refused. skin.json is not an object.", @"modern", nil),
                          @"The skin broken is refused. skin.json is not an object. modern shows instead.");
    NSURL *user = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/qlm/Skins"]];
    XCTAssertEqualObjects(QLMSkinNote(nil, @"retro", user),
                          @"A skin is a folder with skin.json and png/ in ~/Library/Application Support/qlm/Skins. "
                          @"qlm/App/Skins/README.md gives the format.");
}

@end
