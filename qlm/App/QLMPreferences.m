#import "QLMPreferences.h"

#include <math.h>

#include "QLMCommands.h"

const double QLMVolumeRangeMinimumSpan = 10;

static NSString *const QLMCeilingKey = @"QLMCeilingDecibels";
static NSString *const QLMLowestKey = @"QLMLowestDecibels";
static NSString *const QLMVolumeKey = @"QLMVolumeDecibels";
static NSString *const QLMWakesAtLaunchKey = @"QLMWakesAtLaunch";
static NSString *const QLMSetupFileNameKey = @"QLMSetupFileName";

static double QLMStepBelow(double decibels) {
    return floor(decibels / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
}

static double QLMNearestStep(double decibels) {
    return round(decibels / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
}

@implementation QLMPreferences {
    NSUserDefaults *_defaults;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        [defaults registerDefaults:@{
            QLMCeilingKey: @(-20),
            QLMLowestKey: @(-60),
            QLMVolumeKey: @(-40),
            QLMWakesAtLaunchKey: @NO,
        }];
    }
    return self;
}

// Read through the setters' bounds too, so a hand-edited default cannot pass
// the ceiling.
- (double)ceilingDecibels {
    double stored = [_defaults doubleForKey:QLMCeilingKey];
    return fmin(0, fmax(QLMVolumeDecibelsMin + QLMVolumeRangeMinimumSpan, QLMStepBelow(stored)));
}

- (void)setCeilingDecibels:(double)ceilingDecibels {
    double ceiling = fmin(0, fmax(self.lowestDecibels + QLMVolumeRangeMinimumSpan, QLMStepBelow(ceilingDecibels)));
    [_defaults setDouble:ceiling forKey:QLMCeilingKey];
}

- (double)lowestDecibels {
    double stored = [_defaults doubleForKey:QLMLowestKey];
    return fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels - QLMVolumeRangeMinimumSpan, QLMNearestStep(stored)));
}

- (void)setLowestDecibels:(double)lowestDecibels {
    double lowest = fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels - QLMVolumeRangeMinimumSpan, QLMNearestStep(lowestDecibels)));
    [_defaults setDouble:lowest forKey:QLMLowestKey];
}

- (double)volumeDecibels {
    double stored = [_defaults doubleForKey:QLMVolumeKey];
    return fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels, QLMNearestStep(stored)));
}

- (void)setVolumeDecibels:(double)volumeDecibels {
    double volume = fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels, QLMNearestStep(volumeDecibels)));
    [_defaults setDouble:volume forKey:QLMVolumeKey];
}

- (BOOL)wakesAtLaunch {
    return [_defaults boolForKey:QLMWakesAtLaunchKey];
}

- (void)setWakesAtLaunch:(BOOL)wakesAtLaunch {
    [_defaults setBool:wakesAtLaunch forKey:QLMWakesAtLaunchKey];
}

- (NSString *)setupFileName {
    return [_defaults stringForKey:QLMSetupFileNameKey];
}

- (void)setSetupFileName:(NSString *)setupFileName {
    [_defaults setObject:setupFileName forKey:QLMSetupFileNameKey];
}

@end

NSString *QLMSetupDirectory(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Genelec/GLM5/Setup Files"];
}

NSArray<NSString *> *QLMSetupFileNames(void) {
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:QLMSetupDirectory() error:NULL];
    NSMutableArray<NSString *> *setups = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name.pathExtension caseInsensitiveCompare:@"sam"] == NSOrderedSame) {
            [setups addObject:name];
        }
    }
    return [setups sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
