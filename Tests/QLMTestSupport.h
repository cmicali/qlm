#ifndef QLMTESTSUPPORT_H
#define QLMTESTSUPPORT_H

#import <XCTest/XCTest.h>

#include <string.h>

#import "QLMAdapter.h"
#import "QLMCapture.h"
#import "QLMClock.h"
#include "QLMFrame.h"
#import "QLMSetup.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// Asserts that `actual` holds exactly the listed bytes.
#define QLMAssertBytes(actual, actualLength, ...)                                           \
    do {                                                                                   \
        const uint8_t expected_[] = {__VA_ARGS__};                                         \
        XCTAssertEqual((size_t)(actualLength), sizeof expected_);                           \
        if ((size_t)(actualLength) == sizeof expected_) {                                  \
            XCTAssertEqual(memcmp((actual), expected_, sizeof expected_), 0);              \
        }                                                                                  \
    } while (0)

// Builds a QLMMessage from an address and payload bytes.
#define QLMMakeMessage(addr, ...)                                                          \
    ({                                                                                     \
        const uint8_t payload_[] = {__VA_ARGS__};                                          \
        QLMMessageMake((addr), payload_, sizeof payload_);                                 \
    })

NSData *QLMBytes(const uint8_t *bytes, size_t length);

// A hand-back as System would give it.
QLMHandBack *QLMMakeHandBack(QLMHandBackKind kind, NSNumber *_Nullable knob, NSNumber *_Nullable volume);

// The output report a message packs into, 64 bytes.
NSData *QLMReportFor(QLMMessage message);

// A frame as the bus carries it, with no allowlist: the CRC over the address
// and payload, then 7E and 7D escaped, then the flag (docs/protocol.md,
// Framing). For frames qlm never encodes: replies, and GLM's refused frames.
NSData *QLMUncheckedFrame(QLMMessage message);

// A path from the repository's root.
NSString *QLMRepositoryPath(NSString *relative);

// A file in Tests/Setups/Fixtures/.
NSString *QLMFixturePath(NSString *name);

// Fixtures/Main.sam, parsed once and shared. Never change it.
QLMSetup *QLMReadFixtureSetup(void);

// The fixture's group with this name.
QLMSetupGroup *_Nullable QLMFixtureGroup(NSString *name);

// Picks out a group apply from frames as they went out, as the address
// byte, then the payload. Feed it every frame in order: it drops GLM's or
// System's cycle beside the apply, which is the adapter's polls, the probes,
// the leases, the polls, the volume after a probe, and a monitor's 39 and
// 19 01 before its block.
@interface QLMApplyFilter : NSObject
- (BOOL)keeps:(NSData *)record;
@end

// Every directory under captures/ with a reports.txt, sorted.
NSArray<NSString *> *QLMCaptureScenarios(void);

// captures/<scenario>/reports.txt, read once and shared.
QLMCapture *_Nullable QLMReadCapture(NSString *scenario, NSError **error);

// A frame that controls the monitors: none of a poll, a serial, system info,
// the probe, or a lease.
BOOL QLMIsControl(QLMMessage message);

// A lease: 02, a hardware ID, and a session, to the multicast address.
BOOL QLMIsLease(QLMMessage message);

// A poll of a monitor: 08 to a session.
BOOL QLMIsMonitorPoll(QLMMessage message);

// A volume frame's 24-bit word.
uint32_t QLMVolumeWordOf(QLMMessage message);

// Each output report in captures/<scenario> whose payload starts with `opcode`.
NSSet<NSData *> *QLMOutputReports(NSString *scenario, uint8_t opcode);

@interface XCTestCase (QLMCaptureRun)

// `count` frames of captures/<scenario>, from the one at `time` to the half
// millisecond, each one `keep` passes, or every one when it is NULL. Nil,
// after a failure, when there are fewer.
- (nullable NSArray<QLMCaptureExchange *> *)qlm_frames:(NSUInteger)count
                                                     of:(NSString *)scenario
                                                   from:(NSTimeInterval)time
                                                   keep:(BOOL (*_Nullable)(QLMMessage))keep;
// The same, keeping QLMIsControl's frames.
- (nullable NSArray<QLMCaptureExchange *> *)qlm_controls:(NSUInteger)count of:(NSString *)scenario from:(NSTimeInterval)time;
// The exchange's output report is `message`'s, as qlm packs it.
- (void)qlm_assertExchange:(QLMCaptureExchange *)exchange is:(QLMMessage)message;
- (void)qlm_assertExchange:(QLMCaptureExchange *)exchange isExchange:(QLMCaptureExchange *)other;
// A lease the monitor acked, then `level` within `seconds` of it.
- (void)qlm_assertLease:(QLMCaptureExchange *)lease
              thenLevel:(QLMCaptureExchange *)next
                     is:(QLMMessage)level
                 within:(NSTimeInterval)seconds;

@end

@class QLMReportLink;

// The GLM adapter as a capture saw it, at the level of reports, behind a
// QLMReportLink as the HID adapter is. Each output report the link writes
// gets the input reports that answered it in the capture, split as the
// adapter sent them, after replyDelay. Once the capture's replies to a report
// run out, it gets the last again: a link's syncs add adapter queries. Replies
// come in order, as the adapter's do: none before the one ahead of it. A
// report the capture never sent, or any report while silent, gets none.
@interface QLMCaptureDevice : NSObject <QLMAdapter>

- (instancetype)initWithCapture:(QLMCapture *)capture;

@property (nonatomic, readonly, nullable) QLMReportLink *link;  // made by startOnQueue:clock:
@property (atomic) NSTimeInterval replyDelay;                   // 1 ms
@property (atomic) NSTimeInterval nextReplyDelay;               // above 0: the next reply's delay, once
@property (atomic) BOOL silent;
@property (atomic) NSUInteger dropReplies;  // the next N replies never come
// Every output report written, as 64 bytes. Read on the queue.
@property (nonatomic, readonly) NSArray<NSData *> *writtenReports;
@property (nonatomic, readonly) NSUInteger unmatchedReports;  // reports the capture never sent
@property (nonatomic, readonly) NSUInteger deliveredReplies;  // read on the queue

// A frame as the adapter delivers it: one input report per 63 bytes, each
// starting with 3F and padded with zeros.
+ (NSArray<NSData *> *)inputReportsForFrame:(NSData *)frame;

@end

// A clock that moves only when a test advances it, or while a caller waits
// on it: a wait runs each timer due, one at a time, until its semaphore is
// signalled or its time runs out. A hop waits until the clock settles,
// advances, or waits, so the caller's own steps take no time, and a reply
// never beats the caller's next step. Every hop and timer it runs joins one
// dispatch group, so it can wait until the work a timer starts is done.
// Time and order then depend on the test alone, never on the host.
@interface QLMVirtualClock : NSObject <QLMClock>

// Runs the hops waiting, and the work they start, with time still. A hop to
// the main queue runs in place when the main thread settles. Raises if the
// work is not done within a generous deadline, which only a hang would reach.
- (void)settle;
// Settles, then runs each timer due within `seconds`, one at a time, until
// the condition holds. Timers run in order of time, the earlier first when
// two are due together, with now at each one's time, and each one's work
// settles before the condition is checked again. When the condition never
// holds, now ends `seconds` on, and this returns NO.
- (BOOL)runUntil:(BOOL (^)(void))condition within:(NSTimeInterval)seconds;
// Runs every timer due within `seconds`, as runUntil:within: does. Now ends
// `seconds` on.
- (void)advanceBy:(NSTimeInterval)seconds;
// Moves now on by `seconds` with no timer run, as when the queues stall.
// Then each timer that came due runs once, in order, as GCD runs a missed
// timer once when its queue frees up. A repeating one keeps its beat.
- (void)stallFor:(NSTimeInterval)seconds;

@end

@interface XCTestCase (QLMAdapter)

// Sends on the adapter's queue, then moves the clock one timer at a time
// until the handler comes, so the test's next step comes at that moment.
// Fails the test if it never comes. Returns whether a monitor answered.
- (BOOL)qlm_send:(QLMMessage)message
              to:(id<QLMAdapter>)adapter
           queue:(dispatch_queue_t)queue
           clock:(QLMVirtualClock *)clock
           reply:(nullable QLMMessage *)reply
           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif
