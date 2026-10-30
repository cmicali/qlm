#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A GLM 5 setup file (.sam) as values. Immutable. The reader fills them.

typedef NS_ENUM(NSInteger, QLMSetupBandType) {
    QLMSetupBandLowShelf,
    QLMSetupBandHighShelf,
    QLMSetupBandPeak,  // "Notch" in the file
};

@interface QLMSetupBand : NSObject

@property (nonatomic, readonly) QLMSetupBandType type;
@property (nonatomic, readonly) NSInteger index;    // as the file numbers it, from 1
@property (nonatomic, readonly) double frequency;   // Hz
@property (nonatomic, readonly) double gain;        // dB
@property (nonatomic, readonly) double q;           // 0 for a shelf
@property (nonatomic, readonly) double sampleRate;  // the design rate the file states

@end

typedef NS_ENUM(NSInteger, QLMSetupNodeClass) {
    QLMSetupNodeClassUnknown = 0,
    QLMSetupNodeClassTwoWay,     // TwowayGen2
    QLMSetupNodeClassThreeWay,   // ThreewayGen2
    QLMSetupNodeClassSubwoofer,  // SubwooferGen2
};

// One device's settings within one group.
@interface QLMSetupNode : NSObject

@property (nonatomic, readonly) NSString *className;
@property (nonatomic, readonly) QLMSetupNodeClass nodeClass;
@property (nonatomic, readonly) NSString *serial;
// The monitor's three-byte hardware ID, which serial gives in decimal. Nil
// if serial is not one. TRAP: the serial from 19 01 does not end in serial.
@property (nonatomic, readonly, nullable) NSData *hardwareID;
@property (nonatomic, readonly) BOOL on;
@property (nonatomic, readonly) double levelSensitivity;        // dB
@property (nonatomic, readonly) double calibrationLevel;        // dB
@property (nonatomic, readonly) double optionalGain;            // dB
@property (nonatomic, readonly) double timeOfFlightCompensation;
@property (nonatomic, readonly) double videoDelay;
@property (nonatomic, readonly) double groupSensitivity;        // dB
@property (nonatomic, readonly) NSInteger input;                // 1 AES3 A, 2 AES3 B, 3 AES3 A+B, 4 analog
@property (nonatomic, readonly) NSInteger aesChannel;
@property (nonatomic, readonly) double crossoverFrequency;      // Hz
@property (nonatomic, readonly, nullable) NSNumber *phaseDegrees;           // subwoofers
@property (nonatomic, readonly, nullable) NSNumber *lfePlus10;              // subwoofers
@property (nonatomic, readonly, nullable) NSNumber *lfeChannel;             // subwoofers
@property (nonatomic, readonly, nullable) NSNumber *lfeCrossoverFrequency;  // subwoofers
@property (nonatomic, readonly, nullable) NSNumber *lfeLevel;               // subwoofers
@property (nonatomic, readonly, nullable) NSNumber *subwooferGroupID;       // subwoofers
@property (nonatomic, readonly) NSArray<QLMSetupBand *> *bands;

@end

@interface QLMSetupGroup : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly, nullable) NSString *calibrated;
@property (nonatomic, readonly) double groupSensitivity;  // dB
@property (nonatomic, readonly) double crossover;         // Hz
@property (nonatomic, readonly) NSInteger crossoverGlobalMode;
@property (nonatomic, readonly) double videoDelay;
@property (nonatomic, readonly) BOOL subwooferBypass;
@property (nonatomic, readonly, nullable) NSNumber *volumePreset1;  // dB
@property (nonatomic, readonly, nullable) NSNumber *volumePreset2;  // dB
@property (nonatomic, readonly, nullable) QLMSetupBand *lowShelf;   // group-level, host side
@property (nonatomic, readonly, nullable) QLMSetupBand *highShelf;
@property (nonatomic, readonly) NSArray<QLMSetupNode *> *nodes;
// The nodes in the order of the setup's devices, the order of GLM's DSP pass
// and its rounds of 2B. A node with no device follows, in node order. For a
// group no reader made, the node order.
@property (nonatomic, readonly) NSArray<QLMSetupNode *> *nodesInDeviceOrder;

- (nullable QLMSetupNode *)nodeWithSerial:(NSString *)serial;

@end

@interface QLMSetupDevice : NSObject

@property (nonatomic, readonly) NSString *model;
@property (nonatomic, readonly) NSInteger type;  // 0 adapter, 1 subwoofer, 2 two-way, 3 three-way, as observed
@property (nonatomic, readonly, nullable) NSString *serial;
// The monitor's hardware ID, which serial gives in decimal, as a node's.
@property (nonatomic, readonly, nullable) NSData *hardwareID;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly, nullable) NSString *hardwareVersion;
@property (nonatomic, readonly, nullable) NSString *dspVersion;
@property (nonatomic, readonly, nullable) NSString *microVersion;
@property (nonatomic, readonly) BOOL dbmFilter;

@end

@interface QLMSetup : NSObject

@property (nonatomic, readonly) NSString *magic;
@property (nonatomic, readonly, nullable) NSString *glmVersion;
@property (nonatomic, readonly, nullable) NSString *setupName;
@property (nonatomic, readonly, nullable) NSString *layoutStyle;
@property (nonatomic, readonly) double volume;           // dB
@property (nonatomic, readonly) BOOL volumeMute;
@property (nonatomic, readonly) BOOL volumeDim;
@property (nonatomic, readonly) double volumeMaxLimit;   // dB
@property (nonatomic, readonly) double startupLevel;     // dB
@property (nonatomic, readonly) BOOL startupLevelEnabled;
@property (nonatomic, readonly) BOOL automaticPowerUp;
@property (nonatomic, readonly) BOOL automaticShutDown;
@property (nonatomic, readonly) NSInteger issDelay;      // minutes
@property (nonatomic, readonly) NSInteger issSensitivity;
@property (nonatomic, readonly) BOOL ledDisable;
@property (nonatomic, readonly) NSInteger inputMode;
// As the file counts. Whether it counts from 0 or 1 is unverified.
@property (nonatomic, readonly) NSInteger activeGroup;
@property (nonatomic, readonly, nullable) QLMSetupDevice *adapter;
@property (nonatomic, readonly) NSArray<QLMSetupDevice *> *devices;
@property (nonatomic, readonly) NSArray<QLMSetupGroup *> *groups;
// Every key the reader did not know, as "<where>: <key>", in file order.
@property (nonatomic, readonly) NSArray<NSString *> *unknownKeys;

- (nullable QLMSetupDevice *)deviceWithSerial:(NSString *)serial;
// The device a monitor on the bus is, matched by its three-byte hardware ID.
- (nullable QLMSetupDevice *)deviceWithHardwareID:(NSData *)hardwareID;

@end

NS_ASSUME_NONNULL_END
