#import <Foundation/Foundation.h>

#import "QLMAdapter.h"
#import "QLMCapture.h"

NS_ASSUME_NONNULL_BEGIN

// Plays a capture back as the adapter. Each message is packed as an output
// report, so the allowlist applies, and matched byte for byte against the
// first exchange in the capture with the same report that has not played
// yet. The reply is that exchange's. A message the capture never sent gets no
// reply, as a session no monitor holds would.
@interface QLMReplayAdapter : NSObject <QLMAdapter>

- (instancetype)initWithCapture:(QLMCapture *)capture NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) QLMCapture *capture;
@property (nonatomic, readonly) NSUInteger playedCount;
// Every message no exchange matched, as the address byte, then the payload.
@property (nonatomic, readonly) NSArray<NSData *> *unmatchedMessages;

@end

NS_ASSUME_NONNULL_END
