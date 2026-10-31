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

// Each call to one of System's commands takes the next number, from 1, in
// the order the calls run on System's queue.
typedef uint64_t QLMCallNumber;

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
// The mic's two readings, DE and DD, as raw counts. Nil without the mic,
// or when the reply lacks the reading. Like the knob, they stay at the last
// status read while missedPolls is above 0.
// Their meaning is unconfirmed: docs/adapter-status.md has the guesses. They
// refresh once a cycle.
@property (nonatomic, readonly, nullable) NSNumber *micDE;
@property (nonatomic, readonly, nullable) NSNumber *micDD;
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
    QLMBusProblemNoAdapter,  // no GLM adapter is connected, or adapterProblem says why it is no use
    QLMBusProblemGLM,        // GLM holds the adapter: quit it first
    QLMBusProblemOtherHost,  // another process holds the adapter, or qlm could not seize it
};

// Why qlm holds the adapter, but nothing reaches the bus. The adapter takes
// over at the knob's level about 2.6 s after the last report it took, so
// warn with the snapshot's handBack, which keeps the last knob reading.
typedef NS_ENUM(NSInteger, QLMAdapterProblem) {
    QLMAdapterProblemNone = 0,
    // It stopped answering. qlm syncs a few times over about 7 s, then waits
    // for a reply, and resumes once one comes.
    QLMAdapterProblemUnresponsive,
    // qlm lost track of its replies, and sends nothing until a replug.
    QLMAdapterProblemLostTrack,
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

// The session an identified monitor last held, as System knew it. Immutable.
@interface QLMKnownLease : NSObject
- (instancetype)initWithHardwareID:(NSData *)hardwareID serialNumber:(NSString *)serialNumber session:(uint8_t)session;
@property (nonatomic, readonly) NSData *hardwareID;
@property (nonatomic, readonly) NSString *serialNumber;  // from 19 01
@property (nonatomic, readonly) uint8_t session;
@end

// Immutable.
@interface QLMHandBack : NSObject
@property (nonatomic, readonly) QLMHandBackKind kind;
@property (nonatomic, readonly, nullable) NSNumber *knobDecibels;  // nil with no knob
// The level System sends, dimmed and under the ceiling. Nil with none set.
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;
@end

// The whole system at one moment. Immutable.
@interface QLMSnapshot : NSObject

// The last call that ran on System's queue before this snapshot was made,
// or 0 before any. Its frames are out or still queued, a volume held by the
// coalescing timer among them. In an idle snapshot none is left to go out:
// each went out, failed, or was dropped by a stop.
@property (nonatomic, readonly) QLMCallNumber lastCall;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) QLMAdapterState *adapter;
// Why nothing reaches the bus: QLMAdapterErrorBusy while another host has
// the adapter, QLMAdapterErrorDisconnected, QLMAdapterErrorUnresponsive, or
// QLMAdapterErrorLostTrack. Nil once a send goes out.
@property (nonatomic, readonly, nullable) NSError *adapterError;
// The same, typed, so the app need not read GLMAdapter's error codes.
@property (nonatomic, readonly) QLMBusProblem busProblem;
// Set only while busProblem is NoAdapter. Read it first.
@property (nonatomic, readonly) QLMAdapterProblem adapterProblem;
@property (nonatomic, readonly) NSArray<QLMMonitorState *> *monitors;
@property (nonatomic, readonly, nullable) NSNumber *volumeDecibels;  // nil until set, undimmed, at most the ceiling
@property (nonatomic, readonly) double ceilingDecibels;            // every volume frame is capped at it
@property (nonatomic, readonly) BOOL dimmed;
@property (nonatomic, readonly) BOOL applying;
@property (nonatomic, readonly, nullable) NSString *activeGroupName;  // the last group applied in full
// A wake went out with no group active, so the monitors that woke play on
// their stored settings. It ends when a group applies, or when GLM holds
// the adapter, since GLM's launch applies its group. Kept across a stop.
@property (nonatomic, readonly) BOOL wokeWithoutGroup;
// Nothing was queued for the bus, in flight, or, while System runs, held by
// the volume's coalescing timer when this was made.
@property (nonatomic, readonly) BOOL idle;
// While System runs, what a stop would do to the level now. Once it has
// stopped, what it did.
@property (nonatomic, readonly) QLMHandBack *handBack;
// System's mute record: every muted hardware ID, leased or not, whether
// mute all is on, and the monitors the user lifted it from. Mute all holds
// for every other monitor, one that appears later included. Give all three
// back through QLMSystemSettings to start from it.
@property (nonatomic, readonly) NSSet<NSData *> *mutedHardwareIDs;
@property (nonatomic, readonly) BOOL mutingAll;
@property (nonatomic, readonly) NSSet<NSData *> *liftedHardwareIDs;
// The session each monitor System identified last held, in session order,
// kept across a stop. Give them back through QLMSystemSettings, so a new
// System checks them before it leases anything.
@property (nonatomic, readonly) NSArray<QLMKnownLease *> *knownLeases;
// Each is NO when there are no monitors.
@property (nonatomic, readonly) BOOL allIdentified;
@property (nonatomic, readonly) BOOL allMuted;
@property (nonatomic, readonly) BOOL anyOn;

@end

NS_ASSUME_NONNULL_END
