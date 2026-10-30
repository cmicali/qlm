#import <Foundation/Foundation.h>

#import "QLMAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// The GLM adapter over IOKit HID: vendor 1781, product 0E39, usage page FFA0.
// Each message goes out as one output report, and input reports reach the
// report link on System's queue, which is the queue given to startOnQueue:.
// Call every method on that queue.
//
// It never opens the adapter while another host has it: GLM 5 running, or
// another process holding the device. Then every send fails with
// QLMAdapterErrorBusy, whose description names the host, and nothing goes
// out. It checks before it opens, again just after, and every second while
// it runs; when a host appears, it closes the device at once. It seizes the
// device when IOKit allows, so GLM cannot open it meanwhile.
@interface QLMHIDAdapter : NSObject <QLMAdapter>

@property (nonatomic) NSTimeInterval replyTimeout;  // the report link's, 0.1 s

// Whether the open device is seized. NO while none is open.
@property (nonatomic, readonly) BOOL seized;

@end

NS_ASSUME_NONNULL_END
