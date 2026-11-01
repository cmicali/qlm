#import <Foundation/Foundation.h>

#import "QLMAdapter.h"
#import "QLMClock.h"
#import "QLMSetup.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QLMSystemErrorDomain;

// Why System refused or failed a group apply. A refusal sends nothing.
typedef NS_ERROR_ENUM(QLMSystemErrorDomain, QLMSystemError) {
    QLMSystemErrorUnverifiedRate = 1,  // a node's filter design rate is unverified on the wire
    QLMSystemErrorUnknownMonitor,      // a node matches no leased monitor
    QLMSystemErrorBlocksFailed,        // the DSP blocks could not be built; see NSUnderlyingErrorKey
    QLMSystemErrorAlreadyApplying,
    QLMSystemErrorNotRunning,          // also given to an apply cut short by stop
    QLMSystemErrorNoVolume,            // no volume is set, so the restore has nothing to send
    QLMSystemErrorSendFailed,          // a frame failed or a monitor did not ack it
    QLMSystemErrorKnobUnread,          // the level waits for the knob's first reading
};

@interface QLMSystemSettings : NSObject <NSCopying>

// The user's ceiling. Every volume frame is capped at it. The default is low.
@property (nonatomic) double ceilingDecibels;           // -30, qlmctl's highest without --allow-high-ceiling
@property (nonatomic) NSTimeInterval cycleInterval;     // 0.57 s: probe, volume, a poll to each monitor
@property (nonatomic) NSTimeInterval volumeInterval;    // 0.05 s: at most one volume frame per interval
@property (nonatomic) NSUInteger missedPollsLimit;      // 4 polls unanswered, then the retry burst
@property (nonatomic) NSUInteger retryBurst;            // 4 polls to the dead address before re-discovery
// TRAP: polled less often than GLM polls it, the adapter may take over
// while System runs, at the knob's level, which the ceiling does not bound.
// Only qlmctl's --adapter-poll polls less, with the knob at or below the
// volume, for docs/experiments.md's Part B.
// 0.107 s: a round of 01 08 to the adapter, as GLM polls it. 0 polls it
// only at start.
@property (nonatomic) NSTimeInterval adapterPollInterval;
// 2: GLM's round is a pair, 2.4 ms apart (docs/adapter-status.md).
@property (nonatomic) NSUInteger adapterPollsPerRound;
// YES: the cycle probes, leases, and polls monitors. NO talks to the adapter
// alone, and sends the volume only once one is set.
@property (nonatomic) BOOL discoversMonitors;
// The mute record to start from, as a snapshot gave it: the muted hardware
// IDs, whether mute all is on, and the monitors the user lifted it from. No
// reply reports a monitor's mute, so System's record is the truth, and its
// rounds restate it.
@property (nonatomic, copy) NSSet<NSData *> *mutedHardwareIDs;   // empty
@property (nonatomic) BOOL mutingAll;                            // NO
@property (nonatomic, copy) NSSet<NSData *> *liftedHardwareIDs;  // empty
// The leases to check at start, as a snapshot gave them. A monitor still
// holds its lease for 23 s or more after a host goes quiet, and never
// answers a probe meanwhile. So at start System asks each session for its
// serial, takes back each monitor whose own serial answers, and leases
// nothing to a session another monitor answers.
@property (nonatomic, copy) NSArray<QLMKnownLease *> *knownLeases;  // empty
// The knob's last reading of the last run, as a snapshot's adapter gave
// it. knobRead is NO when none was read. Then knobTenths is the position in
// tenths of a dB, or nil with no knob in. A start compares the knob's first
// reading with it.
@property (nonatomic) BOOL knobRead;                         // NO
@property (nonatomic, copy, nullable) NSNumber *knobTenths;  // nil
// TRAP: AGENTS.md's Safety rule refuses a group apply for any model whose
// filter design rate is unverified, such as the 8351B. Only qlmctl's
// supervised test sets this, behind --unverified-rate. The app never does.
@property (nonatomic) BOOL allowsUnverifiedRates;  // NO
// Every timer and hop of System and its adapter goes through it, and so do
// qlmctl's waits. Tests give a virtual clock.
@property (nonatomic) id<QLMClock> clock;  // QLMRealClock.shared

@end

typedef void (^QLMSnapshotHandler)(QLMSnapshot *snapshot);

// Owns the bus on one serial queue. It reads the adapter's identity and polls
// its status. It runs discovery, the session leases, the poll cycle, and
// volume. After a change it publishes an immutable snapshot once nothing is
// queued for the bus, in flight, or held by the volume's coalescing timer.
// Every method may be called from any thread.
// Each command returns its call's number. Once the call has run on System's
// queue, a snapshot that carries it follows, with its frames out, queued,
// failed, or dropped by a stop (QLMSnapshot's lastCall).
// While the bus is refused or gone, no frame goes to a session. Once it comes
// back, System drops every monitor, and takes each back only where its own
// serial answers at the session it last held.
// When the adapter's link gives up, System reopens the adapter, and the link
// syncs again. It waits 1 s before the first reopen, then twice as long
// before each next one, up to 30 s, until a send goes out, the adapter is
// gone or refused, or a stop. A reopen that fails is tried again after the
// next wait. A link whose syncs the adapter did not take is never reopened.
@interface QLMSystem : NSObject

- (instancetype)initWithAdapter:(id<QLMAdapter>)adapter settings:(QLMSystemSettings *)settings;

@property (atomic, readonly) QLMSystemSettings *settings;  // replaced whole when the ceiling changes
@property (atomic, readonly) QLMSnapshot *snapshot;  // the latest

// The handler gets the latest snapshot at once, then every one published.
- (void)setSnapshotHandler:(nullable QLMSnapshotHandler)handler queue:(dispatch_queue_t)queue;

// The snapshot System would publish now. The latest one may lag, since
// System publishes only once it is idle.
// Decide from this one what must not miss a change, such as whether a stop
// makes the monitors louder. Nil when System's queue is still busy after
// `seconds`: it waits up to 5 s on each report an adapter does not take.
// Never from System's queue.
- (nullable QLMSnapshot *)snapshotNowWithin:(NSTimeInterval)seconds;

// While no host ran, the adapter ran the monitors at the knob's level. So
// a volume set before the start, or kept from the last run, waits for the
// knob's first reading, and no level goes out meanwhile. When the knob
// moved since the last reading of the last run, or the settings', by GLM's
// rule (QLMKnobMoved), or went in, that turn is the listener's last choice.
// Then the volume falls to the knob's, when that is lower, and the
// snapshot's startLoweredFromDecibels says so. With the knob unmoved, no
// last reading, or no knob in now, the volume goes out as set. So does one
// set after the start. The same holds after a gap in the bus, from the
// last reading before it.
- (QLMCallNumber)start;
// Before it lets go, sends the knob's level when the knob is at or below the
// level System sends, so the adapter's take-over changes nothing. The
// snapshot's handBack says what it did. A start while that goes out runs
// once the stop is done.
- (QLMCallNumber)stop;
// The same. The completion runs on the main queue once System has let go of
// the adapter, or at once when it is not running.
- (QLMCallNumber)stopWithCompletion:(nullable dispatch_block_t)completion;
// The same, for a stop no one can answer. Where the take-over would be
// louder, or is unknown, it sends mute all before it lets go. A mute
// outlasts the host, so the take-over can't make the monitors louder. A
// snapshot that still runs carries mute all in the record before the stop
// ends, so a keeper of the record, as the app is, starts the next System
// muted. This System's own next start lifts that mute all, back to the
// record before the stop, as the Mac's wake needs. The lift waits for the
// knob's read and the first cycle's level frame, which follows the leases'
// own levels. A change to the mutes before then keeps the user's.
- (QLMCallNumber)stopMutingIfLouderWithCompletion:(nullable dispatch_block_t)completion;

// Goes out at once, coalesced to one frame per volumeInterval, again every
// cycle, and ahead of everything else when a monitor is leased. Held at the
// ceiling, and clamped to it in the builder too. Once one is set, a turn of
// the adapter's knob sets it too, as GLM lets it (QLMKnob), under the
// ceiling. A turn that leaves it where it was sends nothing. At start the
// knob sets nothing.
- (QLMCallNumber)setVolumeDecibels:(double)decibels;

// Caps every volume frame that goes out after this, those already in line
// too. A volume above the new ceiling falls to it, and stays there if the
// ceiling rises again. A volume already set goes out again.
- (QLMCallNumber)setCeilingDecibels:(double)ceilingDecibels;

// While dimmed, every volume frame is the volume less QLMDimDecibels. A
// change sends GLM's dim sequence, or nothing while no volume is set.
- (QLMCallNumber)setDimmed:(BOOL)dimmed;

// Each sends two rounds of 2B, restating the state of every monitor that is
// on: its mute in the active group, and GLM's 05 and 07 outside it. Mute all
// also re-sends the volume and sets the adapter's own mute, as GLM does. A
// lift of one mute under mute all lifts the adapter's own mute too, as
// GLM's unmute all does, but mute all holds for every other monitor. A mute
// of the last one lifted brings it back, as GLM's mute all. A
// mute holds by hardware ID until the user lifts it, across a lease that
// lapses, a stop and a start, and for a monitor that first appears while all
// are muted. A muted monitor leased again, or one that was not on, hears its
// state after its next poll that says on. So does one whose 2B did not go
// out, or whose round a stop dropped, by the next start's poll. No 2B System
// sends unmutes a muted monitor.
- (QLMCallNumber)setMuted:(BOOL)muted forMonitorWithHardwareID:(NSData *)hardwareID;
- (QLMCallNumber)setAllMuted:(BOOL)muted;
// Adds to the record monitors already muted elsewhere, as in GLM, and sends
// nothing. The next rounds restate them as muted.
- (QLMCallNumber)recordMutedHardwareIDs:(NSSet<NSData *> *)hardwareIDs;

// Broadcasts the power sequences, with GLM's spacing between the steps.
// Nothing else goes out between them. The wake ends with a level, as GLM's
// does: the volume once one is set, else the knob's position under the
// ceiling, else the bottom level. The monitors' power state comes back in
// their telemetry.
- (QLMCallNumber)sleep;
- (QLMCallNumber)wake;

// The first apply sends what GLM sends at launch: each leased monitor's
// block in turn, off nodes included. Each one after is GLM's group switch:
// the duck, the wake, the routing pass, the blocks of the nodes that are
// on, the mute state, and the restore. QLMApplySequence has both. The group
// stays active, across stop: a monitor leased later gets its block once the
// probe finds no more, as GLM's do at a wake. Refused, with nothing sent,
// for a node with a leased monitor whose block fails or whose design rate
// is unverified, for a node that is on with no leased monitor, and while no
// volume is set. The completion runs on the main queue.
- (QLMCallNumber)applyGroup:(QLMSetupGroup *)group completion:(void (^)(NSError *_Nullable error))completion;
// GLM's group switch, even as the first apply. The rest is as applyGroup:.
- (QLMCallNumber)switchToGroup:(QLMSetupGroup *)group completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
