#import <Foundation/Foundation.h>

#import "QLMClock.h"

NS_ASSUME_NONNULL_BEGIN

// How often the watch reads the adapter's own part of the IORegistry.
extern const NSTimeInterval QLMHostWatchClientInterval;
// How often the watch runs the full check with no event: the net under the
// events.
extern const NSTimeInterval QLMHostWatchFallbackInterval;

// Watches for another host while the HID adapter runs. Every
// QLMHostWatchClientInterval it runs the client check, which reads only
// the adapter's subtree of the IORegistry. It runs the full check, with its
// scan of every process's path, only when an event says a host may have
// come or gone: an app at a GLMv5.app path launched or quit, or a process
// opened the adapter, tried to, or closed it. And every
// QLMHostWatchFallbackInterval. Each check runs off the adapter's queue.
// Call every method but the two events on that queue.
@interface QLMHostWatch : NSObject

// `check` and `clientCheck` name a host, or return nil. `found` takes each
// check's answer on the queue.
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                        clock:(id<QLMClock>)clock
                        check:(NSString *_Nullable (^)(void))check
                  clientCheck:(NSString *_Nullable (^)(void))clientCheck
                        found:(void (^)(NSString *_Nullable host))found;

- (void)start;
// No check's answer arrives after a stop, even one in flight.
- (void)stop;

// From any queue. An app launched or quit, with its executable's path.
// Only a path QLMHostCheckIsGLMExecutable accepts starts a check.
- (void)appChangedAtPath:(NSString *)executablePath;
// From any queue. IOKit's interest message on the adapter or a service it
// hangs from: a process opened it, tried to, or closed it.
- (void)adapterChanged;

@end

NS_ASSUME_NONNULL_END
