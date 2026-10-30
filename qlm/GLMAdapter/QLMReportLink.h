#import <Foundation/Foundation.h>

#import "QLMAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// Writes one output report. Nil on success, or why it failed.
typedef NSError *_Nullable (^QLMReportWriter)(const uint8_t *report);

// The adapter's request and reply rules over raw reports, whatever carries
// them: one request in flight, each reply assembled from input reports and
// handed to the request that expects it, and a timeout. The HID adapter
// drives a device through it, and the tests drive it with a capture.
//
// Every method runs on the queue, and so does the writer. Each handler is
// called once, asynchronously, on the queue.
@interface QLMReportLink : NSObject

- (instancetype)initWithQueue:(dispatch_queue_t)queue writer:(QLMReportWriter)writer NS_DESIGNATED_INITIALIZER;
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
// goes out. The sync waits five timeouts, since its reply queues behind the
// late one. If none comes, the link fails.
@property (nonatomic) NSTimeInterval replyTimeout;

// Called once, on the queue, when the link fails. Every send then fails.
@property (nonatomic, copy, nullable) void (^failureHandler)(NSError *error);

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler;

// One input report, as the device delivered it.
- (void)receiveReport:(const uint8_t *)report length:(size_t)length;

// Fails the request in flight, and every later send, with the error.
- (void)closeWithError:(NSError *)error;

// Input that completed a frame no request was waiting for, or that a sync
// dropped. A reply that comes after its timeout is one of these.
@property (nonatomic, readonly) NSUInteger strayReplies;
@property (nonatomic, readonly) NSUInteger timeouts;

@end

NS_ASSUME_NONNULL_END
