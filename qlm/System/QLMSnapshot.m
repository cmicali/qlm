#import "QLMSnapshotInternal.h"

const NSInteger QLMMonitorValueAbsent = -1;

@implementation QLMMonitorState

- (instancetype)init {
    self = [super init];
    if (self) {
        _hardwareID = [NSData data];
        _temperature = QLMMonitorValueAbsent;
        _inputMeter = QLMMonitorValueAbsent;
        _hfMeter = QLMMonitorValueAbsent;
        _lfMeter = QLMMonitorValueAbsent;
        _subMeter = QLMMonitorValueAbsent;
    }
    return self;
}

@end

@implementation QLMAdapterState

- (instancetype)init {
    self = [super init];
    if (self) {
        _device = @"";
    }
    return self;
}

@end

@implementation QLMKnownLease

- (instancetype)initWithHardwareID:(NSData *)hardwareID serialNumber:(NSString *)serialNumber session:(uint8_t)session {
    self = [super init];
    if (self) {
        _hardwareID = [hardwareID copy];
        _serialNumber = [serialNumber copy];
        _session = session;
    }
    return self;
}

@end

@implementation QLMHandBack
@end

@implementation QLMSnapshot

- (instancetype)init {
    self = [super init];
    if (self) {
        _adapter = [[QLMAdapterState alloc] init];
        _monitors = @[];
        _mutedHardwareIDs = [NSSet set];
        _liftedHardwareIDs = [NSSet set];
        _knownLeases = @[];
        _handBack = [[QLMHandBack alloc] init];
    }
    return self;
}

@end
