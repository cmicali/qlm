#import "QLMPreferences.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMFakeBus.h"
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

// Every bus's writes, in order, off the main queue: a write sends its
// value to cfprefsd, which costs far more than the decision to make it.
// Every read waits for the writes queued before it, so it sees them.
static dispatch_queue_t QLMKeptWrites(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.commonwealthrecordings.qlm.kept-writes",
                                      dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

@interface QLMBusPreferences ()
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults prefix:(NSString *)prefix preferences:(QLMPreferences *)preferences;
@end

@implementation QLMBusPreferences {
    NSUserDefaults *_defaults;
    NSString *_prefix;
    __weak QLMPreferences *_preferences;  // for the ceiling
    // What waits to be written.
    BOOL _volumeWaits;
    double _waitingVolume;
    BOOL _knobWaits;
    NSNumber *_waitingKnob;
    BOOL _flushScheduled;
    // What the defaults hold, as stored, read once and then kept with each
    // write, so a decision reads no defaults. Only this bus writes its keys.
    // TRAP: the level as stored, not as the ceiling bounds it. Bounded, a
    // level above a lowered ceiling read as the level that plays, so it was
    // never written, and showed again once the ceiling rose.
    BOOL _writtenLoaded;
    double _writtenVolume;
    BOOL _writtenKnobRead;
    NSNumber *_writtenKnob;
    // The last snapshot's values, so an unchanged one compares nothing
    // with the defaults. A write by any other path clears them.
    NSNumber *_seenVolume;
    NSSet<NSData *> *_seenMuted;
    NSNumber *_seenMutingAll;
    NSSet<NSData *> *_seenLifted;
    NSArray<QLMKnownLease *> *_seenLeases;
    id _seenKnob;  // NSNull for no knob
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults prefix:(NSString *)prefix preferences:(QLMPreferences *)preferences {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _prefix = [prefix copy];
        _preferences = preferences;
        _scheduler = ^(NSTimeInterval delay, dispatch_block_t block) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
        };
    }
    return self;
}

- (NSString *)key:(NSString *)name {
    return [_prefix stringByAppendingString:name];
}

// The defaults, once every write queued before has landed.
- (NSUserDefaults *)read {
    dispatch_sync(QLMKeptWrites(), ^{
    });
    return _defaults;
}

- (void)write:(void (^)(NSUserDefaults *defaults))write {
    NSUserDefaults *defaults = _defaults;
    dispatch_async(QLMKeptWrites(), ^{
        write(defaults);
    });
}

// The queue's blocks never wait on the main queue, so this can't deadlock.
- (void)writeNow:(void (^)(NSUserDefaults *defaults))write {
    NSUserDefaults *defaults = _defaults;
    dispatch_sync(QLMKeptWrites(), ^{
        write(defaults);
    });
}

- (double)storedVolume {
    return QLMKeptLevel(self.read, [self key:QLMVolumeName], QLMDefaultVolumeDecibels);
}

- (double)writtenVolume {
    return [_preferences boundedVolume:[self storedVolume]];
}

- (void)loadWritten {
    if (_writtenLoaded) {
        return;
    }
    _writtenLoaded = YES;
    _writtenVolume = [self storedVolume];
    _writtenKnobRead = self.writtenKnobRead;
    _writtenKnob = self.writtenKnobTenths;
}

- (double)volumeDecibels {
    return _volumeWaits ? [_preferences boundedVolume:_waitingVolume] : [self writtenVolume];
}

- (BOOL)saveVolumeDecibels:(double)volumeDecibels {
    if (!QLMIsSavableLevel(volumeDecibels)) {
        return NO;
    }
    _seenVolume = nil;
    _volumeWaits = YES;
    _waitingVolume = volumeDecibels;
    [self flush];
    return YES;
}

// Kept as a list of data, which a property list can hold.
- (NSSet<NSData *> *)hardwareIDsNamed:(NSString *)name {
    NSMutableSet<NSData *> *hardwareIDs = [NSMutableSet set];
    for (id item in [self.read arrayForKey:[self key:name]]) {
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
    _seenMuted = nil;
    NSArray<NSData *> *list = mutedHardwareIDs.allObjects;
    NSString *key = [self key:QLMMutedName];
    [self writeNow:^(NSUserDefaults *defaults) {
        [defaults setObject:list forKey:key];
    }];
}

- (BOOL)mutingAll {
    return [self.read boolForKey:[self key:QLMMutingAllName]];
}

- (void)setMutingAll:(BOOL)mutingAll {
    _seenMutingAll = nil;
    NSString *key = [self key:QLMMutingAllName];
    [self writeNow:^(NSUserDefaults *defaults) {
        [defaults setBool:mutingAll forKey:key];
    }];
}

- (NSSet<NSData *> *)liftedHardwareIDs {
    return [self hardwareIDsNamed:QLMLiftedName];
}

- (void)setLiftedHardwareIDs:(NSSet<NSData *> *)liftedHardwareIDs {
    _seenLifted = nil;
    NSArray<NSData *> *list = liftedHardwareIDs.allObjects;
    NSString *key = [self key:QLMLiftedName];
    [self writeNow:^(NSUserDefaults *defaults) {
        [defaults setObject:list forKey:key];
    }];
}

// System checks each lease again before it takes one.
- (NSArray<QLMKnownLease *> *)knownLeases {
    NSMutableArray<QLMKnownLease *> *leases = [NSMutableArray array];
    for (id item in [self.read arrayForKey:[self key:QLMLeasesName]]) {
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
    _seenLeases = nil;
    NSArray<NSDictionary *> *plist = QLMLeasesPlist(knownLeases);
    NSString *key = [self key:QLMLeasesName];
    [self write:^(NSUserDefaults *defaults) {
        [defaults setObject:plist forKey:key];
    }];
}

- (BOOL)writtenKnobRead {
    id kept = [self.read objectForKey:[self key:QLMKnobReadName]];
    return [kept isKindOfClass:[NSNumber class]] && [kept boolValue];
}

- (nullable NSNumber *)writtenKnobTenths {
    if (!self.writtenKnobRead) {
        return nil;
    }
    double tenths = QLMKeptNumber(self.read, [self key:QLMKnobName]);
    return tenths == floor(tenths) && tenths <= 0 && tenths > INT32_MIN ? @((NSInteger)tenths) : nil;
}

- (BOOL)knobRead {
    return _knobWaits || self.writtenKnobRead;
}

- (NSNumber *)knobTenths {
    return _knobWaits ? _waitingKnob : self.writtenKnobTenths;
}

// Writes a reading at once. Only the tests call it.
- (void)keepKnobTenths:(nullable NSNumber *)knobTenths {
    _seenKnob = nil;
    _knobWaits = YES;
    _waitingKnob = knobTenths;
    [self flush];
}

// Whether what waits is lower than what is stored. A knob put in or taken
// out counts.
- (BOOL)waitingLowers {
    [self loadWritten];
    if (_volumeWaits && _waitingVolume < _writtenVolume) {
        return YES;
    }
    if (!_knobWaits) {
        return NO;
    }
    return !_writtenKnobRead || _writtenKnob == nil || _waitingKnob == nil || _waitingKnob.integerValue < _writtenKnob.integerValue;
}

// Writes what waits. A lowering and a stop wait until it has landed, so a
// crash just after can't lose it. A raise is queued.
- (void)writeWaitingAndWait:(BOOL)waits {
    if (!_volumeWaits && !_knobWaits) {
        if (waits) {
            [self writeNow:^(NSUserDefaults *defaults) {
            }];
        }
        return;
    }
    [self loadWritten];
    BOOL volumeWaits = _volumeWaits;
    BOOL knobWaits = _knobWaits;
    double volume = [_preferences boundedVolume:_waitingVolume];
    NSNumber *knob = _waitingKnob;
    if (volumeWaits) {
        _volumeWaits = NO;
        _writtenVolume = volume;
    }
    if (knobWaits) {
        _knobWaits = NO;
        _writtenKnobRead = YES;
        _writtenKnob = knob;
    }
    NSString *volumeKey = [self key:QLMVolumeName];
    NSString *knobKey = [self key:QLMKnobName];
    NSString *readKey = [self key:QLMKnobReadName];
    void (^write)(NSUserDefaults *) = ^(NSUserDefaults *defaults) {
        if (volumeWaits) {
            [defaults setDouble:volume forKey:volumeKey];
        }
        if (knobWaits) {
            [defaults setObject:knob forKey:knobKey];
            if (![[defaults objectForKey:readKey] isEqual:@YES]) {
                [defaults setBool:YES forKey:readKey];
            }
        }
    };
    if (waits) {
        [self writeNow:write];
    } else {
        [self write:write];
    }
}

// A stop writes the level and the reading kept, changed or not, so a
// louder one put in the defaults from outside, by a hand edit or another
// copy of the app, can't outlast it. TRAP: it only ever lowers. Another
// copy on the same defaults may have written a lower level since this one
// read, and a restate of its own older level would raise it.
- (void)restateKept {
    [self loadWritten];
    if (!_volumeWaits) {
        _volumeWaits = YES;
        _waitingVolume = fmin(_writtenVolume, [self storedVolume]);
    }
    if (!_knobWaits && _writtenKnobRead) {
        _knobWaits = YES;
        _waitingKnob = _writtenKnob;
    }
}

- (void)flush {
    [self restateKept];
    [self writeWaitingAndWait:YES];
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
            [strongSelf writeWaitingAndWait:NO];
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

// TRAP: a snapshot from before System starts carries an empty record, not
// the one System starts from. Each is compared with the one kept, so an
// unchanged one writes nothing. A value the last snapshot had too is not
// compared again.
- (void)keepFromSnapshot:(QLMSnapshot *)snapshot {
    // The knob moves the volume too. Keep whichever set it last. System
    // never reports one above 0 dB.
    [self loadWritten];
    NSNumber *volume = snapshot.volumeDecibels;
    if (volume != nil && ![volume isEqual:_seenVolume]) {
        _seenVolume = volume;
        // TRAP: kept as it plays. Kept raw, a raise waiting while the
        // ceiling fell and rose was written above the level System had
        // capped for good.
        double kept = _volumeWaits ? _waitingVolume : _writtenVolume;
        double plays = [_preferences boundedVolume:volume.doubleValue];
        if (QLMIsSavableLevel(volume.doubleValue) && plays != kept) {
            _volumeWaits = YES;
            _waitingVolume = plays;
        }
    }
    if (snapshot.running) {
        [self keepRecordFromSnapshot:snapshot];
    } else {
        [self restateKept];
    }
    if (!snapshot.running || [self waitingLowers]) {
        [self writeWaitingAndWait:YES];
    } else if (_volumeWaits || _knobWaits) {
        [self scheduleFlush];
    }
}

// The mute record's three keys go in one write, which lands before this
// returns, so a crash just after a mute can't lose it, or keep part of it.
- (void)keepRecordFromSnapshot:(QLMSnapshot *)snapshot {
    NSSet<NSData *> *muted = snapshot.mutedHardwareIDs;
    NSSet<NSData *> *lifted = snapshot.liftedHardwareIDs;
    BOOL mutingAll = snapshot.mutingAll;
    BOOL seen = [muted isEqual:_seenMuted] && [lifted isEqual:_seenLifted] && _seenMutingAll != nil
                && mutingAll == _seenMutingAll.boolValue;
    if (!seen) {
        if (![muted isEqualToSet:self.mutedHardwareIDs] || mutingAll != self.mutingAll
            || ![lifted isEqualToSet:self.liftedHardwareIDs]) {
            NSArray<NSData *> *mutedList = muted.allObjects;
            NSArray<NSData *> *liftedList = lifted.allObjects;
            NSString *mutedKey = [self key:QLMMutedName];
            NSString *mutingAllKey = [self key:QLMMutingAllName];
            NSString *liftedKey = [self key:QLMLiftedName];
            [self writeNow:^(NSUserDefaults *defaults) {
                [defaults setObject:mutedList forKey:mutedKey];
                [defaults setBool:mutingAll forKey:mutingAllKey];
                [defaults setObject:liftedList forKey:liftedKey];
            }];
        }
        _seenMuted = muted;
        _seenMutingAll = @(mutingAll);
        _seenLifted = lifted;
    }
    NSArray<QLMKnownLease *> *leases = snapshot.knownLeases;
    if (![leases isEqual:_seenLeases]) {
        if (![QLMLeasesPlist(leases) isEqualToArray:[self.read arrayForKey:[self key:QLMLeasesName]] ?: @[]]) {
            self.knownLeases = leases;
        }
        _seenLeases = leases;
    }
    if (!snapshot.adapter.hasStatus) {
        return;
    }
    id knob = snapshot.adapter.knobTenths ?: NSNull.null;
    if (![knob isEqual:_seenKnob]) {
        BOOL read = _knobWaits || _writtenKnobRead;
        NSNumber *kept = _knobWaits ? _waitingKnob : _writtenKnob;
        if (!read || ![knob isEqual:(kept ?: NSNull.null)]) {
            _knobWaits = YES;
            _waitingKnob = knob == NSNull.null ? nil : knob;
        }
        _seenKnob = knob;
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
