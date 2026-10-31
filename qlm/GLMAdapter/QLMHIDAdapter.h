#import <Foundation/Foundation.h>

#import "QLMAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// The GLM adapter over IOKit HID: vendor 1781, product 0E39, usage page FFA0.
// Each message goes out as one output report, and input reports reach the
// report link on System's queue, the queue given to startOnQueue:clock:.
// Call every method on that queue.
//
// It never opens the adapter while another host has it: GLM 5 running, or
// another process holding the device. Then every send fails with
// QLMAdapterErrorBusy, whose description names the host, and nothing goes
// out. It checks before it opens, again just after, and every second while
// it runs; when a host appears, it closes the device at once. It opens the
// device only seized, so GLM cannot open it meanwhile. When IOKit will not
// let it seize the device, that too is a refusal.
//
// Each arrival of the adapter gets one report link, kept across closes and
// reopens. If the link gives up, reconnect closes the device and opens it
// again under the same link. If the link loses track of the adapter's
// replies, the adapter opens again only once it arrives anew, after a
// replug.
@interface QLMHIDAdapter : NSObject <QLMAdapter>

@property (nonatomic) NSTimeInterval replyTimeout;  // the report link's, 0.1 s

// Whether a device is open, which it is only seized.
@property (nonatomic, readonly) BOOL seized;

@end

NS_ASSUME_NONNULL_END
