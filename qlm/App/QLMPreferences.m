#import "QLMPreferences.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMFakeBus.h"
#import "QLMScheduler.h"
#import "QLMSkinLibrary.h"
#import "QLMSystem.h"

const double QLMVolumeRangeMinimumSpan = 10;
const NSTimeInterval QLMOSDSecondsMin = 0.5;
const NSTimeInterval QLMOSDSecondsMax = 10;
const NSTimeInterval QLMOSDSecondsStep = 0.5;
const NSTimeInterval QLMKeptRaiseDelay = 1;
static const NSTimeInterval QLMDefaultOSDSeconds = 2;
static const double QLMDefaultLowestDecibels = -60;
static const double QLMDefaultVolumeDecibels = -40;

static NSString *const QLMCeilingKey = @"QLMCeilingDecibels";
static NSString *const QLMLowestKey = @"QLMLowestDecibels";
static NSString *const QLMWakesAtLaunchKey = @"QLMWakesAtLaunch";
static NSString *const QLMUsesAdapterKey = @"QLMUsesAdapter";
static NSString *const QLMSetupFileNameKey = @"QLMSetupFileName";
static NSString *const QLMOpensWindowAtLaunchKey = @"QLMOpensWindowAtLaunch";
static NSString *const QLMSkinNameKey = @"QLMSkinName";
static NSString *const QLMShowsOSDKey = @"QLMShowsOSD";
static NSString *const QLMOSDPlacementKey = @"QLMOSDPlacement";
static NSString *const QLMOSDSecondsKey = @"QLMOSDSeconds";
// Each bus's keys are its prefix and a name. The real monitors' came first,
// with no word between.
static NSString *const QLMAdapterBusPrefix = @"QLM";
static NSString *const QLMFakeBusPrefix = @"QLMFake";
static NSString *const QLMVolumeName = @"VolumeDecibels";
static NSString *const QLMMutedName = @"MutedHardwareIDs";
static NSString *const QLMMutingAllName = @"MutingAll";
static NSString *const QLMLiftedName = @"LiftedHardwareIDs";
static NSString *const QLMLeasesName = @"KnownLeases";
static NSString *const QLMKnobReadName = @"KnobRead";
static NSString *const QLMKnobName = @"KnobTenths";
static NSString *const QLMLeaseHardwareIDKey = @"hardwareID";
static NSString *const QLMLeaseSerialKey = @"serialNumber";
static NSString *const QLMLeaseSessionKey = @"session";

static double QLMStepBelow(double decibels) {
    return floor(decibels / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep;
}

BOOL QLMIsSavableLevel(double decibels) {
    return decibels <= QLMVolumeDecibelsMax;
}

// NAN when nothing is kept, or what is kept is no number. TRAP:
// doubleForKey: reads a string that is no number, or nothing, as 0.
static double QLMKeptNumber(NSUserDefaults *defaults, NSString *key) {
    id kept = [defaults objectForKey:key];
    return [kept isKindOfClass:[NSNumber class]] ? [kept doubleValue] : NAN;
}

// Anything but a number at or under 0 dB reads as the default. The levels
// register no default, so a key with none can't read as 0 dB.
static double QLMKeptLevel(NSUserDefaults *defaults, NSString *key, double fallback) {
    double decibels = QLMKeptNumber(defaults, key);
    return QLMIsSavableLevel(decibels) ? decibels : fallback;
}

// In QLMOSDPlacement's order. A function, since a literal array is no
// constant at file scope.
static NSArray<NSString *> *QLMOSDPlacementNames(void) {
    return @[@"topLeft", @"topCenter", @"topRight", @"bottomLeft", @"bottomCenter", @"bottomRight"];
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
    __weak QLMPreferences *_preferences;  // for the ceiling
    NSString *_volumeKey;
    NSString *_mutedKey;
    NSString *_mutingAllKey;
    NSString *_liftedKey;
    NSString *_leasesKey;
    NSString *_knobReadKey;
    NSString *_knobKey;
    // The one thing kept outside the defaults: a raise, waiting its turn.
    // The level is as it plays, under the ceiling at the time.
    BOOL _volumeWaits;
    double _waitingVolume;
    BOOL _knobWaits;
    NSNumber *_waitingKnob;
    BOOL _flushScheduled;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults prefix:(NSString *)prefix preferences:(QLMPreferences *)preferences {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _preferences = preferences;
        _volumeKey = [prefix stringByAppendingString:QLMVolumeName];
        _mutedKey = [prefix stringByAppendingString:QLMMutedName];
        _mutingAllKey = [prefix stringByAppendingString:QLMMutingAllName];
        _liftedKey = [prefix stringByAppendingString:QLMLiftedName];
        _leasesKey = [prefix stringByAppendingString:QLMLeasesName];
        _knobReadKey = [prefix stringByAppendingString:QLMKnobReadName];
        _knobKey = [prefix stringByAppendingString:QLMKnobName];
        _scheduler = QLMMainQueueScheduler();
    }
    return self;
}

#pragma mark - The level and the knob

// As the defaults hold it, not bounded by the ceiling, which may have fallen
// since it was written.
- (double)storedVolume {
    return QLMKeptLevel(_defaults, _volumeKey, QLMDefaultVolumeDecibels);
}

- (double)volumeDecibels {
    return [_preferences boundedVolume:_volumeWaits ? _waitingVolume : [self storedVolume]];
}

- (BOOL)saveVolumeDecibels:(double)volumeDecibels {
    if (!QLMIsSavableLevel(volumeDecibels)) {
        return NO;
    }
    _volumeWaits = YES;
    _waitingVolume = [_preferences boundedVolume:volumeDecibels];
    [self writeWaiting];
    return YES;
}

- (BOOL)storedKnobRead {
    id kept = [_defaults objectForKey:_knobReadKey];
    return [kept isKindOfClass:[NSNumber class]] && [kept boolValue];
}

- (nullable NSNumber *)storedKnobTenths {
    if (!self.storedKnobRead) {
        return nil;
    }
    double tenths = QLMKeptNumber(_defaults, _knobKey);
    return tenths == floor(tenths) && tenths <= 0 && tenths > INT32_MIN ? @((NSInteger)tenths) : nil;
}

- (BOOL)knobRead {
    return _knobWaits || self.storedKnobRead;
}

- (NSNumber *)knobTenths {
    return _knobWaits ? _waitingKnob : self.storedKnobTenths;
}

// Writes a reading at once. Only the tests call it.
- (void)keepKnobTenths:(nullable NSNumber *)knobTenths {
    _knobWaits = YES;
    _waitingKnob = knobTenths;
    [self writeWaiting];
}

// Whether what waits is quieter than what the defaults hold. A knob put in
// or taken out counts.
- (BOOL)waitingLowers {
    if (_volumeWaits && _waitingVolume < [self storedVolume]) {
        return YES;
    }
    if (!_knobWaits) {
        return NO;
    }
    NSNumber *stored = self.storedKnobTenths;
    return stored == nil || _waitingKnob == nil || _waitingKnob.integerValue < stored.integerValue;
}

- (void)writeWaiting {
    if (_volumeWaits) {
        _volumeWaits = NO;
        [_defaults setDouble:[_preferences boundedVolume:_waitingVolume] forKey:_volumeKey];
    }
    if (_knobWaits) {
        _knobWaits = NO;
        [_defaults setObject:_waitingKnob forKey:_knobKey];
        if (!self.storedKnobRead) {
            [_defaults setBool:YES forKey:_knobReadKey];
        }
    }
}

// What waits goes now. With none, a level stored above the ceiling goes
// down to it, so a stop never leaves one louder than it can play. TRAP: it
// only ever lowers what is stored, so a second copy of the app on the same
// defaults can't raise what the other wrote.
- (void)flush {
    if (!_volumeWaits) {
        double stored = [self storedVolume];
        double plays = [_preferences boundedVolume:stored];
        if (plays < stored) {
            _volumeWaits = YES;
            _waitingVolume = plays;
        }
    }
    [self writeWaiting];
}

- (void)flushKeeping:(QLMSnapshot *)last {
    if (last != nil) {
        [self keepFromSnapshot:last];
    }
    [self flush];
}

- (void)scheduleFlush {
    if (_flushScheduled) {
        return;
    }
    _flushScheduled = YES;
    __weak QLMBusPreferences *weakSelf = self;
    self.scheduler(QLMKeptRaiseDelay, ^{
        QLMBusPreferences *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_flushScheduled = NO;
            [strongSelf writeWaiting];
        }
    });
}

- (void)restoreKnobOn:(QLMFakeBus *)bus {
    if (!self.knobRead) {
        return;
    }
    NSNumber *tenths = self.knobTenths;
    [bus perform:^{
        bus.knobTenths = tenths;
    }];
}

#pragma mark - The record and the leases

// Kept as a list of data, which a property list can hold.
- (NSSet<NSData *> *)hardwareIDsAt:(NSString *)key {
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    for (id item in [_defaults arrayForKey:key]) {
        if ([item isKindOfClass:[NSData class]]) {
            [hardwareIDs addObject:item];
        }
    }
    return hardwareIDs;
}

- (NSSet<NSData *> *)mutedHardwareIDs {
    return [self hardwareIDsAt:_mutedKey];
}

- (BOOL)mutingAll {
    return [_defaults boolForKey:_mutingAllKey];
}

- (NSSet<NSData *> *)liftedHardwareIDs {
    return [self hardwareIDsAt:_liftedKey];
}

// System checks each lease again before it takes one.
- (NSArray<QLMKnownLease *> *)knownLeases {
    NSMutableArray<QLMKnownLease *> *leases = [NSMutableArray array];
    for (id item in [_defaults arrayForKey:_leasesKey]) {
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

#pragma mark - A snapshot

// TRAP: a snapshot from before System starts carries an empty record, not
// the one System starts from. Each value is compared with the defaults, so
// an unchanged one writes nothing, and one changed from outside is put
// right.
- (void)keepFromSnapshot:(QLMSnapshot *)snapshot {
    // The knob moves the volume too. Keep whichever set it last. System
    // never reports one above 0 dB.
    NSNumber *volume = snapshot.volumeDecibels;
    if (volume != nil && QLMIsSavableLevel(volume.doubleValue)) {
        double plays = [_preferences boundedVolume:volume.doubleValue];
        if (plays != (_volumeWaits ? _waitingVolume : [self storedVolume])) {
            _volumeWaits = YES;
            _waitingVolume = plays;
        }
    }
    if (snapshot.running) {
        [self keepRecordFromSnapshot:snapshot];
        [self keepKnobFromSnapshot:snapshot];
    }
    if (!snapshot.running) {
        [self flush];
    } else if ([self waitingLowers]) {
        [self writeWaiting];
    } else if (_volumeWaits || _knobWaits) {
        [self scheduleFlush];
    }
}

// The record's three keys go together, so a crash can't keep half of it.
- (void)keepRecordFromSnapshot:(QLMSnapshot *)snapshot {
    if (![snapshot.mutedHardwareIDs isEqualToSet:self.mutedHardwareIDs] || snapshot.mutingAll != self.mutingAll
        || ![snapshot.liftedHardwareIDs isEqualToSet:self.liftedHardwareIDs]) {
        [_defaults setObject:snapshot.mutedHardwareIDs.allObjects forKey:_mutedKey];
        [_defaults setBool:snapshot.mutingAll forKey:_mutingAllKey];
        [_defaults setObject:snapshot.liftedHardwareIDs.allObjects forKey:_liftedKey];
    }
    NSArray<NSDictionary *> *leases = QLMLeasesPlist(snapshot.knownLeases);
    if (![leases isEqualToArray:[_defaults arrayForKey:_leasesKey] ?: @[]]) {
        [_defaults setObject:leases forKey:_leasesKey];
    }
}

- (void)keepKnobFromSnapshot:(QLMSnapshot *)snapshot {
    if (!snapshot.adapter.hasStatus) {
        return;
    }
    NSNumber *knob = snapshot.adapter.knobTenths;
    if (!self.knobRead || ![(knob ?: NSNull.null) isEqual:(self.knobTenths ?: NSNull.null)]) {
        _knobWaits = YES;
        _waitingKnob = knob;
    }
}

- (void)fillSettings:(QLMSystemSettings *)settings {
    settings.mutedHardwareIDs = self.mutedHardwareIDs;
    settings.mutingAll = self.mutingAll;
    settings.liftedHardwareIDs = self.liftedHardwareIDs;
    settings.knownLeases = self.knownLeases;
    settings.knobRead = self.knobRead;
    settings.knobTenths = self.knobTenths;
}

@end

@implementation QLMPreferences {
    NSUserDefaults *_defaults;
    double _defaultCeilingDecibels;  // System's
}

- (void)flushKept {
    [_adapterBus flush];
    [_fakeBus flush];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _adapterBus = [[QLMBusPreferences alloc] initWithDefaults:defaults prefix:QLMAdapterBusPrefix preferences:self];
        _fakeBus = [[QLMBusPreferences alloc] initWithDefaults:defaults prefix:QLMFakeBusPrefix preferences:self];
        _defaultCeilingDecibels = [[QLMSystemSettings alloc] init].ceilingDecibels;
        [defaults registerDefaults:@{
            QLMWakesAtLaunchKey: @NO,
            QLMUsesAdapterKey: @NO,
            QLMOpensWindowAtLaunchKey: @YES,
            QLMShowsOSDKey: @YES,
        }];
    }
    return self;
}

// Read through the save's bounds too, so a hand-edited default stays on a
// step and above the range's bottom.
- (double)ceilingDecibels {
    return fmax(QLMVolumeDecibelsMin + QLMVolumeRangeMinimumSpan, QLMStepBelow(QLMKeptLevel(_defaults, QLMCeilingKey, _defaultCeilingDecibels)));
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
    return [self boundedLowest:QLMKeptLevel(_defaults, QLMLowestKey, QLMDefaultLowestDecibels)];
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

- (BOOL)opensWindowAtLaunch {
    return [_defaults boolForKey:QLMOpensWindowAtLaunchKey];
}

- (void)setOpensWindowAtLaunch:(BOOL)opensWindowAtLaunch {
    [_defaults setBool:opensWindowAtLaunch forKey:QLMOpensWindowAtLaunchKey];
}

- (NSString *)skinName {
    NSString *name = [_defaults stringForKey:QLMSkinNameKey];
    return name.length > 0 ? name : QLMSkinDefaultName;
}

- (void)setSkinName:(NSString *)skinName {
    [_defaults setObject:skinName forKey:QLMSkinNameKey];
}

- (BOOL)showsOSD {
    return [_defaults boolForKey:QLMShowsOSDKey];
}

- (void)setShowsOSD:(BOOL)showsOSD {
    [_defaults setBool:showsOSD forKey:QLMShowsOSDKey];
}

- (QLMOSDPlacement)osdPlacement {
    id kept = [_defaults objectForKey:QLMOSDPlacementKey];
    NSUInteger index = kept == nil ? NSNotFound : [QLMOSDPlacementNames() indexOfObject:kept];
    return index == NSNotFound ? QLMOSDPlacementBottomCenter : (QLMOSDPlacement)index;
}

- (void)setOsdPlacement:(QLMOSDPlacement)osdPlacement {
    [_defaults setObject:QLMOSDPlacementName(osdPlacement) forKey:QLMOSDPlacementKey];
}

static NSTimeInterval QLMBoundedOSDSeconds(NSTimeInterval seconds) {
    return fmax(QLMOSDSecondsMin, fmin(QLMOSDSecondsMax, round(seconds / QLMOSDSecondsStep) * QLMOSDSecondsStep));
}

- (NSTimeInterval)osdSeconds {
    double seconds = QLMKeptNumber(_defaults, QLMOSDSecondsKey);
    return isfinite(seconds) ? QLMBoundedOSDSeconds(seconds) : QLMDefaultOSDSeconds;
}

- (void)setOsdSeconds:(NSTimeInterval)osdSeconds {
    if (isnan(osdSeconds)) {
        return;
    }
    [_defaults setDouble:QLMBoundedOSDSeconds(osdSeconds) forKey:QLMOSDSecondsKey];
}

@end

NSString *QLMOSDPlacementName(QLMOSDPlacement placement) {
    return QLMOSDPlacementNames()[(NSUInteger)placement];
}

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
