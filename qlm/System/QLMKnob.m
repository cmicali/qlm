#import "QLMKnob.h"

#include <math.h>

#include "QLMCommands.h"

// More than a whole dB. A 10-tenth wander never moved GLM, and 11 did.
static const NSInteger QLMKnobMoveTenths = 11;
// GLM followed a change 2.53 s after the one that moved it, and none from
// 2.55 s.
static const NSTimeInterval QLMKnobFollowInterval = 2.54;

// The nearest step, from QLMVolumeDecibelsMin to 0 dB. No tenth falls
// halfway between two steps.
static double QLMKnobStep(NSInteger tenths) {
    double decibels = round((double)tenths / (10 * QLMVolumeDecibelsStep)) * QLMVolumeDecibelsStep;
    return fmin(0, fmax(QLMVolumeDecibelsMin, decibels));
}

@implementation QLMKnob {
    BOOL _resting;
    NSInteger _followed;  // the last reading the volume followed, or the rest point
    NSInteger _last;
    NSTimeInterval _followUntil;
}

- (void)reset {
    _resting = NO;
}

- (NSNumber *)volumeForReading:(NSInteger)tenths atTime:(NSTimeInterval)time volume:(NSNumber *)volume {
    if (!_resting) {
        _resting = YES;
        _followed = tenths;
        _last = tenths;
        _followUntil = 0;
        return nil;
    }
    if (tenths == _last) {
        return nil;
    }
    _last = tenths;
    if (labs(tenths - _followed) >= QLMKnobMoveTenths) {
        _followUntil = time + QLMKnobFollowInterval;
    }
    if (time >= _followUntil || volume == nil) {
        return nil;
    }
    _followed = tenths;
    double step = QLMKnobStep(tenths);
    return step == volume.doubleValue ? nil : @(step);
}

@end
