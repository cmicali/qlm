#import <Foundation/Foundation.h>

#import "QLMClock.h"
#include "QLMFrame.h"
#include "QLMReport.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QLMAdapterErrorDomain;

typedef NS_ERROR_ENUM(QLMAdapterErrorDomain, QLMAdapterError) {
    QLMAdapterErrorForbidden = 1, // the allowlist refused the message
    QLMAdapterErrorTooLong,       // the frame does not fit one output report
    QLMAdapterErrorDisconnected,  // no adapter
    QLMAdapterErrorTimeout,       // the adapter never answered
    QLMAdapterErrorCapture,       // a capture does not read; the description names the line
    QLMAdapterErrorBusy,          // another host has the adapter, or qlm could not seize it; the description says which, and nothing was sent
    QLMAdapterErrorBadReply,      // the reply did not read
    QLMAdapterErrorUnresponsive,  // the adapter stopped answering, so the link sends nothing but its syncs; nothing was sent
    QLMAdapterErrorLostTrack,     // the link lost track of the adapter's replies, and stays closed until a replug; nothing was sent
    QLMAdapterErrorNotTaken,      // the adapter did not take the report in time, so nothing went out
    QLMAdapterErrorGaveUp,        // the link's syncs all went unanswered, so it sends nothing until a reply or a reconnect; nothing was sent
    QLMAdapterErrorStoppedTaking, // the same, but the adapter did not take some of those syncs, so a reconnect would block for seconds; nothing was sent
};

// What a reconnect did.
typedef NS_ENUM(NSInteger, QLMReconnectResult) {
    QLMReconnectNotNeeded = 0,  // the link has not given up: it synced, or it closed
    QLMReconnectReopened,       // the device opened again, and the link syncs anew
    QLMReconnectFailed,         // the device would not open; the link stays given up, for the next try
};

// One handler call per send, on the queue given to startOnQueue:clock:.
// `reply` is NULL when no monitor answered, which is not an error. The
// pointer is valid only during the call.
typedef void (^QLMAdapterReplyHandler)(const QLMMessage *_Nullable reply, NSError *_Nullable error);

// The message as it goes out, from the message as it was handed over. Run on
// the queue just before its report is written.
typedef QLMMessage (^QLMAdapterRewrite)(QLMMessage message);

// What the traffic tap sees on the adapter's send and receive path.
typedef NS_ENUM(NSInteger, QLMTrafficKind) {
    QLMTrafficRequest = 0,  // a request written, as it went out
    QLMTrafficSync,         // a sync the report link wrote itself
    QLMTrafficNotTaken,     // a request or sync whose write failed, so it may not have gone out
    QLMTrafficReply,        // the reply to the request or sync in flight
    QLMTrafficNoAnswer,     // the adapter's 01 7E for it
    QLMTrafficStray,        // a reply no request waited for, or one a sync dropped; no message if it did not read
    QLMTrafficUnreadable,   // the reply waited for did not read; no message
    QLMTrafficTimeout,      // the reply did not come in time; no message. A sync's wait may go on.
};

// Host to adapter: a request, a sync, or one not taken.
static inline BOOL QLMTrafficKindIsOutgoing(QLMTrafficKind kind) {
    return kind == QLMTrafficRequest || kind == QLMTrafficSync || kind == QLMTrafficNotTaken;
}

// One call per frame, on the adapter's queue, as it goes out or comes in.
// The message is valid only during the call.
typedef void (^QLMTrafficTap)(QLMTrafficKind kind, const QLMMessage *_Nullable message);

// What System drives: the GLM network adapter over HID, a replay of a capture,
// or a fake bus. The bus is half-duplex, so a caller sends one message and
// waits for its handler before sending the next.
@protocol QLMAdapter <NSObject>

// Every timer and hop the adapter makes goes through the clock, System's.
- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock;
- (void)stop;
- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler;

// What this adapter drives, for display. Read on the queue.
@property (nonatomic, readonly) NSString *deviceDescription;

@optional
// The same, but `rewrite`, when given, gives the message that goes out, as
// its report is written. The rewrite may change only the values, and the
// allowlist checks it again. TRAP: an adapter that may hold a message before
// it writes it, as a report link does behind its syncs, must take this.
- (void)sendMessage:(QLMMessage)message
            rewrite:(nullable QLMAdapterRewrite)rewrite
       replyHandler:(QLMAdapterReplyHandler)handler;

// After QLMAdapterErrorGaveUp: closes the device, opens it again, and syncs
// anew. A device gone, or another host, closes the link, and sends then fail
// with why, as with no adapter.
- (QLMReconnectResult)reconnect;

// Taps every frame it sends and receives, for display only. Set before
// start, or on the queue. Nil, the default, costs nothing.
- (void)setTrafficTap:(nullable QLMTrafficTap)tap;

@end

// Packs the message as an output report, through the allowlist. Every adapter
// sends through this, and a refusal comes back as the error to hand over.
BOOL QLMAdapterPackReport(const QLMMessage *message, uint8_t report[_Nonnull QLMReportLength], NSError **error);

// A message as the adapters record it: the address byte, then the payload.
NSData *QLMAdapterRecord(const QLMMessage *message);
// The message a record holds. Empty for an empty record.
QLMMessage QLMAdapterRecordMessage(NSData *_Nullable record);

// Taps a request and its reply, for an adapter with no report link. A
// request that expects a reply and got none got the adapter's 01 7E.
void QLMTapExchange(QLMTrafficTap tap, const QLMMessage *request, const QLMMessage *_Nullable reply);

NSError *QLMAdapterErrorMake(QLMAdapterError code, NSString *description);

NS_ASSUME_NONNULL_END
