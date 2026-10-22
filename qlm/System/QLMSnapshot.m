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

@implementation QLMSnapshot

- (instancetype)init {
    self = [super init];
    if (self) {
        _monitors = @[];
    }
    return self;
}

@end
