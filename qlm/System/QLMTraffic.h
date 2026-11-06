#import <Foundation/Foundation.h>

#import "QLMAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// One frame between qlm and the adapter, as the adapter's tap saw it.
// Immutable.
@interface QLMTrafficEntry : NSObject

@property (nonatomic, readonly) uint64_t number;  // from 1, in order, per System
@property (nonatomic, readonly) NSDate *date;
@property (nonatomic, readonly) QLMTrafficKind kind;
// A request, a sync, or one not taken: host to adapter.
@property (nonatomic, readonly) BOOL outgoing;
// The address, then the payload. Empty for a timeout or an unreadable frame.
@property (nonatomic, readonly) NSData *bytes;
// The request or sync a reply, a no-answer, a timeout, or an unreadable
// reply ends, and its bytes. 0 and nil for the rest.
@property (nonatomic, readonly) uint64_t answers;
@property (nonatomic, readonly, nullable) NSData *request;
// The monitor the frame names, or the one its request named: the one that
// held the session then, or the one a lease names. Nil for the rest.
@property (nonatomic, readonly, nullable) NSData *hardwareID;
// The ceiling as the frame went out, or as its request did.
@property (nonatomic, readonly) double ceilingDecibels;

- (instancetype)initWithNumber:(uint64_t)number
                          date:(NSDate *)date
                          kind:(QLMTrafficKind)kind
                         bytes:(NSData *)bytes
                       answers:(uint64_t)answers
                       request:(nullable NSData *)request
                    hardwareID:(nullable NSData *)hardwareID
               ceilingDecibels:(double)ceilingDecibels NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The frame as a message, or the request's. Empty when there is none.
@property (nonatomic, readonly) QLMMessage message;
@property (nonatomic, readonly) QLMMessage requestMessage;

@end

// The last frames, in a fixed ring of plain values, so recording costs a
// copy and no allocation. Entries are made only when asked for. Not thread
// safe: System uses it on its queue.
@interface QLMTrafficRecorder : NSObject

- (instancetype)initWithCapacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// `hardwareID`, 3 bytes, is the monitor an outgoing frame names. A reply
// takes its request's. A request or sync that expects a reply stays in
// flight until a reply, a no-answer, or an unreadable reply ends it, or the
// next one, or one not taken. A timeout names it and leaves it in flight:
// a sync's wait goes on past it, and a request's late reply comes as a
// stray.
- (void)record:(QLMTrafficKind)kind
       message:(const QLMMessage *_Nullable)message
    hardwareID:(const uint8_t *_Nullable)hardwareID
       ceiling:(double)ceilingDecibels;

@property (nonatomic, readonly) uint64_t lastNumber;  // 0 before the first
// Every entry still kept with a number above `number`, in order.
- (NSArray<QLMTrafficEntry *> *)entriesAfter:(uint64_t)number;

@end

NS_ASSUME_NONNULL_END
