#import "QLMSkinPreview.h"

#if DEBUG

#import "QLMSkinLibrary.h"
#import "QLMSkinView.h"

// A borderless window that can be key, so dump_screenshot takes it.
@interface QLMSkinPreviewWindow : NSWindow
@end

@implementation QLMSkinPreviewWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

@end

// TRAP: dump_screenshot draws a window's content view with no layer into
// an unflipped context, so a flipped content view, as the skin views are,
// comes out upside down. So the view fills an unflipped container.
static NSWindow *QLMSkinPreviewHost(NSWindow *window, NSView *view) {
    NSView *container = [[NSView alloc] initWithFrame:view.frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
    window.contentView = container;
    return window;
}

static NSWindow *QLMSkinPreviewMainWindow(QLMSkin *skin, BOOL disabled) {
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                              | NSWindowStyleMaskFullSizeContentView;
    NSRect frame = NSMakeRect(0, 0, skin.windowSize.width, skin.windowSize.height);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Skin preview";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.movableByWindowBackground = YES;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.contentMinSize = skin.windowSize;

    QLMSkinView *view = [[QLMSkinView alloc] initWithSkin:skin];
    view.logo = @"qlm.";
    view.tagline = @"REFERENCE CONTROL";
    view.groupsTitle = @"LISTENING SETUP";
    view.knobMin = @"−80";
    view.knobMax = @"−30";
    view.knobCaption = @"VOLUME";
    view.status.text = @"6 ONLINE";
    view.status.lit = YES;
    // The owner's setup file has four groups.
    [view setGroupTitles:@[@"MAIN 4X2", @"MAIN 2X2", @"MAIN 2X1", @"GROUP_4"] prefixes:@[@"A", @"B", @"C", @"D"]];
    view.groupButtons[0].selected = YES;
    view.display.caption = @"MAIN";
    view.display.level = @"−59.0";
    view.display.unit = @"dB";
    view.display.output = @"OUTPUT −59.0";
    view.display.max = @"MAX −30";
    view.muteButton.title = @"MUTE";
    view.dimButton.title = @"DIM −20";
    view.knob.minValue = -80;
    view.knob.maxValue = -30;
    view.knob.doubleValue = -59;
    view.monitorsButton.title = @"Monitors";
    view.powerButton.title = @"Standby";
    if (disabled) {
        NSArray<QLMSkinControl *> *others = @[view.muteButton, view.dimButton, view.knob, view.monitorsButton,
                                              view.powerButton];
        for (QLMSkinControl *control in [others arrayByAddingObjectsFromArray:view.groupButtons]) {
            control.enabled = NO;
        }
        view.status.enabled = NO;
        view.display.disabled = YES;
    }
    return QLMSkinPreviewHost(window, view);
}

static NSWindow *QLMSkinPreviewOSDWindow(QLMSkin *skin) {
    NSRect frame = skin.osd.frame;
    NSWindow *window = [[QLMSkinPreviewWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless
                                                                 backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Skin preview OSD";
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = YES;
    QLMSkinOSDView *view = [[QLMSkinOSDView alloc] initWithSkin:skin];
    view.level = @"−59.0";
    view.unit = @"dB";
    view.title = @"Main monitors";
    view.subtitle = @"qlm · Output level";
    view.fraction = (-59.0 + 80) / 50;
    return QLMSkinPreviewHost(window, view);
}

NSDictionary *QLMShowSkinPreview(NSString *name, BOOL osd, BOOL disabled) {
    static NSWindow *shown;
    NSString *refusal = nil;
    QLMSkin *skin = [[QLMSkinLibrary standardLibrary] loadSkinNamed:name refusal:&refusal];
    if (skin == nil) {
        return @{@"error": refusal ?: @"no skin loads"};
    }
    [shown close];
    shown = osd ? QLMSkinPreviewOSDWindow(skin) : QLMSkinPreviewMainWindow(skin, disabled);
    shown.releasedWhenClosed = NO;
    [shown center];
    [shown makeKeyAndOrderFront:nil];
    NSSize size = shown.contentView.frame.size;
    return @{
        @"ok": @YES,
        @"skin": skin.name,
        @"refusal": refusal ?: NSNull.null,
        @"size": @[@(size.width), @(size.height)],
    };
}

#endif
