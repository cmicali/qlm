#import "QLMSetup.h"

// For the reader, which builds setups. Nothing else writes them.

NS_ASSUME_NONNULL_BEGIN

@interface QLMSetupBand ()
@property (nonatomic, readwrite) QLMSetupBandType type;
@property (nonatomic, readwrite) NSInteger index;
@property (nonatomic, readwrite) double frequency;
@property (nonatomic, readwrite) double gain;
@property (nonatomic, readwrite) double q;
@property (nonatomic, readwrite) double sampleRate;
@end

@interface QLMSetupNode ()
@property (nonatomic, readwrite) NSString *className;
@property (nonatomic, readwrite) QLMSetupNodeClass nodeClass;
@property (nonatomic, readwrite) NSString *serial;
@property (nonatomic, readwrite, nullable) NSData *hardwareID;
@property (nonatomic, readwrite) BOOL on;
@property (nonatomic, readwrite) double levelSensitivity;
@property (nonatomic, readwrite) double calibrationLevel;
@property (nonatomic, readwrite) double optionalGain;
@property (nonatomic, readwrite) double timeOfFlightCompensation;
@property (nonatomic, readwrite) double videoDelay;
@property (nonatomic, readwrite) double groupSensitivity;
@property (nonatomic, readwrite) NSInteger input;
@property (nonatomic, readwrite) NSInteger aesChannel;
@property (nonatomic, readwrite) double crossoverFrequency;
@property (nonatomic, readwrite, nullable) NSNumber *phaseDegrees;
@property (nonatomic, readwrite, nullable) NSNumber *lfePlus10;
@property (nonatomic, readwrite, nullable) NSNumber *lfeChannel;
@property (nonatomic, readwrite, nullable) NSNumber *lfeCrossoverFrequency;
@property (nonatomic, readwrite, nullable) NSNumber *lfeLevel;
@property (nonatomic, readwrite, nullable) NSNumber *subwooferGroupID;
@property (nonatomic, readwrite, nullable) NSNumber *groupDelayCompensation;
@property (nonatomic, readwrite, nullable) NSNumber *bassExtensionCrossover;
@property (nonatomic, readwrite) NSArray<QLMSetupBand *> *bands;
@end

@interface QLMSetupGroup ()
@property (nonatomic, readwrite) NSString *name;
@property (nonatomic, readwrite, nullable) NSString *calibrated;
@property (nonatomic, readwrite) double groupSensitivity;
@property (nonatomic, readwrite) double crossover;
@property (nonatomic, readwrite) NSInteger crossoverGlobalMode;
@property (nonatomic, readwrite, nullable) NSNumber *groupDelayCompensation;
@property (nonatomic, readwrite, nullable) NSNumber *bassExtensionMode;
@property (nonatomic, readwrite, nullable) NSNumber *bassExtensionCrossoverMin;
@property (nonatomic, readwrite, nullable) NSNumber *bassExtensionCrossoverMax;
@property (nonatomic, readwrite) double videoDelay;
@property (nonatomic, readwrite) BOOL subwooferBypass;
@property (nonatomic, readwrite, nullable) NSNumber *volumePreset1;
@property (nonatomic, readwrite, nullable) NSNumber *volumePreset2;
@property (nonatomic, readwrite, nullable) QLMSetupBand *lowShelf;
@property (nonatomic, readwrite, nullable) QLMSetupBand *highShelf;
@property (nonatomic, readwrite) NSArray<QLMSetupNode *> *nodes;
@property (nonatomic, readwrite) NSArray<QLMSetupNode *> *nodesInDeviceOrder;
@end

@interface QLMSetupDevice ()
@property (nonatomic, readwrite) NSString *model;
@property (nonatomic, readwrite) NSInteger type;
@property (nonatomic, readwrite, nullable) NSString *serial;
@property (nonatomic, readwrite, nullable) NSData *hardwareID;
@property (nonatomic, readwrite) NSString *name;
@property (nonatomic, readwrite, nullable) NSString *hardwareVersion;
@property (nonatomic, readwrite, nullable) NSString *dspVersion;
@property (nonatomic, readwrite, nullable) NSString *microVersion;
@property (nonatomic, readwrite) BOOL dbmFilter;
@end

@interface QLMSetup ()
@property (nonatomic, readwrite) NSString *magic;
@property (nonatomic, readwrite, nullable) NSString *glmVersion;
@property (nonatomic, readwrite, nullable) NSString *setupName;
@property (nonatomic, readwrite, nullable) NSString *layoutStyle;
@property (nonatomic, readwrite) double volume;
@property (nonatomic, readwrite) BOOL volumeMute;
@property (nonatomic, readwrite) BOOL volumeDim;
@property (nonatomic, readwrite) double volumeMaxLimit;
@property (nonatomic, readwrite) double startupLevel;
@property (nonatomic, readwrite) BOOL startupLevelEnabled;
@property (nonatomic, readwrite) BOOL automaticPowerUp;
@property (nonatomic, readwrite) BOOL automaticShutDown;
@property (nonatomic, readwrite) NSInteger issDelay;
@property (nonatomic, readwrite) NSInteger issSensitivity;
@property (nonatomic, readwrite) BOOL ledDisable;
@property (nonatomic, readwrite) NSInteger inputMode;
@property (nonatomic, readwrite) NSInteger activeGroup;
@property (nonatomic, readwrite, nullable) QLMSetupDevice *adapter;
@property (nonatomic, readwrite) NSArray<QLMSetupDevice *> *devices;
@property (nonatomic, readwrite) NSArray<QLMSetupGroup *> *groups;
@property (nonatomic, readwrite) NSArray<NSString *> *unknownKeys;
@end

NS_ASSUME_NONNULL_END
