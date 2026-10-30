#import <Foundation/Foundation.h>

#import "QLMAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// A simulated monitor. Change it only inside a block given to the bus's
// perform:, which runs on the bus's queue.
@interface QLMFakeMonitor : NSObject

- (instancetype)initWithHardwareID:(NSData *)hardwareID serialNumber:(NSString *)serialNumber systemInfo:(NSString *)systemInfo deviceClass:(uint8_t)deviceClass;

@property (nonatomic, readonly) NSData *hardwareID;
@property (nonatomic, readonly) NSString *serialNumber;
@property (nonatomic, readonly) NSString *systemInfo;
@property (nonatomic, readonly) uint8_t deviceClass;

@property (nonatomic) uint8_t temperature;
@property (nonatomic) BOOL on;          // NO sends standby telemetry
@property (nonatomic) BOOL present;     // NO answers nothing, as if unplugged
@property (nonatomic) uint8_t session;  // 0 when it holds no lease
// The next N replies are lost: to a lease, which the monitor still takes,
// and to unicasts.
@property (nonatomic) NSUInteger dropReplies;
@property (nonatomic) uint8_t muteValue;       // the last 2B value received

@end

// A bus of simulated monitors, behaving as the spec's section 9 describes,
// with the adapter itself at 01 answering as the captures show.
// Every message is packed as an output report, so the allowlist applies.
@interface QLMFakeBus : NSObject <QLMAdapter>

- (instancetype)initWithMonitors:(NSArray<QLMFakeMonitor *> *)monitors;

// Two 8330A, and a 7350A when asked, each answering with model and firmware.
+ (instancetype)demoBusWithSubwoofer:(BOOL)withSubwoofer;

@property (nonatomic, readonly) NSArray<QLMFakeMonitor *> *monitors;
// Every message sent, in order, as QLMAdapterRecord gives it, while
// recordsSentMessages is YES (the default).
@property (nonatomic, readonly) NSArray<NSData *> *sentMessages;
@property (atomic) BOOL recordsSentMessages;
@property (nonatomic) BOOL disconnected;  // every send fails
// Set: another host has the adapter. Every send fails with
// QLMAdapterErrorBusy and this description, and none is recorded, as the
// HID adapter sends nothing then.
@property (atomic, copy, nullable) NSString *busyReason;

// The adapter at 01. Change these only inside perform:.
@property (nonatomic, copy) NSString *adapterSystemInfo;
@property (nonatomic, copy) NSString *adapterSerialNumber;
@property (nonatomic, nullable) NSNumber *knobTenths;  // nil: no knob. -1004, the bottom stop, by default.
@property (nonatomic) NSUInteger adapterDropReplies;

// Runs the block on the bus's queue and waits for it.
- (void)perform:(dispatch_block_t)block;

@end

NS_ASSUME_NONNULL_END
