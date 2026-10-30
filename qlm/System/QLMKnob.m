#import "QLMKnob.h"

#include <math.h>

#include "QLMCommands.h"

static const NSInteger QLMKnobTurnTenths = 10;          // a turn, and a wander
static const NSTimeInterval QLMKnobRestInterval = 0.5;  // the rest point's age, at most
static const NSTimeInterval QLMKnobFollowInterval = 2;  // following, after a turn
// Past a step's edge by more than a tenth, so jitter at the edge does not
// flip the volume.
static const double QLMKnobFollowTenths = 4;

// The nearest step, from QLMVolumeDecibelsMin to 0 dB. No tenth falls
// halfway between two steps.
static double QLMKnobStep(NSInteger tenths) {
    double decibels = round((double)tenths / (10 * QLMVolumeDecibelsStep)) * QLMVolumeDecibelsStep;
    return fmin(0, fmax(QLMVolumeDecibelsMin, decibels));
}

@implementation QLMKnob {
    BOOL _resting;
    NSInteger _rest;
    NSTimeInterval _restTime;
    NSTimeInterval _followUntil;
    NSNumber *_lastVolume;  // the last volume this set
}

- (void)reset {
    _resting = NO;
    _followUntil = 0;
    _lastVolume = nil;
}

- (NSNumber *)volumeForReading:(NSInteger)tenths atTime:(NSTimeInterval)time volume:(NSNumber *)volume {
    if (!_resting) {
        _resting = YES;
        _rest = tenths;
        _restTime = time;
        return nil;
    }
    BOOL turned = labs(tenths - _rest) >= QLMKnobTurnTenths;
    if (turned || time - _restTime >= QLMKnobRestInterval) {
        _rest = tenths;
        _restTime = time;
    }
    if (turned) {
        _followUntil = time + QLMKnobFollowInterval;
    }

    double step = QLMKnobStep(tenths);
    if (volume == nil || step == volume.doubleValue) {
        return nil;
    }
    double distance = fabs((double)tenths - volume.doubleValue * 10);
    BOOL following = time < _followUntil && distance >= QLMKnobFollowTenths;
    BOOL wandered = [volume isEqual:_lastVolume] && distance >= QLMKnobTurnTenths;
    if (!turned && !following && !wandered) {
        return nil;
    }
    _lastVolume = @(step);
    return _lastVolume;
}

@end
