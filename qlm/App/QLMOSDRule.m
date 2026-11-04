#import "QLMOSDRule.h"

#include <math.h>

static const CGFloat QLMOSDMargin = 24;

@implementation QLMOSDRule {
    NSTimeInterval (^_now)(void);
    BOOL _seen;
    NSNumber *_volume;
    BOOL _muted;
    BOOL _dimmed;
}

- (instancetype)initWithNow:(NSTimeInterval (^)(void))now {
    self = [super init];
    if (self) {
        _now = [now copy];
        _enabled = YES;
        _seconds = 2;
        _hidesAt = -INFINITY;
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    if (!enabled) {
        [self hide];
    }
}

- (BOOL)showsSnapshot:(QLMSnapshot *)snapshot {
    BOOL seen = _seen;
    BOOL turned = snapshot.volumeFromKnob && snapshot.volumeDecibels != nil && ![snapshot.volumeDecibels isEqual:_volume];
    BOOL stateChanged = snapshot.allMuted != _muted || snapshot.dimmed != _dimmed;
    _seen = YES;
    _volume = snapshot.volumeDecibels;
    _muted = snapshot.allMuted;
    _dimmed = snapshot.dimmed;
    if (!seen || !self.enabled || !(turned || (stateChanged && self.showing))) {
        return NO;
    }
    [self show];
    return YES;
}

- (void)show {
    _hidesAt = _now() + self.seconds;
}

- (void)hide {
    _hidesAt = -INFINITY;
}

- (BOOL)showing {
    return _now() < _hidesAt;
}

@end

NSString *QLMOSDTitle(QLMSnapshot *snapshot) {
    return snapshot.activeGroupName.length > 0 ? snapshot.activeGroupName : @"Monitors";
}

NSString *QLMOSDSubtitle(QLMSnapshot *snapshot) {
    if (snapshot.allMuted) {
        return @"MUTED";
    }
    return snapshot.dimmed ? @"DIM" : @"qlm · Output level";
}

double QLMOSDFraction(double decibels, double lowestDecibels, double ceilingDecibels) {
    double span = ceilingDecibels - lowestDecibels;
    double fraction = span > 0 ? (decibels - lowestDecibels) / span : 1;
    return isfinite(fraction) ? fmax(0, fmin(1, fraction)) : 0;
}

CGRect QLMOSDFrame(CGRect visible, CGSize size, QLMOSDPlacement placement) {
    CGFloat x = 0;
    switch (placement) {
        case QLMOSDPlacementTopLeft:
        case QLMOSDPlacementBottomLeft:
            x = CGRectGetMinX(visible) + QLMOSDMargin;
            break;
        case QLMOSDPlacementTopCenter:
        case QLMOSDPlacementBottomCenter:
            x = CGRectGetMidX(visible) - size.width / 2;
            break;
        case QLMOSDPlacementTopRight:
        case QLMOSDPlacementBottomRight:
            x = CGRectGetMaxX(visible) - QLMOSDMargin - size.width;
            break;
    }
    BOOL top = placement == QLMOSDPlacementTopLeft || placement == QLMOSDPlacementTopCenter || placement == QLMOSDPlacementTopRight;
    CGFloat y = top ? CGRectGetMaxY(visible) - QLMOSDMargin - size.height : CGRectGetMinY(visible) + QLMOSDMargin;
    return CGRectMake(round(x), round(y), size.width, size.height);
}
