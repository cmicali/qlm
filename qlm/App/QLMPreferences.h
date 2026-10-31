#import <Foundation/Foundation.h>

@class QLMKnownLease;
@class QLMSnapshot;
@class QLMSystemSettings;

NS_ASSUME_NONNULL_BEGIN

// The narrowest the volume range may get, from its bottom to the ceiling.
extern const double QLMVolumeRangeMinimumSpan;

// What one bus keeps across launches: the app's level, System's mute record,
// and the leases. The real monitors and the fake bus each keep their own, so
// nothing set on the fake bus reaches the real monitors. On the main queue.
@interface QLMBusPreferences : NSObject

// The app's own level. At connect System keeps it until the knob turns.
// Never above the ceiling.
@property (nonatomic) double volumeDecibels;
// System's mute record: the muted hardware IDs, whether mute all is on, and
// the monitors the user lifted it from. No reply reports a monitor's mute,
// so the record is the truth.
@property (nonatomic, copy) NSSet<NSData *> *mutedHardwareIDs;
@property (nonatomic) BOOL mutingAll;
@property (nonatomic, copy) NSSet<NSData *> *liftedHardwareIDs;
// The session each monitor last held, which the next System checks before
// it leases anything.
@property (nonatomic, copy) NSArray<QLMKnownLease *> *knownLeases;

// Keeps what changed in the snapshot. The record and the leases come only
// from a running System's.
- (void)keepFromSnapshot:(QLMSnapshot *)snapshot;

// Sets the mute record and the leases System starts from.
- (void)fillSettings:(QLMSystemSettings *)settings;

@end

// The user's choices, kept in NSUserDefaults. Each setter keeps its value in
// range and on GLM's 0.5 dB steps. On the main queue.
@interface QLMPreferences : NSObject

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

// System caps every volume frame at it. At most 0 dB, and at least the
// span above the bottom of the range. A value between steps falls to the
// step below. System's default until the user sets one.
@property (nonatomic) double ceilingDecibels;
// The slider's bottom. At least QLMVolumeDecibelsMin, and at least the span
// below the ceiling.
@property (nonatomic) double lowestDecibels;
@property (nonatomic) BOOL wakesAtLaunch;
// On, System drives the real monitors through the GLM adapter. Off, the
// fake bus. Off by default.
@property (nonatomic) BOOL usesAdapter;
// What the real monitors keep, and what the fake bus keeps.
@property (nonatomic, readonly) QLMBusPreferences *adapterBus;
@property (nonatomic, readonly) QLMBusPreferences *fakeBus;
// A file name in QLMSetupDirectory(). Nil takes the first by name.
@property (nonatomic, copy, nullable) NSString *setupFileName;

@end

// The nearest of GLM's 0.5 dB steps.
double QLMNearestStepDecibels(double decibels);

// GLM 5's folder of setup files.
NSString *QLMSetupDirectory(void);

// The .sam files in it, sorted by name.
NSArray<NSString *> *QLMSetupFileNames(void);

NS_ASSUME_NONNULL_END
