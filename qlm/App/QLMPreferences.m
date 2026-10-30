#import "QLMPreferences.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMSystem.h"

const double QLMVolumeRangeMinimumSpan = 10;

static NSString *const QLMCeilingKey = @"QLMCeilingDecibels";
static NSString *const QLMLowestKey = @"QLMLowestDecibels";
static NSString *const QLMVolumeKey = @"QLMVolumeDecibels";
static NSString *const QLMWakesAtLaunchKey = @"QLMWakesAtLaunch";
static NSString *const QLMUsesAdapterKey = @"QLMUsesAdapter";
static NSString *const QLMSetupFileNameKey = @"QLMSetupFileName";

static double QLMStepBelow(double decibels) {
    return floor(decibels / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
}

double QLMNearestStepDecibels(double decibels) {
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
            QLMCeilingKey: @([[QLMSystemSettings alloc] init].ceilingDecibels),
            QLMLowestKey: @(-60),
            QLMVolumeKey: @(-40),
            QLMWakesAtLaunchKey: @NO,
            QLMUsesAdapterKey: @NO,
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

- (double)boundedLowest:(double)decibels {
    return fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels - QLMVolumeRangeMinimumSpan, QLMNearestStepDecibels(decibels)));
}

- (double)lowestDecibels {
    return [self boundedLowest:[_defaults doubleForKey:QLMLowestKey]];
}

- (void)setLowestDecibels:(double)lowestDecibels {
    [_defaults setDouble:[self boundedLowest:lowestDecibels] forKey:QLMLowestKey];
}

- (double)boundedVolume:(double)decibels {
    return fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels, QLMNearestStepDecibels(decibels)));
}

- (double)volumeDecibels {
    return [self boundedVolume:[_defaults doubleForKey:QLMVolumeKey]];
}

- (void)setVolumeDecibels:(double)volumeDecibels {
    [_defaults setDouble:[self boundedVolume:volumeDecibels] forKey:QLMVolumeKey];
}

- (double)cappedDecibels:(double)decibels {
    return fmin(decibels, self.ceilingDecibels);
}

- (double)sentDecibels:(double)decibels dimmed:(BOOL)dimmed {
    double capped = [self cappedDecibels:decibels];
    return dimmed ? fmax(QLMVolumeDecibelsMin, capped - QLMDimDecibels) : capped;
}

- (BOOL)wakesAtLaunch {
    return [_defaults boolForKey:QLMWakesAtLaunchKey];
}

- (void)setWakesAtLaunch:(BOOL)wakesAtLaunch {
    [_defaults setBool:wakesAtLaunch forKey:QLMWakesAtLaunchKey];
}

- (BOOL)usesAdapter {
    return [_defaults boolForKey:QLMUsesAdapterKey];
}

- (void)setUsesAdapter:(BOOL)usesAdapter {
    [_defaults setBool:usesAdapter forKey:QLMUsesAdapterKey];
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
