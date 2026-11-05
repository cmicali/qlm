#import <Foundation/Foundation.h>

@class QLMFakeBus;
@class QLMKnownLease;
@class QLMSnapshot;
@class QLMSystemSettings;

NS_ASSUME_NONNULL_BEGIN

// The narrowest the volume range may get, from its bottom to the ceiling.
extern const double QLMVolumeRangeMinimumSpan;

// Where the OSD shows on the main screen.
typedef NS_ENUM(NSInteger, QLMOSDPlacement) {
    QLMOSDPlacementTopLeft = 0,
    QLMOSDPlacementTopCenter,
    QLMOSDPlacementTopRight,
    QLMOSDPlacementBottomLeft,
    QLMOSDPlacementBottomCenter,
    QLMOSDPlacementBottomRight,
};

// How long the OSD stays up, in half seconds.
extern const NSTimeInterval QLMOSDSecondsMin;
extern const NSTimeInterval QLMOSDSecondsMax;
extern const NSTimeInterval QLMOSDSecondsStep;

// How long a raise of the kept level or knob reading may wait to be written.
extern const NSTimeInterval QLMKeptRaiseDelay;

// Runs the block once, after the delay, on the main queue.
typedef void (^QLMKeptScheduler)(NSTimeInterval delay, dispatch_block_t block);

// What one bus keeps across launches: the app's level, System's mute record,
// and the leases. The real monitors and the fake bus each keep their own, so
// nothing set on the fake bus reaches the real monitors. On the main queue.
@interface QLMBusPreferences : NSObject

// Each snapshot's level and knob reading are written at most once each
// QLMKeptRaiseDelay. TRAP: a level or a reading lower than the one written
// writes both at once, so what a crash leaves can only be quieter than what
// was heard. A stopped System's snapshot writes them at once too. Reads see
// what waits. dispatch_after on the main queue until set.
@property (nonatomic, copy) QLMKeptScheduler scheduler;
// Writes what waits now. Call at every stop.
- (void)flush;

// The app's own level. At connect System keeps it until the knob turns.
// Never above the ceiling.
@property (nonatomic, readonly) double volumeDecibels;
// NO for a level above 0 dB, which keeps the old one.
- (BOOL)saveVolumeDecibels:(double)volumeDecibels __attribute__((warn_unused_result));
// System's mute record: the muted hardware IDs, whether mute all is on, and
// the monitors the user lifted it from. No reply reports a monitor's mute,
// so the record is the truth.
@property (nonatomic, copy) NSSet<NSData *> *mutedHardwareIDs;
@property (nonatomic) BOOL mutingAll;
@property (nonatomic, copy) NSSet<NSData *> *liftedHardwareIDs;
// The session each monitor last held, which the next System checks before
// it leases anything.
@property (nonatomic, copy) NSArray<QLMKnownLease *> *knownLeases;
// The knob's last reading: whether one was read, and then its tenths of a
// dB, or nil with no knob in. The next start compares the knob with it. A
// reading kept wrong reads as no knob, so the next start can only cap.
@property (nonatomic, readonly) BOOL knobRead;
@property (nonatomic, readonly, nullable) NSNumber *knobTenths;
// Puts a fresh fake bus's knob where the last one read, so a relaunch on
// the fake bus finds it unmoved.
- (void)restoreKnobOn:(QLMFakeBus *)bus;

// Keeps what changed in the snapshot. The record, the leases, and the knob
// come only from a running System's.
- (void)keepFromSnapshot:(QLMSnapshot *)snapshot;

// Sets the mute record and the leases System starts from.
- (void)fillSettings:(QLMSystemSettings *)settings;

@end

// The user's choices, kept in NSUserDefaults. Each level's save keeps it in
// range and on GLM's 0.5 dB steps. It refuses a level above 0 dB, and keeps
// the old one, though Settings and the debug channel refuse one first. A
// level kept above 0 dB, or not a number, which only a hand edit could
// store, reads as its default. On the main queue.
@interface QLMPreferences : NSObject

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

// System caps every volume frame at it. At most 0 dB, and at least the
// span above the bottom of the range. A value between steps falls to the
// step below. System's default until the user sets one.
@property (nonatomic, readonly) double ceilingDecibels;
- (BOOL)saveCeilingDecibels:(double)ceilingDecibels __attribute__((warn_unused_result));
// The slider's bottom. At least QLMVolumeDecibelsMin, and at least the span
// below the ceiling.
@property (nonatomic, readonly) double lowestDecibels;
- (BOOL)saveLowestDecibels:(double)lowestDecibels __attribute__((warn_unused_result));
@property (nonatomic) BOOL wakesAtLaunch;
// On, System drives the real monitors through the GLM adapter. Off, the
// fake bus. Off by default.
@property (nonatomic) BOOL usesAdapter;
// What the real monitors keep, and what the fake bus keeps.
@property (nonatomic, readonly) QLMBusPreferences *adapterBus;
@property (nonatomic, readonly) QLMBusPreferences *fakeBus;
// Flushes both buses.
- (void)flushKept;
// A file name in QLMSetupDirectory(). Nil takes the first by name.
@property (nonatomic, copy, nullable) NSString *setupFileName;
// On by default. Turned off, the menu bar item alone shows at launch.
@property (nonatomic) BOOL opensWindowAtLaunch;
// The main window's skin, as QLMSkinLibrary names it. QLMSkinDefaultName
// until set. A skin that no longer loads falls back at the load, not here.
@property (nonatomic, copy) NSString *skinName;
// Whether a turn of the adapter's knob shows the OSD. On by default.
@property (nonatomic) BOOL showsOSD;
// Bottom center by default. Kept by name, so a name it doesn't know reads
// as the default.
@property (nonatomic) QLMOSDPlacement osdPlacement;
// Held to QLMOSDSecondsMin to QLMOSDSecondsMax, on the nearest half
// second. A save of no number keeps the old one. 2 s by default.
@property (nonatomic) NSTimeInterval osdSeconds;

@end

// At or under 0 dB, the monitors' full level. NaN is not.
BOOL QLMIsSavableLevel(double decibels);

// The placement's name as kept, "bottomCenter".
NSString *QLMOSDPlacementName(QLMOSDPlacement placement);

// GLM 5's folder of setup files.
NSString *QLMSetupDirectory(void);

// The .sam files in it, sorted by name.
NSArray<NSString *> *QLMSetupFileNames(void);

NS_ASSUME_NONNULL_END
