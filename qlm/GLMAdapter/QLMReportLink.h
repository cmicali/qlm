#import <Foundation/Foundation.h>

#import "QLMAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// Writes one output report. Nil on success, or why it failed.
typedef NSError *_Nullable (^QLMReportWriter)(const uint8_t *report);

// The adapter's request and reply rules over raw reports, whatever carries
// them: one request in flight, each reply assembled from input reports and
// handed to the request that expects it, and a timeout. The HID adapter
// drives a device through it, one link for each time the adapter arrives,
// and the tests drive it with a capture.
//
// Each open puts the link out of step. A reply to another host, GLM or an
// earlier process, may still come, of any shape. So the first request waits
// for a sync in two steps: the adapter's system info, then its status poll.
// The first step drops any late reply but a system info. A status is the
// likeliest, since GLM's last request before it quits is a status poll
// (captures/quit-glm, qlm-first-discover). A late system info fools the first
// step, and the second then drops the first's own reply.
// TRAP: two late replies, a system info and then a status, fool both steps.
// GLM keeps one request in flight (captures/startup-idle). An earlier qlm
// leaves more than one only when it quit while it synced: the reply that
// timed out, and up to four syncs' (replyTimeout). It leaves a system info
// and then a status only when its system info timed out.
//
// Every method runs on the queue, and so does the writer. Each handler is
// called once, asynchronously, on the queue.
@interface QLMReportLink : NSObject

// The clock runs the timeouts, and the hop that hands a reply over.
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                        clock:(id<QLMClock>)clock
                       writer:(QLMReportWriter)writer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// 0.1 s. The slowest reply in the captures took 11 ms: the adapter's own
// no-answer frame after a monitor stayed silent.
//
// After a timeout, or a reply that does not read, the reply may still come.
// TRAP: no wait makes that safe. Replies name no request, so a late one
// would answer the next. So the link holds the next request and sends a
// sync: the adapter's status poll, or its system info after a status poll,
// so that the late reply cannot have the sync's shape. It drops every reply
// until one has that shape. The adapter bridges one request at a time, so
// it answers in order, and the late reply is then past. The held request
// goes out. The sync's reply queues behind the late one, so after five
// timeouts the link stalls: it fails the held request, and every send, with
// QLMAdapterErrorUnresponsive, until a sync's reply comes. In case the reply
// was lost, it sends up to three more syncs of that shape. Each waits twice
// as long as the one before, so the four wait 0.5, 1, 2, and 4 s at 0.1 s.
// A reply may then be an earlier sync's, so one sync of the other shape
// drops the rest. After the last, the link waits on for a reply, and sends
// nothing. The retries add no shape that may be late, so a close and a
// reopen keep track whenever they did before the stall.
@property (nonatomic) NSTimeInterval replyTimeout;

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler;

// One input report, as the device delivered it.
- (void)receiveReport:(const uint8_t *)report length:(size_t)length;

// The device closed. Fails the request in flight, and every send until a
// reopen, with the error. The request's reply may come after the reopen, so
// the open's sync starts with a shape that reply cannot have. When both
// syncs' shapes may be late, no sync is left, and the link has lost track. A
// close during an open's sync is one such: the other host's reply, ahead of
// the sync's, may have either shape.
- (void)closeWithError:(NSError *)error;

// The device opened again, and the link is out of step, as at its first open.
// A link that lost track stays closed.
- (void)reopen;

// Why the link lost track, QLMAdapterErrorLostTrack, or nil. It never
// reopens. Only a new arrival of the adapter, a new USB enumeration, gets a
// new link.
@property (nonatomic, readonly, nullable) NSError *failure;

// Input that completed a frame no request was waiting for, or that a sync
// dropped. A reply that comes after its timeout is one of these.
@property (nonatomic, readonly) NSUInteger strayReplies;
@property (nonatomic, readonly) NSUInteger timeouts;

@end

NS_ASSUME_NONNULL_END
