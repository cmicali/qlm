#import "QLMSnapshot.h"

// For System, which builds snapshots. Nothing else writes them.

NS_ASSUME_NONNULL_BEGIN

@interface QLMMonitorState ()

@property (nonatomic, readwrite) NSData *hardwareID;
@property (nonatomic, readwrite) uint8_t session;
@property (nonatomic, readwrite, nullable) NSString *serialNumber;
@property (nonatomic, readwrite, nullable) NSString *systemInfo;
@property (nonatomic, readwrite, nullable) NSString *model;
@property (nonatomic, readwrite, nullable) NSString *firmwareVersion;
@property (nonatomic, readwrite) QLMMonitorStatus status;
@property (nonatomic, readwrite) QLMMonitorClass deviceClass;
@property (nonatomic, readwrite) NSInteger temperature;
@property (nonatomic, readwrite) NSInteger inputMeter;
@property (nonatomic, readwrite) NSInteger hfMeter;
@property (nonatomic, readwrite) NSInteger lfMeter;
@property (nonatomic, readwrite) NSInteger subMeter;
@property (nonatomic, readwrite) NSUInteger missedPolls;
@property (nonatomic, readwrite, nullable) NSDate *lastReply;
@property (nonatomic, readwrite) BOOL muted;
@property (nonatomic, readwrite) BOOL identified;

@end

@interface QLMAdapterState ()

@property (nonatomic, readwrite) NSString *device;
@property (nonatomic, readwrite, nullable) NSString *systemInfo;
@property (nonatomic, readwrite, nullable) NSString *model;
@property (nonatomic, readwrite, nullable) NSString *firmwareVersion;
@property (nonatomic, readwrite, nullable) NSString *serialNumber;
@property (nonatomic, readwrite) BOOL hasStatus;
@property (nonatomic, readwrite) BOOL knobPresent;
@property (nonatomic, readwrite) BOOL micPresent;
@property (nonatomic, readwrite, nullable) NSNumber *knobTenths;
@property (nonatomic, readwrite) NSUInteger missedPolls;
@property (nonatomic, readwrite, nullable) NSDate *lastReply;
@property (nonatomic, readwrite) BOOL identified;

@end

@interface QLMSnapshot ()

@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) QLMAdapterState *adapter;
@property (nonatomic, readwrite, nullable) NSError *adapterError;
@property (nonatomic, readwrite) NSArray<QLMMonitorState *> *monitors;
@property (nonatomic, readwrite, nullable) NSNumber *volumeDecibels;
@property (nonatomic, readwrite) BOOL dimmed;
@property (nonatomic, readwrite) BOOL applying;
@property (nonatomic, readwrite, nullable) NSString *activeGroupName;
@property (nonatomic, readwrite) BOOL idle;
@property (nonatomic, readwrite) BOOL allIdentified;
@property (nonatomic, readwrite) BOOL allMuted;
@property (nonatomic, readwrite) BOOL anyOn;

@end

NS_ASSUME_NONNULL_END
