#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QLMMonitorStatus) {
    QLMMonitorStatusUnknown = 0,  // no telemetry yet
    QLMMonitorStatusOn,
    QLMMonitorStatusStandby,
};

// The device class from telemetry. A monitor in standby reports none.
typedef NS_ENUM(NSInteger, QLMMonitorClass) {
    QLMMonitorClassUnknown = 0,
    QLMMonitorClassSubwoofer,
    QLMMonitorClassTwoWay,
};

// A value absent from the last telemetry is -1.
extern const NSInteger QLMMonitorValueAbsent;

// One monitor as System last saw it. Immutable.
@interface QLMMonitorState : NSObject

@property (nonatomic, readonly) NSData *hardwareID;
@property (nonatomic, readonly) uint8_t session;
@property (nonatomic, readonly, nullable) NSString *serialNumber;
@property (nonatomic, readonly, nullable) NSString *systemInfo;
@property (nonatomic, readonly, nullable) NSString *model;            // from systemInfo
@property (nonatomic, readonly, nullable) NSString *firmwareVersion;  // from systemInfo, when it has one
@property (nonatomic, readonly) QLMMonitorStatus status;
@property (nonatomic, readonly) QLMMonitorClass deviceClass;
@property (nonatomic, readonly) NSInteger temperature;  // degrees C
@property (nonatomic, readonly) NSInteger inputMeter;   // raw, see the spec's section 8.1
@property (nonatomic, readonly) NSInteger hfMeter;
@property (nonatomic, readonly) NSInteger lfMeter;
@property (nonatomic, readonly) NSInteger subMeter;
@property (nonatomic, readonly) NSUInteger missedPolls;
@property (nonatomic, readonly, nullable) NSDate *lastReply;
@property (nonatomic, readonly) BOOL muted;  // as System last set it; telemetry does not show mute
// The serial number, the system info, and the power status are known.
@property (nonatomic, readonly) BOOL identified;

@end

// The GLM adapter itself, as System last saw it. Immutable.
@interface QLMAdapterState : NSObject

@property (nonatomic, readonly) NSString *device;  // what the adapter object drives, for display
@property (nonatomic, readonly, nullable) NSString *systemInfo;       // from 01 39
@property (nonatomic, readonly, nullable) NSString *model;            // from systemInfo
@property (nonatomic, readonly, nullable) NSString *firmwareVersion;  // from systemInfo
@property (nonatomic, readonly, nullable) NSString *serialNumber;     // from 01 19 01
// From the last reply to 01 08. hasStatus is NO until one reads.
@property (nonatomic, readonly) BOOL hasStatus;
@property (nonatomic, readonly) BOOL knobPresent;
@property (nonatomic, readonly) BOOL micPresent;
// The knob's position in tenths of a dB: 0 at the top, about -1004 at the
// bottom. Nil without the knob.
@property (nonatomic, readonly, nullable) NSNumber *knobTenths;
@property (nonatomic, readonly) NSUInteger missedPolls;  // since the last reply to 01 08
@property (nonatomic, readonly, nullable) NSDate *lastReply;
// The system info, the serial number, and the status are known.
@property (nonatomic, readonly) BOOL identified;

@end

// The whole system at one moment. Immutable.
@interface QLMSnapshot : NSObject

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) QLMAdapterState *adapter;
// Why nothing reaches the bus: QLMAdapterErrorBusy while another host has
// the adapter, or QLMAdapterErrorDisconnected. Nil once a send goes out.
@property (nonatomic, readonly, nullable) NSError *adapterError;
@property (nonatomic, readonly) NSArray<QLMMonitorState *> *monitors;
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;  // nil until set, undimmed
@property (nonatomic, readonly) BOOL dimmed;
@property (nonatomic, readonly) BOOL applying;
@property (nonatomic, readonly, nullable) NSString *activeGroupName;  // the last group applied in full
// Nothing was queued for the bus or in flight when this was published.
@property (nonatomic, readonly) BOOL idle;
// Each is NO when there are no monitors.
@property (nonatomic, readonly) BOOL allIdentified;
@property (nonatomic, readonly) BOOL allMuted;
@property (nonatomic, readonly) BOOL anyOn;

@end

NS_ASSUME_NONNULL_END
