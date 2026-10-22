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
@property (nonatomic) NSUInteger dropReplies;  // the next N replies are lost
@property (nonatomic) uint8_t muteValue;       // the last 2B value received

@end

// A bus of simulated monitors, behaving as the spec's section 9 describes.
// Every message goes through the frame encoder, so the allowlist applies.
@interface QLMFakeBus : NSObject <QLMAdapter>

- (instancetype)initWithMonitors:(NSArray<QLMFakeMonitor *> *)monitors;

@property (nonatomic, readonly) NSArray<QLMFakeMonitor *> *monitors;
// Every message sent, in order, as the address byte followed by the payload.
@property (nonatomic, readonly) NSArray<NSData *> *sentMessages;
@property (nonatomic) BOOL disconnected;  // every send fails

// Runs the block on the bus's queue and waits for it.
- (void)perform:(dispatch_block_t)block;

@end

NS_ASSUME_NONNULL_END
