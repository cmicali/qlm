#import "QLMPreferences.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMSystem.h"

const double QLMVolumeRangeMinimumSpan = 10;

static NSString *const QLMCeilingKey = @"QLMCeilingDecibels";
static NSString *const QLMLowestKey = @"QLMLowestDecibels";
static NSString *const QLMWakesAtLaunchKey = @"QLMWakesAtLaunch";
static NSString *const QLMUsesAdapterKey = @"QLMUsesAdapter";
static NSString *const QLMSetupFileNameKey = @"QLMSetupFileName";
// Each bus's keys are its prefix and a name. The real monitors' came first,
// with no word between.
static NSString *const QLMAdapterBusPrefix = @"QLM";
static NSString *const QLMFakeBusPrefix = @"QLMFake";
static NSString *const QLMVolumeName = @"VolumeDecibels";
static NSString *const QLMMutedName = @"MutedHardwareIDs";
static NSString *const QLMMutingAllName = @"MutingAll";
static NSString *const QLMLiftedName = @"LiftedHardwareIDs";
static NSString *const QLMLeasesName = @"KnownLeases";
static NSString *const QLMLeaseHardwareIDKey = @"hardwareID";
static NSString *const QLMLeaseSerialKey = @"serialNumber";
static NSString *const QLMLeaseSessionKey = @"session";

static double QLMStepBelow(double decibels) {
    return floor(decibels / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
}

double QLMNearestStepDecibels(double decibels) {
    return round(decibels / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
}

BOOL QLMIsSavableLevel(double decibels) {
    return decibels <= QLMVolumeDecibelsMax;
}

// TRAP: doubleForKey: reads a string that is no number as 0 dB. So only a
// number at or under 0 dB is read, and anything else is the default.
static double QLMKeptLevel(NSUserDefaults *defaults, NSString *key) {
    id kept = [defaults objectForKey:key];
    double decibels = [kept isKindOfClass:[NSNumber class]] ? [kept doubleValue] : NAN;
    if (QLMIsSavableLevel(decibels)) {
        return decibels;
    }
    return [[defaults volatileDomainForName:NSRegistrationDomain][key] doubleValue];
}

// Kept as a property list.
static NSArray<NSDictionary *> *QLMLeasesPlist(NSArray<QLMKnownLease *> *leases) {
    NSMutableArray<NSDictionary *> *plist = [NSMutableArray arrayWithCapacity:leases.count];
    for (QLMKnownLease *lease in leases) {
        [plist addObject:@{
            QLMLeaseHardwareIDKey: lease.hardwareID,
            QLMLeaseSerialKey: lease.serialNumber,
            QLMLeaseSessionKey: @(lease.session),
        }];
    }
    return plist;
}

@interface QLMPreferences ()
- (double)boundedVolume:(double)decibels;
@end

@interface QLMBusPreferences ()
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults prefix:(NSString *)prefix preferences:(QLMPreferences *)preferences;
@end

@implementation QLMBusPreferences {
    NSUserDefaults *_defaults;
    NSString *_prefix;
    __weak QLMPreferences *_preferences;  // for the ceiling
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults prefix:(NSString *)prefix preferences:(QLMPreferences *)preferences {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _prefix = [prefix copy];
        _preferences = preferences;
        [defaults registerDefaults:@{[self key:QLMVolumeName]: @(-40)}];
    }
    return self;
}

- (NSString *)key:(NSString *)name {
    return [_prefix stringByAppendingString:name];
}

- (double)volumeDecibels {
    return [_preferences boundedVolume:QLMKeptLevel(_defaults, [self key:QLMVolumeName])];
}

- (BOOL)saveVolumeDecibels:(double)volumeDecibels {
    if (!QLMIsSavableLevel(volumeDecibels)) {
        return NO;
    }
    [_defaults setDouble:[_preferences boundedVolume:volumeDecibels] forKey:[self key:QLMVolumeName]];
    return YES;
}

// Kept as a list of data, which a property list can hold.
- (NSSet<NSData *> *)hardwareIDsNamed:(NSString *)name {
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    for (id item in [_defaults arrayForKey:[self key:name]]) {
        if ([item isKindOfClass:[NSData class]]) {
            [hardwareIDs addObject:item];
        }
    }
    return hardwareIDs;
}

- (NSSet<NSData *> *)mutedHardwareIDs {
    return [self hardwareIDsNamed:QLMMutedName];
}

- (void)setMutedHardwareIDs:(NSSet<NSData *> *)mutedHardwareIDs {
    [_defaults setObject:mutedHardwareIDs.allObjects forKey:[self key:QLMMutedName]];
}

- (BOOL)mutingAll {
    return [_defaults boolForKey:[self key:QLMMutingAllName]];
}

- (void)setMutingAll:(BOOL)mutingAll {
    [_defaults setBool:mutingAll forKey:[self key:QLMMutingAllName]];
}

- (NSSet<NSData *> *)liftedHardwareIDs {
    return [self hardwareIDsNamed:QLMLiftedName];
}

- (void)setLiftedHardwareIDs:(NSSet<NSData *> *)liftedHardwareIDs {
    [_defaults setObject:liftedHardwareIDs.allObjects forKey:[self key:QLMLiftedName]];
}

// System checks each lease again before it takes one.
- (NSArray<QLMKnownLease *> *)knownLeases {
    NSMutableArray<QLMKnownLease *> *leases = [NSMutableArray array];
    for (id item in [_defaults arrayForKey:[self key:QLMLeasesName]]) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id hardwareID = item[QLMLeaseHardwareIDKey];
        id serial = item[QLMLeaseSerialKey];
        id session = item[QLMLeaseSessionKey];
        if ([hardwareID isKindOfClass:[NSData class]] && [serial isKindOfClass:[NSString class]] &&
            [session isKindOfClass:[NSNumber class]] && [session unsignedIntegerValue] <= UINT8_MAX) {
            [leases addObject:[[QLMKnownLease alloc] initWithHardwareID:hardwareID serialNumber:serial
                                                                session:(uint8_t)[session unsignedIntegerValue]]];
        }
    }
    return leases;
}

- (void)setKnownLeases:(NSArray<QLMKnownLease *> *)knownLeases {
    [_defaults setObject:QLMLeasesPlist(knownLeases) forKey:[self key:QLMLeasesName]];
}

// TRAP: a snapshot from before System starts carries an empty record, not
// the one System starts from. Each is compared with the one kept, so an
// unchanged one writes nothing.
- (void)keepFromSnapshot:(QLMSnapshot *)snapshot {
    // The knob moves the volume too. Keep whichever set it last.
    NSNumber *volume = snapshot.volumeDecibels;
    if (volume != nil && [_preferences boundedVolume:volume.doubleValue] != self.volumeDecibels) {
        (void)[self saveVolumeDecibels:volume.doubleValue];  // System never reports one above 0 dB
    }
    if (!snapshot.running) {
        return;
    }
    if (![snapshot.mutedHardwareIDs isEqualToSet:self.mutedHardwareIDs]) {
        self.mutedHardwareIDs = snapshot.mutedHardwareIDs;
    }
    if (snapshot.mutingAll != self.mutingAll) {
        self.mutingAll = snapshot.mutingAll;
    }
    if (![snapshot.liftedHardwareIDs isEqualToSet:self.liftedHardwareIDs]) {
        self.liftedHardwareIDs = snapshot.liftedHardwareIDs;
    }
    if (![QLMLeasesPlist(snapshot.knownLeases) isEqualToArray:[_defaults arrayForKey:[self key:QLMLeasesName]] ?: @[]]) {
        self.knownLeases = snapshot.knownLeases;
    }
}

- (void)fillSettings:(QLMSystemSettings *)settings {
    settings.mutedHardwareIDs = self.mutedHardwareIDs;
    settings.mutingAll = self.mutingAll;
    settings.liftedHardwareIDs = self.liftedHardwareIDs;
    settings.knownLeases = self.knownLeases;
}

@end

@implementation QLMPreferences {
    NSUserDefaults *_defaults;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _adapterBus = [[QLMBusPreferences alloc] initWithDefaults:defaults prefix:QLMAdapterBusPrefix preferences:self];
        _fakeBus = [[QLMBusPreferences alloc] initWithDefaults:defaults prefix:QLMFakeBusPrefix preferences:self];
        [defaults registerDefaults:@{
            QLMCeilingKey: @([[QLMSystemSettings alloc] init].ceilingDecibels),
            QLMLowestKey: @(-60),
            QLMWakesAtLaunchKey: @NO,
            QLMUsesAdapterKey: @NO,
        }];
    }
    return self;
}

// Read through the save's bounds too, so a hand-edited default stays on a
// step and above the range's bottom.
- (double)ceilingDecibels {
    return fmax(QLMVolumeDecibelsMin + QLMVolumeRangeMinimumSpan, QLMStepBelow(QLMKeptLevel(_defaults, QLMCeilingKey)));
}

- (BOOL)saveCeilingDecibels:(double)ceilingDecibels {
    if (!QLMIsSavableLevel(ceilingDecibels)) {
        return NO;
    }
    double ceiling = fmax(self.lowestDecibels + QLMVolumeRangeMinimumSpan, QLMStepBelow(ceilingDecibels));
    [_defaults setDouble:ceiling forKey:QLMCeilingKey];
    return YES;
}

- (double)boundedLowest:(double)decibels {
    return fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels - QLMVolumeRangeMinimumSpan, QLMNearestStepDecibels(decibels)));
}

- (double)lowestDecibels {
    return [self boundedLowest:QLMKeptLevel(_defaults, QLMLowestKey)];
}

- (BOOL)saveLowestDecibels:(double)lowestDecibels {
    if (!QLMIsSavableLevel(lowestDecibels)) {
        return NO;
    }
    [_defaults setDouble:[self boundedLowest:lowestDecibels] forKey:QLMLowestKey];
    return YES;
}

- (double)boundedVolume:(double)decibels {
    return fmax(QLMVolumeDecibelsMin, fmin(self.ceilingDecibels, QLMNearestStepDecibels(decibels)));
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
