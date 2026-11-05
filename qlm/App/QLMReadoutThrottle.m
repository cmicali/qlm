#import "QLMReadoutThrottle.h"

const NSTimeInterval QLMReadoutInterval = 0.25;

@implementation QLMReadoutThrottle {
    void (^_show)(NSString *text);
    NSString *_shownKind;
    NSTimeInterval _shownAt;
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
        _schedule = ^(NSTimeInterval delay, dispatch_block_t block) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
        };
        [self reset];
    }
    return self;
}

- (void)reset {
    _shownText = nil;
    _shownKind = nil;
    _shownAt = -INFINITY;
    _waiting = nil;
}

- (void)showNow:(NSString *)text kind:(NSString *)kind {
    _waiting = nil;
    _shownKind = [kind copy];
    _shownAt = self.now();
    if (![text isEqualToString:_shownText]) {
        _shownText = [text copy];
        _show(text);
    }
}

- (void)showText:(NSString *)text kind:(NSString *)kind {
    if (![kind isEqualToString:_shownKind] || _shownText == nil) {
        [self showNow:text kind:kind];
        return;
    }
    if ([text isEqualToString:_shownText]) {
        _waiting = nil;
        return;
    }
    NSTimeInterval since = self.now() - _shownAt;
    if (since >= QLMReadoutInterval && !_scheduled) {
        [self showNow:text kind:kind];
        return;
    }
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
    if (_waiting != nil) {
        [self showNow:_waiting kind:_shownKind];
    }
}

@end
