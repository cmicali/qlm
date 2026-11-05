#import "QLMFrameCoalescer.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// How long a request waits for a frame that doesn't come.
static const int64_t QLMFrameFallbackNanoseconds = 100 * NSEC_PER_MSEC;

@implementation QLMFrameCoalescer {
    void (^_apply)(id value);
    id _waiting;
    BOOL _requested;
}

- (instancetype)initWithApply:(void (^)(id value))apply {
    self = [super init];
    if (self) {
        _apply = [apply copy];
        _requestFrame = ^(dispatch_block_t fire) {
            dispatch_async(dispatch_get_main_queue(), fire);
        };
    }
    return self;
}

- (BOOL)pending {
    return _waiting != nil;
}

- (void)submit:(id)value {
    _waiting = value;
    if (_requested) {
        return;
    }
    _requested = YES;
    __weak QLMFrameCoalescer *weakSelf = self;
    self.requestFrame(^{
        QLMFrameCoalescer *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_requested = NO;
            [strongSelf flush];
        }
    });
}

- (void)flush {
    id value = _waiting;
    if (value == nil) {
        return;
    }
    _waiting = nil;
    _apply(value);
}

@end

// One display link, paused while no request waits.
@interface QLMDisplayFrames : NSObject
@end

@implementation QLMDisplayFrames {
    id _link;  // a CADisplayLink, on macOS 14 and later
    __weak NSScreen *_linkScreen;
    NSMutableArray<dispatch_block_t> *_waiting;
    NSUInteger _generation;
}

+ (instancetype)shared {
    static QLMDisplayFrames *frames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        frames = [[QLMDisplayFrames alloc] init];
    });
    return frames;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _waiting = [NSMutableArray array];
        // A window moved to another display, or a display changed, takes a
        // new link.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screensDidChange:)
                                                   name:NSApplicationDidChangeScreenParametersNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screensDidChange:)
                                                   name:NSWindowDidChangeScreenNotification object:nil];
    }
    return self;
}

- (void)screensDidChange:(NSNotification *)notification {
    if (@available(macOS 14.0, *)) {
        [(CADisplayLink *)_link invalidate];
    }
    _link = nil;
}

- (void)request:(dispatch_block_t)fire onScreen:(nullable NSScreen *)screen {
    [_waiting addObject:fire];
    if (_waiting.count > 1) {
        return;
    }
    NSUInteger generation = ++_generation;
    dispatch_block_t tick = ^{
        if (generation == self->_generation) {
            [self tick:nil];
        }
    };
    // TRAP: with no window on screen, as on a locked screen, each frame of
    // the link asks the window server for the display's power state, which
    // costs more than the draw it would time.
    BOOL seen = (NSApp.occlusionState & NSApplicationOcclusionStateVisible) != 0;
    if (@available(macOS 14.0, *)) {
        if (_link != nil && screen != _linkScreen) {
            [(CADisplayLink *)_link invalidate];
            _link = nil;
        }
        if (seen && _link == nil && screen != nil) {
            CADisplayLink *link = [screen displayLinkWithTarget:self selector:@selector(tick:)];
            [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            _link = link;
            _linkScreen = screen;
        }
        if (seen && _link != nil) {
            ((CADisplayLink *)_link).paused = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, QLMFrameFallbackNanoseconds), dispatch_get_main_queue(), tick);
            return;
        }
    }
    dispatch_async(dispatch_get_main_queue(), tick);
}

- (void)tick:(id)sender {
    if (@available(macOS 14.0, *)) {
        ((CADisplayLink *)_link).paused = YES;
    }
    _generation++;
    NSArray<dispatch_block_t> *fires = _waiting;
    _waiting = [NSMutableArray array];
    for (dispatch_block_t fire in fires) {
        fire();
    }
}

@end

QLMFrameRequest QLMDisplayFrameRequest(NSScreen *_Nullable (^screen)(void)) {
    return ^(dispatch_block_t fire) {
        [[QLMDisplayFrames shared] request:fire onScreen:screen() ?: NSScreen.mainScreen];
    };
}
