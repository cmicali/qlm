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
};

// One handler call per send, on the queue given to startOnQueue:clock:.
// `reply` is NULL when no monitor answered, which is not an error. The
// pointer is valid only during the call.
typedef void (^QLMAdapterReplyHandler)(const QLMMessage *_Nullable reply, NSError *_Nullable error);

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

@end

// Packs the message as an output report, through the allowlist. Every adapter
// sends through this, and a refusal comes back as the error to hand over.
BOOL QLMAdapterPackReport(const QLMMessage *message, uint8_t report[_Nonnull QLMReportLength], NSError **error);

// A message as the adapters record it: the address byte, then the payload.
NSData *QLMAdapterRecord(const QLMMessage *message);

NSError *QLMAdapterErrorMake(QLMAdapterError code, NSString *description);

NS_ASSUME_NONNULL_END
