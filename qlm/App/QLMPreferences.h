#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The narrowest the volume range may get, from its bottom to the ceiling.
extern const double QLMVolumeRangeMinimumSpan;

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
// The app's own level, kept across launches. At connect System keeps it
// until the knob turns. Never above the ceiling.
@property (nonatomic) double volumeDecibels;
@property (nonatomic) BOOL wakesAtLaunch;
// On, System drives the real monitors through the GLM adapter. Off, the
// fake bus. Off by default.
@property (nonatomic) BOOL usesAdapter;
// A file name in QLMSetupDirectory(). Nil takes the first by name.
@property (nonatomic, copy, nullable) NSString *setupFileName;

// What goes out for this volume: GLMProtocol caps every frame at the
// ceiling.
- (double)cappedDecibels:(double)decibels;
// The same, less QLMDimDecibels while dimmed, as GLMProtocol's dim frame.
- (double)sentDecibels:(double)decibels dimmed:(BOOL)dimmed;

@end

// The nearest of GLM's 0.5 dB steps.
double QLMNearestStepDecibels(double decibels);

// GLM 5's folder of setup files.
NSString *QLMSetupDirectory(void);

// The .sam files in it, sorted by name.
NSArray<NSString *> *QLMSetupFileNames(void);

NS_ASSUME_NONNULL_END
