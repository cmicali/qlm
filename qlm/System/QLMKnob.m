#import "QLMKnob.h"

#include <math.h>

#include "QLMCommands.h"

// A turn moves the reading a whole dB from where the knob rested. The rest
// point gives way to the reading every half second, so a slower move is no
// turn. For 2 s after a turn the volume follows a reading 4 tenths from it,
// past its step's edge by more than a tenth, so jitter at the edge does not
// flip it. Later, a volume that is the knob's follows a reading a whole dB
// from it.
static const NSInteger QLMKnobTurnTenths = 10;
static const NSTimeInterval QLMKnobRestInterval = 0.5;
static const NSTimeInterval QLMKnobFollowInterval = 2;
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
    if (!turned) {
        double distance = fabs((double)tenths - volume.doubleValue * 10);
        BOOL following = time < _followUntil && distance >= QLMKnobFollowTenths;
        BOOL wandered = _lastVolume != nil && [volume isEqualToNumber:_lastVolume] && distance >= QLMKnobTurnTenths;
        if (!following && !wandered) {
            return nil;
        }
    }
    _lastVolume = @(step);
    return _lastVolume;
}

@end
