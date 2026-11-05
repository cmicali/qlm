#import "QLMOSDController.h"

#import "QLMFormat.h"
#import "QLMKnobMath.h"
#import "QLMOSDRule.h"
#import "QLMReadoutThrottle.h"
#import "QLMSkinControls.h"
#import "QLMSkinView.h"

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
// Both made on the first show.
@property (nonatomic, nullable) NSWindow *window;
@property (nonatomic, nullable) QLMSkinOSDView *osdView;
@property (nonatomic, nullable) QLMSnapshot *shown;
// The hold, then the fade.
@property (nonatomic, nullable) NSTimer *timer;
@property (nonatomic) BOOL fading;
// The level changes four times a second at most. The bar follows each step.
@property (nonatomic) QLMReadoutThrottle *levelReadout;
@end

@implementation QLMOSDController

- (instancetype)initWithPreferences:(QLMPreferences *)preferences skin:(QLMSkin *)skin {
    self = [super init];
    if (self) {
        _preferences = preferences;
        _skin = skin;
        _rule = [[QLMOSDRule alloc] init];
        _rule.enabled = preferences.showsOSD;
        __weak QLMOSDController *weakSelf = self;
        _levelReadout = [[QLMReadoutThrottle alloc] initWithShow:^(NSString *text) {
            weakSelf.osdView.level = text;
        }];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)setSkin:(QLMSkin *)skin {
    _skin = skin;
    // The next show draws in it.
    self.osdView = nil;
    QLMSnapshot *shown = self.shown;
    if (self.window.visible && shown != nil) {
        [self hostSkin];
        [self render:shown];
        [self place];
    }
}

- (void)reloadSettings {
    self.rule.enabled = self.preferences.showsOSD;
    if (!self.rule.enabled) {
        [self hide];
    } else if (self.window.visible) {
        [self place];
    }
}

- (void)makeWindow {
    NSWindow *window = [[QLMOSDWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:YES];
    window.title = @"qlm OSD";
    window.releasedWhenClosed = NO;
    window.level = NSPopUpMenuWindowLevel;
    window.ignoresMouseEvents = YES;
    window.hasShadow = NO;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary
                                | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    window.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    self.window = window;
}

- (void)hostSkin {
    QLMSkinOSDView *view = [[QLMSkinOSDView alloc] initWithSkin:self.skin];
    [self.window setContentSize:view.frame.size];
    QLMSkinHost(self.window, view);
    self.osdView = view;
    [self.levelReadout reset];
}

- (void)place {
    NSScreen *screen = NSScreen.mainScreen;
    if (screen == nil) {
        return;
    }
    [self.window setFrame:QLMOSDFrame(screen.visibleFrame, self.window.frame.size, self.preferences.osdPlacement) display:NO];
}

- (void)takeSnapshot:(QLMSnapshot *)snapshot {
    if ([self.rule showsSnapshot:snapshot whileShowing:self.timer != nil]) {
        [self present:snapshot];
    }
}

- (NSString *)showSnapshot:(QLMSnapshot *)snapshot {
    NSString *refusal = [self.rule refusalToShowSnapshot:snapshot];
    if (refusal == nil) {
        [self present:snapshot];
    }
    return refusal;
}

- (void)render:(QLMSnapshot *)snapshot {
    double decibels = snapshot.volumeDecibels.doubleValue;
    QLMSkinOSDView *view = self.osdView;
    [self.levelReadout showText:QLMDecibelsNumberText(decibels, 1) kind:@"level"];
    view.title = QLMGroupNameText(snapshot);
    view.subtitle = QLMOutputStateText(snapshot);
    view.fraction = QLMKnobFraction(decibels, self.preferences.lowestDecibels, QLMShownCeiling(snapshot, self.preferences.ceilingDecibels));
}

// No animation in.
- (void)present:(QLMSnapshot *)snapshot {
    if (self.window == nil) {
        [self makeWindow];
    }
    if (self.osdView == nil) {
        [self hostSkin];
    }
    self.shown = snapshot;
    // TRAP: taken before the fade is undone below. A fade's timer is its
    // hide's, which a step must replace, not move.
    BOOL holding = self.timer != nil && !self.fading;
    // A show from hidden shows its level at once.
    if (!self.window.visible || self.fading) {
        [self.levelReadout reset];
    }
    [self render:snapshot];
    // Only when it's hidden or fading: on each step of a turn, the order
    // front would wait on the window server for the last frame.
    if (!self.window.visible || self.fading) {
        self.fading = NO;
        self.window.alphaValue = 1;
        if (!self.window.visible) {
            [self place];
        }
        [self.window orderFrontRegardless];
    }
    // A turn that goes on moves the hold's end, rather than make a timer
    // a step.
    if (holding) {
        self.timer.fireDate = [NSDate dateWithTimeIntervalSinceNow:self.preferences.osdSeconds];
        return;
    }
    [self holdFor:self.preferences.osdSeconds then:^(QLMOSDController *controller) {
        [controller fade];
    }];
}

- (void)flushReadout {
    [self.levelReadout flush];
}

// In the common modes, so it ends during a slider drag or a menu held open.
- (void)holdFor:(NSTimeInterval)seconds then:(void (^)(QLMOSDController *controller))then {
    [self.timer invalidate];
    __weak QLMOSDController *weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:seconds repeats:NO block:^(NSTimer *timer) {
        QLMOSDController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            then(strongSelf);
        }
    }];
    self.timer.tolerance = 0.02;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

// TRAP: ordered out from the animation group's completion handler, the
// window stayed in at alpha 0 in a run with the app inactive. A timer of
// its own orders it out.
- (void)fade {
    self.fading = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = QLMOSDFadeSeconds;
        self.window.animator.alphaValue = 0;
    }];
    [self holdFor:QLMOSDFadeSeconds then:^(QLMOSDController *controller) {
        [controller hide];
    }];
}

- (void)hide {
    [self.timer invalidate];
    self.timer = nil;
    self.fading = NO;
    [self.window orderOut:nil];
    self.window.alphaValue = 1;
}

- (BOOL)showing {
    return self.timer != nil && !self.fading;
}

@end

#if DEBUG
@implementation QLMOSDController (Debug)
@end
#endif
