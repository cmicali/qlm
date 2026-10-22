#import "QLMSnapshotInternal.h"

const NSInteger QLMMonitorValueAbsent = -1;

@implementation QLMMonitorState

- (instancetype)initWithHardwareID:(NSData *)hardwareID session:(uint8_t)session {
    self = [super init];
    if (self) {
        _hardwareID = [hardwareID copy];
        _session = session;
        _status = QLMMonitorStatusUnknown;
        _deviceClass = QLMMonitorValueAbsent;
        _temperature = QLMMonitorValueAbsent;
        _inputMeter = QLMMonitorValueAbsent;
        _hfMeter = QLMMonitorValueAbsent;
        _lfMeter = QLMMonitorValueAbsent;
        _subMeter = QLMMonitorValueAbsent;
    }
    return self;
}

@end

@implementation QLMSnapshot

- (instancetype)initWithRunning:(BOOL)running monitors:(NSArray<QLMMonitorState *> *)monitors volumeDecibels:(NSNumber *)volumeDecibels {
    self = [super init];
    if (self) {
        _date = [NSDate date];
        _running = running;
        _monitors = [monitors copy];
        _volumeDecibels = volumeDecibels;
    }
    return self;
}

@end
