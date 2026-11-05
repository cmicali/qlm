#import <Foundation/Foundation.h>

#import "QLMClock.h"

NS_ASSUME_NONNULL_BEGIN

// How often the watch checks with no event: the net under the events.
extern const NSTimeInterval QLMHostWatchFallbackInterval;

// Watches for another host while the HID adapter runs. It checks when an
// event says one may have come or gone: an app at a GLMv5.app path
// launched or quit, or a process opened, tried to open, or closed the
// adapter. It checks every QLMHostWatchFallbackInterval too. With no
// event, it checks nothing more. Each check runs off the adapter's queue.
// Call every method but the two events on that queue.
@interface QLMHostWatch : NSObject

// `check` names a host, or returns nil. `found` takes each check's answer on
// the queue.
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                        clock:(id<QLMClock>)clock
                        check:(NSString *_Nullable (^)(void))check
                        found:(void (^)(NSString *_Nullable host))found;

- (void)start;
// No check's answer arrives after a stop.
- (void)stop;

// From any queue. An app launched or quit, with its executable's path.
// Only a path QLMHostCheckIsGLMExecutable accepts starts a check.
- (void)appChangedAtPath:(NSString *)executablePath;
// From any queue. IOKit's interest message on the adapter or a service it
// hangs from: a process opened it, tried to, or closed it.
- (void)adapterChanged;

@end

NS_ASSUME_NONNULL_END
