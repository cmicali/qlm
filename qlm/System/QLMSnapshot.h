#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QLMMonitorStatus) {
    QLMMonitorStatusUnknown = 0,  // no telemetry yet
    QLMMonitorStatusOn,
    QLMMonitorStatusStandby,
};

// A value absent from the last telemetry is -1.
extern const NSInteger QLMMonitorValueAbsent;

// One monitor as System last saw it. Immutable.
@interface QLMMonitorState : NSObject

@property (nonatomic, readonly) NSData *hardwareID;
@property (nonatomic, readonly) uint8_t session;
@property (nonatomic, readonly, nullable) NSString *serialNumber;
@property (nonatomic, readonly, nullable) NSString *systemInfo;
@property (nonatomic, readonly) QLMMonitorStatus status;
@property (nonatomic, readonly) NSInteger deviceClass;
@property (nonatomic, readonly) NSInteger temperature;  // degrees C
@property (nonatomic, readonly) NSInteger inputMeter;   // raw, see the spec's section 8.1
@property (nonatomic, readonly) NSInteger hfMeter;
@property (nonatomic, readonly) NSInteger lfMeter;
@property (nonatomic, readonly) NSInteger subMeter;
@property (nonatomic, readonly) NSUInteger missedPolls;
@property (nonatomic, readonly, nullable) NSDate *lastReply;

@end

// The whole system at one moment. Immutable.
@interface QLMSnapshot : NSObject

@property (nonatomic, readonly) NSDate *date;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) NSArray<QLMMonitorState *> *monitors;
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;  // nil until set

@end

NS_ASSUME_NONNULL_END
