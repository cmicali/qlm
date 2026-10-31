#import "QLMKnob.h"

#include <math.h>

#include "QLMCommands.h"

// More than a whole dB. A 10-tenth wander never moved GLM, and 11 did.
static const NSInteger QLMKnobMoveTenths = 11;
// GLM followed a change 2.53 s after the one that moved it, and none from
// 2.55 s.
static const NSTimeInterval QLMKnobFollowInterval = 2.54;
// As the plug came out, the reading moved from 25.11 s and read absent at
// 25.45 s, 0.33 s on (captures/volume-sweep). Half a second holds that, and
// a poll more.
static const NSTimeInterval QLMKnobUnplugWindow = 0.5;

// The nearest step, from QLMVolumeDecibelsMin to 0 dB. No tenth falls
// halfway between two steps.
static double QLMKnobStep(NSInteger tenths) {
    double decibels = round((double)tenths / (10 * QLMVolumeDecibelsStep)) * QLMVolumeDecibelsStep;
    return fmin(QLMVolumeDecibelsMax, fmax(QLMVolumeDecibelsMin, decibels));
}

// A move of the volume the knob made.
@interface QLMKnobFollow : NSObject
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) NSNumber *volumeBefore;
@end

@implementation QLMKnobFollow
@end

@implementation QLMKnob {
    BOOL _resting;
    NSInteger _followed;  // the last reading the volume followed, or the rest point
    NSInteger _last;
    NSTimeInterval _followUntil;
    NSMutableArray<QLMKnobFollow *> *_follows;  // those of the last QLMKnobUnplugWindow, oldest first
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _follows = [NSMutableArray array];
    }
    return self;
}

- (void)reset {
    _resting = NO;
    [_follows removeAllObjects];
}

- (void)forgetFollowsBefore:(NSTimeInterval)time {
    while (_follows.count > 0 && _follows.firstObject.time < time - QLMKnobUnplugWindow) {
        [_follows removeObjectAtIndex:0];
    }
}

- (NSNumber *)volumeAtUnplugAtTime:(NSTimeInterval)time volume:(NSNumber *)volume {
    [self forgetFollowsBefore:time];
    NSNumber *before = _follows.firstObject.volumeBefore;
    [self reset];
    return before != nil && volume != nil && before.doubleValue < volume.doubleValue ? before : nil;
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
    if (step == volume.doubleValue) {
        return nil;
    }
    [self forgetFollowsBefore:time];
    QLMKnobFollow *follow = [[QLMKnobFollow alloc] init];
    follow.time = time;
    follow.volumeBefore = volume;
    [_follows addObject:follow];
    return @(step);
}

@end
