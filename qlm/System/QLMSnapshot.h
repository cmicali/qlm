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
// Polls in a row that went out and got no reply. A poll that never went
// out, while the bus was refused or gone, does not count.
@property (nonatomic, readonly) NSUInteger missedPolls;
// System's rule for presence: missedPollsLimit polls in a row missed. System
// then polls a burst, and drops the monitor if every poll goes out and none
// is answered.
@property (nonatomic, readonly) BOOL offline;
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
@property (nonatomic, readonly) NSUInteger missedPolls;  // that went out, since the last reply to 01 08
@property (nonatomic, readonly, nullable) NSDate *lastReply;
// The system info, the serial number, and the status are known.
@property (nonatomic, readonly) BOOL identified;

@end

// Why nothing reaches the bus.
typedef NS_ENUM(NSInteger, QLMBusProblem) {
    QLMBusProblemNone = 0,
    QLMBusProblemNoAdapter,  // no GLM adapter is connected
    QLMBusProblemGLM,        // GLM holds the adapter: quit it first
    QLMBusProblemOtherHost,  // another process holds the adapter, or qlm could not seize it
};

// What the adapter's take-over does to the level. About 2.6 s after the
// host goes quiet, the adapter applies the knob's position
// (captures/qlm-control-first/notes.md).
typedef NS_ENUM(NSInteger, QLMHandBackKind) {
    // No knob, or no volume set, so the level at the take-over is unknown.
    QLMHandBackUnknown = 0,
    // The knob is at or below the level System sends. System sends the
    // knob's level just before it lets go, so the take-over changes nothing.
    QLMHandBackKnobLevel,
    // The knob is above the level System sends, so the take-over makes it
    // louder. System sends nothing extra.
    QLMHandBackLouder,
};

// Immutable.
@interface QLMHandBack : NSObject
@property (nonatomic, readonly) QLMHandBackKind kind;
@property (nonatomic, readonly, nullable) NSNumber *knobDecibels;  // nil with no knob
// The level System sends, dimmed and under the ceiling. Nil with none set.
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;
@end

// The whole system at one moment. Immutable.
@interface QLMSnapshot : NSObject

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) QLMAdapterState *adapter;
// Why nothing reaches the bus: QLMAdapterErrorBusy while another host has
// the adapter, or QLMAdapterErrorDisconnected. Nil once a send goes out.
@property (nonatomic, readonly, nullable) NSError *adapterError;
// The same, typed, so the app need not read GLMAdapter's error codes.
@property (nonatomic, readonly) QLMBusProblem busProblem;
@property (nonatomic, readonly) NSArray<QLMMonitorState *> *monitors;
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;  // nil until set, undimmed
@property (nonatomic, readonly) double ceilingDecibels;            // every volume frame is capped at it
@property (nonatomic, readonly) BOOL dimmed;
@property (nonatomic, readonly) BOOL applying;
@property (nonatomic, readonly, nullable) NSString *activeGroupName;  // the last group applied in full
// Nothing was queued for the bus or in flight when this was published.
@property (nonatomic, readonly) BOOL idle;
// While System runs, what a stop would do to the level now. Once it has
// stopped, what it did.
@property (nonatomic, readonly) QLMHandBack *handBack;
// System's mute record: every muted hardware ID, leased or not, and whether
// mute all is on. Give both back through QLMSystemSettings to start from it.
@property (nonatomic, readonly) NSSet<NSData *> *mutedHardwareIDs;
@property (nonatomic, readonly) BOOL mutingAll;
// Each is NO when there are no monitors.
@property (nonatomic, readonly) BOOL allIdentified;
@property (nonatomic, readonly) BOOL allMuted;
@property (nonatomic, readonly) BOOL anyOn;

@end

NS_ASSUME_NONNULL_END
