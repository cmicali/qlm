#import "QLMOSDRule.h"

#include <math.h>

static const CGFloat QLMOSDMargin = 24;

@implementation QLMOSDRule {
    BOOL _seen;
    NSNumber *_volume;
    BOOL _muted;
    BOOL _dimmed;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
    }
    return self;
}

- (BOOL)showsSnapshot:(QLMSnapshot *)snapshot whileShowing:(BOOL)showing {
    BOOL seen = _seen;
    BOOL turned = snapshot.volumeFromKnob && snapshot.volumeDecibels != nil && ![snapshot.volumeDecibels isEqual:_volume];
    BOOL stateChanged = snapshot.allMuted != _muted || snapshot.dimmed != _dimmed;
    _seen = YES;
    _volume = snapshot.volumeDecibels;
    _muted = snapshot.allMuted;
    _dimmed = snapshot.dimmed;
    return seen && self.enabled && (turned || (stateChanged && showing));
}

- (NSString *)refusalToShowSnapshot:(QLMSnapshot *)snapshot {
    if (!self.enabled) {
        return @"the OSD is off in Settings";
    }
    return snapshot.volumeDecibels == nil ? @"no level yet" : nil;
}

@end

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
