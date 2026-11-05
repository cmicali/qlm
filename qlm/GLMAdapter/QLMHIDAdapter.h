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
// out. It checks before it opens, and again just after. While it runs, it
// reads the adapter's own part of the IORegistry each second, for a process
// that holds it. It scans every process for GLM only when GLM launches or
// quits, as the launch watch tells it, when a process opens the adapter,
// tries to, or closes it, as IOKit tells it, and every 30 s, in case an
// event never comes. When a host appears, it closes the device at once. A
// check that finds none reopens a free adapter, at most once a second. It opens the device only
// seized, so GLM cannot open it meanwhile. When IOKit will not let it seize
// the device, that too is a refusal.
//
// Each arrival of the adapter gets one report link, kept across closes and
// reopens. If the link gives up, reconnect closes the device and opens it
// again under the same link. The link stays given up across a reopen that
// fails, until the next, or until the adapter goes or another host takes it.
// If the link loses track of the adapter's replies, the adapter opens again
// only once it arrives anew, after a replug.
@interface QLMHIDAdapter : NSObject <QLMAdapter>

@property (nonatomic) NSTimeInterval replyTimeout;  // the report link's, 0.1 s

// Whether a device is open, which it is only seized.
@property (nonatomic, readonly) BOOL seized;

// Starts a watch of app launches and quits, which calls `changed` with each
// app's executable path, from any queue, until the block it returns runs.
// GLMAdapter links no AppKit, so the app hands it NSWorkspace's. Set it
// before the start. Without one, as in qlmctl, IOKit's events and the 30 s
// check remain.
typedef dispatch_block_t _Nonnull (^QLMLaunchWatch)(void (^changed)(NSString *executablePath));
@property (nonatomic, copy, nullable) QLMLaunchWatch launchWatch;

@end

NS_ASSUME_NONNULL_END
