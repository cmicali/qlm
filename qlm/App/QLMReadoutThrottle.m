#import "QLMReadoutThrottle.h"

const NSTimeInterval QLMReadoutInterval = 0.25;

static BOOL QLMReadoutSame(NSString *a, NSString *b) {
    return a == b || [a isEqualToString:b];
}

@implementation QLMReadoutThrottle {
    void (^_show)(NSString *text);
    BOOL _shownAny;
    NSString *_shown;
    NSTimeInterval _shownAt;
    BOOL _waits;
    NSString *_waiting;
    BOOL _scheduled;
}

- (instancetype)initWithShow:(void (^)(NSString *text))show {
    self = [super init];
    if (self) {
        _show = [show copy];
        _now = ^NSTimeInterval {
            return NSProcessInfo.processInfo.systemUptime;
        };
        _schedule = QLMMainQueueScheduler();
    }
    return self;
}

- (void)showNow:(NSString *)text {
    _waits = NO;
    _waiting = nil;
    _shownAt = self.now();
    if (!_shownAny || !QLMReadoutSame(text, _shown)) {
        _shownAny = YES;
        _shown = [text copy];
        _show(text);
    }
}

- (void)showText:(NSString *)text atOnce:(BOOL)atOnce {
    if (atOnce || !_shownAny) {
        [self showNow:text];
        return;
    }
    if (QLMReadoutSame(text, _shown)) {
        _waits = NO;
        _waiting = nil;
        return;
    }
    NSTimeInterval since = self.now() - _shownAt;
    if (since >= QLMReadoutInterval && !_scheduled) {
        [self showNow:text];
        return;
    }
    _waits = YES;
    _waiting = [text copy];
    if (_scheduled) {
        return;
    }
    _scheduled = YES;
    __weak QLMReadoutThrottle *weakSelf = self;
    self.schedule(QLMReadoutInterval - since, ^{
        QLMReadoutThrottle *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_scheduled = NO;
            [strongSelf flush];
        }
    });
}

- (void)flush {
    if (_waits) {
        [self showNow:_waiting];
    }
}

@end
