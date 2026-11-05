#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Asks for one call of `fire` at the screen's next frame, on the main queue.
typedef void (^QLMFrameRequest)(dispatch_block_t fire);

// Hands on the newest value it was given, at most once a screen frame, on
// the main queue. A value given while one waits replaces it, so a burst of
// snapshots draws once. It asks for a frame only while a value waits, so
// nothing runs while none does. On the main queue.
@interface QLMFrameCoalescer<ObjectType> : NSObject

- (instancetype)initWithApply:(void (^)(ObjectType value))apply NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The next main-queue turn until set. The app sets QLMDisplayFrameRequest().
@property (nonatomic, copy) QLMFrameRequest requestFrame;

- (void)submit:(ObjectType)value;
// Applies what waits now, if anything, as a verb that reads the windows
// must.
- (void)flush;
@property (nonatomic, readonly) BOOL pending;

@end

// The main screen's frames, from its display link on macOS 14 and later,
// else the next main-queue turn. TRAP: a display that sleeps or goes away
// gives no frames, so a request waits at most 100 ms for one.
QLMFrameRequest QLMDisplayFrameRequest(void);

NS_ASSUME_NONNULL_END
