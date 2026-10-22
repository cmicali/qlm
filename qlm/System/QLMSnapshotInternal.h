#import "QLMSnapshot.h"

// For System, which builds snapshots. Nothing else writes them.

NS_ASSUME_NONNULL_BEGIN

@interface QLMMonitorState ()

- (instancetype)initWithHardwareID:(NSData *)hardwareID session:(uint8_t)session;

@property (nonatomic, readwrite, nullable) NSString *serialNumber;
@property (nonatomic, readwrite, nullable) NSString *systemInfo;
@property (nonatomic, readwrite) QLMMonitorStatus status;
@property (nonatomic, readwrite) NSInteger deviceClass;
@property (nonatomic, readwrite) NSInteger temperature;
@property (nonatomic, readwrite) NSInteger inputMeter;
@property (nonatomic, readwrite) NSInteger hfMeter;
@property (nonatomic, readwrite) NSInteger lfMeter;
@property (nonatomic, readwrite) NSInteger subMeter;
@property (nonatomic, readwrite) NSUInteger missedPolls;
@property (nonatomic, readwrite, nullable) NSDate *lastReply;
@property (nonatomic, readwrite) BOOL muted;

@end

@interface QLMSnapshot ()

- (instancetype)initWithRunning:(BOOL)running monitors:(NSArray<QLMMonitorState *> *)monitors volumeDecibels:(nullable NSNumber *)volumeDecibels;

@property (nonatomic, readwrite) BOOL dimmed;
@property (nonatomic, readwrite) BOOL applying;
@property (nonatomic, readwrite, nullable) NSString *activeGroupName;

@end

NS_ASSUME_NONNULL_END
