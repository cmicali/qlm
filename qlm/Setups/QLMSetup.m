#import "QLMSetupInternal.h"

@implementation QLMSetupBand
@end

@implementation QLMSetupNode

- (instancetype)init {
    self = [super init];
    if (self) {
        _className = @"";
        _serial = @"";
        _bands = @[];
    }
    return self;
}

@end

@implementation QLMSetupGroup

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _nodes = @[];
    }
    return self;
}

- (NSArray<QLMSetupNode *> *)nodesInDeviceOrder {
    return _nodesInDeviceOrder ?: _nodes;
}

- (QLMSetupNode *)nodeWithSerial:(NSString *)serial {
    for (QLMSetupNode *node in _nodes) {
        if ([node.serial isEqualToString:serial]) {
            return node;
        }
    }
    return nil;
}

@end

@implementation QLMSetupDevice

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = @"";
        _name = @"";
    }
    return self;
}

@end

@implementation QLMSetup

- (instancetype)init {
    self = [super init];
    if (self) {
        _magic = @"";
        _devices = @[];
        _groups = @[];
        _unknownKeys = @[];
    }
    return self;
}

- (QLMSetupDevice *)deviceWithSerial:(NSString *)serial {
    for (QLMSetupDevice *device in _devices) {
        if ([device.serial isEqualToString:serial]) {
            return device;
        }
    }
    return nil;
}

- (QLMSetupDevice *)deviceWithHardwareID:(NSData *)hardwareID {
    for (QLMSetupDevice *device in _devices) {
        if (device.hardwareID != nil && [device.hardwareID isEqualToData:hardwareID]) {
            return device;
        }
    }
    return nil;
}

@end
