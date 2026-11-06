#import "QLMFrameCoalescer.h"

@implementation QLMFrameCoalescer {
    void (^_apply)(id value);
    id _waiting;
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

// A value already waiting has its turn asked for.
- (void)submit:(id)value {
    BOOL asked = _waiting != nil;
    _waiting = value;
    if (asked) {
        return;
    }
    __weak QLMFrameCoalescer *weakSelf = self;
    self.requestFrame(^{
        [weakSelf flush];
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
