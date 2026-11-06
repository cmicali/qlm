#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Asks for one call of `fire` later, on the main queue.
typedef void (^QLMFrameRequest)(dispatch_block_t fire);

// Hands on the newest value it was given, once, at the main queue's next
// turn. A value given while one waits replaces it, so a burst of snapshots
// draws once. It asks for a turn only while a value waits, so nothing runs
// while none does. On the main queue.
@interface QLMFrameCoalescer<ObjectType> : NSObject

- (instancetype)initWithApply:(void (^)(ObjectType value))apply NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// dispatch_async on the main queue until set. The tests swap it.
@property (nonatomic, copy) QLMFrameRequest requestFrame;

- (void)submit:(ObjectType)value;
// Applies what waits now, if anything, as a verb that reads the windows
// must.
- (void)flush;
@property (nonatomic, readonly) BOOL pending;

@end

NS_ASSUME_NONNULL_END
