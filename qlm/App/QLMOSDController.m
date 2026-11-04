#import "QLMOSDController.h"

#import "QLMFormat.h"
#import "QLMOSDRule.h"
#import "QLMSkinControls.h"
#import "QLMSkinLibrary.h"

static const NSTimeInterval QLMOSDFadeSeconds = 0.25;

// A window that never becomes key or main, so a show takes no focus, and
// orderFrontRegardless never activates the app. TRAP: not an NSPanel.
// NSApp.orderedWindows leaves panels out, so dump_screenshot, which falls
// back to it while the app has no key window, could never take one.
@interface QLMOSDWindow : NSWindow
@end

@implementation QLMOSDWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

@end

@interface QLMOSDController ()
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic) QLMOSDRule *rule;
@property (nonatomic, nullable) QLMSkinOSDView *osdView;
@property (nonatomic, copy, nullable) NSString *skinName;
@property (nonatomic, nullable) NSTimer *timer;
// Each show and hide moves it on, so a fade a show interrupted orders
// nothing out.
@property (nonatomic) NSUInteger generation;
@end

@implementation QLMOSDController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences {
    self = [super init];
    if (self) {
        _preferences = preferences;
        _rule = [[QLMOSDRule alloc] initWithNow:^NSTimeInterval {
            return NSProcessInfo.processInfo.systemUptime;
        }];
        _window = [[QLMOSDWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered defer:YES];
        _window.title = @"qlm OSD";
        _window.releasedWhenClosed = NO;
        _window.level = NSPopUpMenuWindowLevel;
        _window.ignoresMouseEvents = YES;
        _window.hidesOnDeactivate = NO;
        _window.hasShadow = NO;
        _window.opaque = NO;
        _window.backgroundColor = NSColor.clearColor;
        _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary
                                    | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
        [self reloadPreferences];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(defaultsDidChange:)
                                                   name:NSUserDefaultsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_timer invalidate];
}

- (void)defaultsDidChange:(NSNotification *)notification {
    [self reloadPreferences];
}

// Every save posts the notification, a knob's level kept among them, so
// only a new skin rebuilds the view.
- (void)reloadPreferences {
    self.rule.enabled = self.preferences.showsOSD;
    self.rule.seconds = self.preferences.osdSeconds;
    if (!self.rule.enabled && self.window.visible) {
        [self hide];
    }
    NSString *name = self.preferences.skinName;
    if (self.osdView == nil || ![name isEqualToString:self.skinName]) {
        [self loadSkinNamed:name];
    }
    if (self.window.visible) {
        [self place];
    }
}

// TRAP: dump_screenshot draws a flipped content view upside down, as
// QLMSkinPreview says, so the skin's view fills an unflipped container.
- (void)loadSkinNamed:(NSString *)name {
    QLMSkin *skin = [[QLMSkinLibrary standardLibrary] loadSkinNamed:name refusal:NULL];
    if (skin == nil) {
        return;
    }
    QLMSkinOSDView *view = [[QLMSkinOSDView alloc] initWithSkin:skin];
    QLMSkinOSDView *old = self.osdView;
    view.level = old.level;
    view.unit = old.unit;
    view.title = old.title;
    view.subtitle = old.subtitle;
    view.fraction = old.fraction;
    NSView *container = [[NSView alloc] initWithFrame:view.frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
    self.osdView = view;
    self.skinName = name;
    [self.window setContentSize:view.frame.size];
    self.window.contentView = container;
}

- (void)place {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen == nil) {
        return;
    }
    NSRect frame = QLMOSDFrame(screen.visibleFrame, self.window.frame.size, self.preferences.osdPlacement);
    [self.window setFrame:frame display:NO];
}

- (void)takeSnapshot:(QLMSnapshot *)snapshot {
    if ([self.rule showsSnapshot:snapshot]) {
        [self present:snapshot];
    }
}

- (BOOL)showSnapshot:(QLMSnapshot *)snapshot {
    if (snapshot.volumeDecibels == nil) {
        return NO;
    }
    [self.rule show];
    [self present:snapshot];
    return YES;
}

// No animation in: it is up at full strength at once.
- (void)present:(QLMSnapshot *)snapshot {
    double decibels = snapshot.volumeDecibels.doubleValue;
    QLMSkinOSDView *view = self.osdView;
    view.level = QLMDecibelsNumberText(decibels);
    view.unit = @"dB";
    view.title = QLMOSDTitle(snapshot);
    view.subtitle = QLMOSDSubtitle(snapshot);
    view.fraction = QLMOSDFraction(decibels, self.preferences.lowestDecibels, self.preferences.ceilingDecibels);

    self.generation += 1;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0;
        self.window.animator.alphaValue = 1;
    }];
    [self place];
    [self.window orderFrontRegardless];
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.rule.seconds target:self selector:@selector(timerEnded:)
                                                userInfo:nil repeats:NO];
    self.timer.tolerance = 0.02;
}

- (void)timerEnded:(NSTimer *)timer {
    self.timer = nil;
    [self.rule hide];
    NSUInteger generation = self.generation;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = QLMOSDFadeSeconds;
        self.window.animator.alphaValue = 0;
    }];
    // TRAP: ordered out from the group's completion handler, the window
    // stayed in at alpha 0 in a run with the app inactive. A delay of its
    // own orders it out.
    __weak QLMOSDController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QLMOSDFadeSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        QLMOSDController *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf.generation == generation) {
            [strongSelf hide];
        }
    });
}

- (void)hide {
    self.generation += 1;
    [self.timer invalidate];
    self.timer = nil;
    [self.rule hide];
    [self.window orderOut:nil];
    self.window.alphaValue = 1;
}

- (BOOL)showing {
    return self.window.visible && self.rule.showing;
}

@end
