#import "QLMSetupReader.h"

#import "QLMSetupInternal.h"

NSErrorDomain const QLMSetupErrorDomain = @"QLMSetupErrorDomain";
NSString *const QLMSetupErrorLineKey = @"QLMSetupErrorLine";

// One "Key:Value" line.
@interface QLMSetupEntry : NSObject
@property (nonatomic) NSString *key;
@property (nonatomic) NSString *value;
@property (nonatomic) NSInteger line;
@end

@implementation QLMSetupEntry
@end

@interface QLMSetupParser : NSObject
- (instancetype)initWithEntries:(NSArray<QLMSetupEntry *> *)entries;
- (nullable QLMSetup *)parse:(NSError **)error;
@end

@implementation QLMSetupReader

+ (QLMSetup *)readFileAtPath:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (data == nil) {
        return nil;
    }
    return [self readData:data error:error];
}

+ (QLMSetup *)readData:(NSData *)data error:(NSError **)error {
    // ISO Latin-1 decodes any bytes, so the fallback cannot fail.
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                         ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];

    // Lines are CRLF. A line without a colon is part of the banner before
    // the magic, or a separator of dashes. Blank lines hold one space.
    NSMutableArray<QLMSetupEntry *> *entries = [NSMutableArray array];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    BOOL sawMagic = NO;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:whitespace];
        if (line.length == 0 || [line hasPrefix:@"--"]) {
            continue;
        }
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            if (sawMagic) {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:QLMSetupErrorDomain code:QLMSetupErrorStructure
                                             userInfo:@{QLMSetupErrorLineKey: @(i + 1), NSLocalizedDescriptionKey: @"a line without a key"}];
                }
                return nil;
            }
            continue;
        }
        QLMSetupEntry *entry = [[QLMSetupEntry alloc] init];
        entry.key = [line substringToIndex:colon.location];
        entry.value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:whitespace];
        entry.line = (NSInteger)i + 1;
        [entries addObject:entry];
        if ([entry.key isEqualToString:@"Magic"]) {
            sawMagic = YES;
        }
    }
    return [[[QLMSetupParser alloc] initWithEntries:entries] parse:error];
}

@end

#pragma mark - The parser

@implementation QLMSetupParser {
    NSArray<QLMSetupEntry *> *_entries;
    NSUInteger _position;
    NSMutableArray<NSString *> *_unknown;
    NSError *_error;
    NSUInteger _deviceCount;
    NSUInteger _groupCount;
    // Keys the file carries that qlm has no use for. Listed so they are not
    // reported as unknown. Anything else new in a future GLM is.
    NSSet<NSString *> *_headerIgnored;
    NSSet<NSString *> *_deviceIgnored;
    NSSet<NSString *> *_groupIgnored;
    NSSet<NSString *> *_nodeIgnored;
}

- (instancetype)initWithEntries:(NSArray<QLMSetupEntry *> *)entries {
    self = [super init];
    if (self) {
        _entries = entries;
        _unknown = [NSMutableArray array];
        _headerIgnored = [NSSet setWithArray:@[
            @"RoomWidth", @"RoomLenght", @"RoomHeight", @"Created", @"Modified", @"GridSize", @"GLMTheme",
            @"MicReferenceLevel", @"LEDOFF", @"SubwooferBypass", @"PowerMateKnopEnabled", @"RFRemoteEnabled",
            @"LevelPanelEnabled", @"ShutDownGroupOffDevices", @"SignalDetectionEnabled", @"SystemPowerStatus",
            @"ShowInfoType", @"SoundDoseWarningOff", @"SystemSensitivity",
        ]];
        _deviceIgnored = [NSSet setWithArray:@[
            @"Uniq_ID", @"Barcode", @"SineTone_Supported", @"XPos", @"YPos", @"ZPos", @"Orientation", @"Elevation",
            @"Colour", @"SE_Output", @"MicrophoneSerial", @"MicrophoneSensitivity", @"MicrophoneSensitivityCorrection",
        ]];
        _groupIgnored = [NSSet setWithArray:@[
            @"Calibration_Description", @"AutoCal_Cloud", @"Session_ID", @"ReferenceLevelActive", @"Loudness_Signal_Level",
            @"Loudness_Target_Level", @"Loudness_Calibrated_Level", @"HP_Loudness_Calibrated_Level", @"Group_Microphone_Serial",
            @"Group_RoomProfile", @"Group_RoomProfile_MidRange", @"Group_RoomProfile_Strength", @"Group_SymmetricalEQ",
            @"Group_Audio",
        ]];
        _nodeIgnored = [NSSet setWithArray:@[
            @"CalibrationGroupID", @"CalibrationStatusFlag", @"PhaseCalibratedWith", @"MultiChannel_AES_EBU",
            @"WooferSystemWithSerial", @"RateFlatness", @"RateCorrelated",
        ]];
    }
    return self;
}

#pragma mark Cursor

- (nullable QLMSetupEntry *)peek {
    return _position < _entries.count ? _entries[_position] : nil;
}

- (nullable QLMSetupEntry *)next {
    QLMSetupEntry *entry = [self peek];
    if (entry != nil) {
        _position++;
    }
    return entry;
}

- (void)failAt:(nullable QLMSetupEntry *)entry code:(QLMSetupError)code message:(NSString *)message {
    if (_error != nil) {
        return;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = message;
    if (entry != nil) {
        info[QLMSetupErrorLineKey] = @(entry.line);
    }
    _error = [NSError errorWithDomain:QLMSetupErrorDomain code:code userInfo:info];
}

- (nullable QLMSetupEntry *)expect:(NSString *)key {
    QLMSetupEntry *entry = [self next];
    if (entry == nil || ![entry.key isEqualToString:key]) {
        [self failAt:entry code:QLMSetupErrorStructure message:[NSString stringWithFormat:@"expected %@", key]];
        return nil;
    }
    return entry;
}

- (void)unknown:(QLMSetupEntry *)entry in:(NSString *)where {
    [_unknown addObject:[NSString stringWithFormat:@"%@: %@", where, entry.key]];
}

#pragma mark Values

- (double)number:(QLMSetupEntry *)entry {
    const char *text = entry.value.UTF8String;
    char *end = NULL;
    double value = strtod(text, &end);
    if (end == text || *end != '\0') {
        [self failAt:entry code:QLMSetupErrorValue message:[NSString stringWithFormat:@"%@ is not a number", entry.key]];
        return 0;
    }
    return value;
}

- (NSInteger)integer:(QLMSetupEntry *)entry {
    return (NSInteger)[self number:entry];
}

- (BOOL)flag:(QLMSetupEntry *)entry {
    return [self integer:entry] != 0;
}

- (nullable NSString *)text:(QLMSetupEntry *)entry {
    return entry.value.length > 0 ? entry.value : nil;
}

#pragma mark Sections

- (nullable QLMSetup *)parse:(NSError **)error {
    QLMSetup *setup = [[QLMSetup alloc] init];
    QLMSetupEntry *magic = [self expect:@"Magic"];
    if (magic != nil && ![magic.value isEqualToString:@"GLM5_v2"]) {
        [self failAt:magic code:QLMSetupErrorMagic message:@"not a GLM5_v2 file"];
    }
    if (_error == nil) {
        setup.magic = magic.value;
        [self parseHeaderInto:setup];
    }
    if (_error == nil) {
        [self parseDevicesInto:setup];
    }
    if (_error == nil) {
        [self parseGroupsInto:setup];
    }
    if (_error == nil && [self peek] != nil) {
        [self failAt:[self peek] code:QLMSetupErrorStructure message:@"content after the last group"];
    }
    if (_error != nil) {
        if (error != NULL) {
            *error = _error;
        }
        return nil;
    }
    setup.unknownKeys = [_unknown copy];
    return setup;
}

- (void)parseHeaderInto:(QLMSetup *)setup {
    NSInteger deviceCount = -1;
    NSInteger groupCount = -1;
    while (_error == nil) {
        QLMSetupEntry *entry = [self next];
        if (entry == nil) {
            [self failAt:nil code:QLMSetupErrorStructure message:@"no Header_End"];
            return;
        }
        NSString *key = entry.key;
        if ([key isEqualToString:@"Header_End"]) {
            break;
        } else if ([key isEqualToString:@"GLM_Version"]) {
            setup.glmVersion = [self text:entry];
        } else if ([key isEqualToString:@"AdapterData"]) {
            setup.adapter = [self parseDevice];
        } else if ([key isEqualToString:@"Setup_Name"]) {
            setup.setupName = [self text:entry];
        } else if ([key isEqualToString:@"LayoutStyle"]) {
            setup.layoutStyle = [self text:entry];
        } else if ([key isEqualToString:@"Devices"]) {
            deviceCount = [self integer:entry];
        } else if ([key isEqualToString:@"Groups"]) {
            groupCount = [self integer:entry];
        } else if ([key isEqualToString:@"Active_Group"]) {
            setup.activeGroup = [self integer:entry];
        } else if ([key isEqualToString:@"Volume"]) {
            setup.volume = [self number:entry];
        } else if ([key isEqualToString:@"VolumeMute"]) {
            setup.volumeMute = [self flag:entry];
        } else if ([key isEqualToString:@"VolumeDim"]) {
            setup.volumeDim = [self flag:entry];
        } else if ([key isEqualToString:@"Volume_Max_Limit"]) {
            setup.volumeMaxLimit = [self number:entry];
        } else if ([key isEqualToString:@"StartupLevel"]) {
            setup.startupLevel = [self number:entry];
        } else if ([key isEqualToString:@"StartupLevelEnabled"]) {
            setup.startupLevelEnabled = [self flag:entry];
        } else if ([key isEqualToString:@"AutomaticPowerUp"]) {
            setup.automaticPowerUp = [self flag:entry];
        } else if ([key isEqualToString:@"AutomaticShutDown"]) {
            setup.automaticShutDown = [self flag:entry];
        } else if ([key isEqualToString:@"ISSDelay"]) {
            setup.issDelay = [self integer:entry];
        } else if ([key isEqualToString:@"ISSSensitivity"]) {
            setup.issSensitivity = [self integer:entry];
        } else if ([key isEqualToString:@"LEDDisable"]) {
            setup.ledDisable = [self flag:entry];
        } else if ([key isEqualToString:@"InputMode"]) {
            setup.inputMode = [self integer:entry];
        } else if (![_headerIgnored containsObject:key]) {
            [self unknown:entry in:@"header"];
        }
    }
    if (_error != nil) {
        return;
    }
    if (deviceCount < 0 || groupCount < 0) {
        [self failAt:nil code:QLMSetupErrorStructure message:@"no Devices or Groups count"];
        return;
    }
    _deviceCount = (NSUInteger)deviceCount;
    _groupCount = (NSUInteger)groupCount;
}

// Big-endian, from at most 8 decimal digits.
static NSData *_Nullable QLMHardwareIDForSerial(NSString *serial) {
    if (serial.length == 0 || serial.length > 8) {
        return nil;
    }
    uint32_t value = 0;
    for (NSUInteger i = 0; i < serial.length; i++) {
        unichar digit = [serial characterAtIndex:i];
        if (digit < '0' || digit > '9') {
            return nil;
        }
        value = value * 10 + (uint32_t)(digit - '0');
    }
    if (value > 0xFFFFFF) {
        return nil;
    }
    const uint8_t bytes[3] = {(uint8_t)(value >> 16), (uint8_t)(value >> 8), (uint8_t)value};
    return [NSData dataWithBytes:bytes length:3];
}

// Model, then keys to Data_End. The adapter's block has the same shape.
- (nullable QLMSetupDevice *)parseDevice {
    QLMSetupEntry *model = [self expect:@"Model"];
    if (model == nil) {
        return nil;
    }
    QLMSetupDevice *device = [[QLMSetupDevice alloc] init];
    device.model = model.value;
    NSString *where = [NSString stringWithFormat:@"device %@", model.value];
    while (_error == nil) {
        QLMSetupEntry *entry = [self next];
        if (entry == nil) {
            [self failAt:model code:QLMSetupErrorStructure message:@"a device without Data_End"];
            return nil;
        }
        NSString *key = entry.key;
        if ([key isEqualToString:@"Data_End"]) {
            return device;
        } else if ([key isEqualToString:@"Type"]) {
            device.type = [self integer:entry];
        } else if ([key isEqualToString:@"Serial"]) {
            device.serial = [self text:entry];
            device.hardwareID = device.serial != nil ? QLMHardwareIDForSerial(device.serial) : nil;
        } else if ([key isEqualToString:@"Name"]) {
            device.name = entry.value;
        } else if ([key isEqualToString:@"Hardware_Version"]) {
            device.hardwareVersion = [self text:entry];
        } else if ([key isEqualToString:@"DSP_Sw_Version"]) {
            device.dspVersion = [self text:entry];
        } else if ([key isEqualToString:@"Micro_Sw_Version"]) {
            device.microVersion = [self text:entry];
        } else if ([key isEqualToString:@"DBM_Filter"]) {
            device.dbmFilter = [self flag:entry];
        } else if (![_deviceIgnored containsObject:key]) {
            [self unknown:entry in:where];
        }
    }
    return nil;
}

- (void)parseDevicesInto:(QLMSetup *)setup {
    NSMutableArray<QLMSetupDevice *> *devices = [NSMutableArray array];
    for (NSUInteger i = 0; i < _deviceCount && _error == nil; i++) {
        QLMSetupDevice *device = [self parseDevice];
        if (device != nil) {
            [devices addObject:device];
        }
    }
    setup.devices = devices;
}

// A band is its own key, then Frequency, Gain, Q_Value for a peak, and SR.
- (nullable QLMSetupBand *)parseBandOfType:(QLMSetupBandType)type from:(QLMSetupEntry *)start {
    QLMSetupBand *band = [[QLMSetupBand alloc] init];
    band.type = type;
    band.index = [self integer:start];
    BOOL sawFrequency = NO, sawGain = NO, sawQ = NO, sawRate = NO;
    // Each value once. A repeat belongs to something else, so the band ends.
    while (_error == nil) {
        QLMSetupEntry *entry = [self peek];
        if (entry == nil) {
            break;
        }
        if ([entry.key isEqualToString:@"Frequency"] && !sawFrequency) {
            band.frequency = [self number:entry];
            sawFrequency = YES;
        } else if ([entry.key isEqualToString:@"Gain"] && !sawGain) {
            band.gain = [self number:entry];
            sawGain = YES;
        } else if ([entry.key isEqualToString:@"Q_Value"] && !sawQ) {
            band.q = [self number:entry];
            sawQ = YES;
        } else if ([entry.key isEqualToString:@"SR"] && !sawRate) {
            band.sampleRate = [self number:entry];
            sawRate = YES;
        } else {
            break;
        }
        [self next];
    }
    if (_error == nil && !(sawFrequency && sawGain && sawRate)) {
        [self failAt:start code:QLMSetupErrorStructure message:@"a band without Frequency, Gain, and SR"];
        return nil;
    }
    return band;
}

static QLMSetupNodeClass QLMNodeClassNamed(NSString *name) {
    if ([name isEqualToString:@"TwowayGen2"]) {
        return QLMSetupNodeClassTwoWay;
    }
    if ([name isEqualToString:@"ThreewayGen2"]) {
        return QLMSetupNodeClassThreeWay;
    }
    if ([name isEqualToString:@"SubwooferGen2"]) {
        return QLMSetupNodeClassSubwoofer;
    }
    return QLMSetupNodeClassUnknown;
}

// Class, then keys and bands to Data_End.
- (nullable QLMSetupNode *)parseNodeInGroup:(NSString *)groupName {
    QLMSetupEntry *classEntry = [self expect:@"Class"];
    if (classEntry == nil) {
        return nil;
    }
    QLMSetupNode *node = [[QLMSetupNode alloc] init];
    node.className = classEntry.value;
    node.nodeClass = QLMNodeClassNamed(classEntry.value);
    NSMutableArray<QLMSetupBand *> *bands = [NSMutableArray array];
    NSString *where = [NSString stringWithFormat:@"group %@ node ?", groupName];
    while (_error == nil) {
        QLMSetupEntry *entry = [self next];
        if (entry == nil) {
            [self failAt:classEntry code:QLMSetupErrorStructure message:@"a node without Data_End"];
            return nil;
        }
        NSString *key = entry.key;
        if ([key isEqualToString:@"Data_End"]) {
            node.bands = bands;
            return node;
        } else if ([key isEqualToString:@"Serial"]) {
            node.serial = entry.value;
            node.hardwareID = QLMHardwareIDForSerial(entry.value);
            where =[NSString stringWithFormat:@"group %@ node %@", groupName, entry.value];
        } else if ([key isEqualToString:@"Group_ON"]) {
            node.on = [self flag:entry];
        } else if ([key isEqualToString:@"Level_Sensitivity"]) {
            node.levelSensitivity = [self number:entry];
        } else if ([key isEqualToString:@"Calibration_Level"]) {
            node.calibrationLevel = [self number:entry];
        } else if ([key isEqualToString:@"Optional_Gain"]) {
            node.optionalGain = [self number:entry];
        } else if ([key isEqualToString:@"Time-of-flight_Compensation"]) {
            node.timeOfFlightCompensation = [self number:entry];
        } else if ([key isEqualToString:@"Video_Delay"]) {
            node.videoDelay = [self number:entry];
        } else if ([key isEqualToString:@"Group_Sensitivity"]) {
            node.groupSensitivity = [self number:entry];
        } else if ([key isEqualToString:@"Input"]) {
            node.input = [self integer:entry];
        } else if ([key isEqualToString:@"Input1_AES_EBUChannel"]) {
            node.aesChannel = [self integer:entry];
        } else if ([key isEqualToString:@"CrossoverFrequency(Hz)"]) {
            node.crossoverFrequency = [self number:entry];
        } else if ([key isEqualToString:@"Phase(degrees)"]) {
            node.phaseDegrees = @([self number:entry]);
        } else if ([key isEqualToString:@"LFE_+10"]) {
            node.lfePlus10 = @([self number:entry]);
        } else if ([key isEqualToString:@"LFE_Channel"]) {
            node.lfeChannel = @([self number:entry]);
        } else if ([key isEqualToString:@"LFE_CrossoverFrequency(Hz)"]) {
            node.lfeCrossoverFrequency = @([self number:entry]);
        } else if ([key isEqualToString:@"LFE_Level"]) {
            node.lfeLevel = @([self number:entry]);
        } else if ([key isEqualToString:@"SubwooferGroupID"]) {
            node.subwooferGroupID = @([self number:entry]);
        } else if ([key isEqualToString:@"GroupDelayCompensation"]) {
            node.groupDelayCompensation = @([self number:entry]);
        } else if ([key isEqualToString:@"BassExtensionXO(Hz)"]) {
            node.bassExtensionCrossover = @([self number:entry]);
        } else if ([key isEqualToString:@"LP_Shelve"]) {
            QLMSetupBand *band = [self parseBandOfType:QLMSetupBandLowShelf from:entry];
            if (band != nil) [bands addObject:band];
        } else if ([key isEqualToString:@"HP_Shelve"]) {
            QLMSetupBand *band = [self parseBandOfType:QLMSetupBandHighShelf from:entry];
            if (band != nil) [bands addObject:band];
        } else if ([key isEqualToString:@"Notch"]) {
            QLMSetupBand *band = [self parseBandOfType:QLMSetupBandPeak from:entry];
            if (band != nil) [bands addObject:band];
        } else if ([key isEqualToString:@"Frequency"] || [key isEqualToString:@"Gain"] || [key isEqualToString:@"Q_Value"] ||
                   [key isEqualToString:@"SR"]) {
            [self failAt:entry code:QLMSetupErrorStructure message:@"a band value outside a band"];
            return nil;
        } else if (![_nodeIgnored containsObject:key]) {
            [self unknown:entry in:where];
        }
    }
    return nil;
}

// Group_Name, the group's keys, the 9320 panel block, Group_Nodes and the
// nodes, then Group_End.
- (nullable QLMSetupGroup *)parseGroup {
    QLMSetupEntry *nameEntry = [self expect:@"Group_Name"];
    if (nameEntry == nil) {
        return nil;
    }
    QLMSetupGroup *group = [[QLMSetupGroup alloc] init];
    group.name = nameEntry.value;
    NSString *where = [NSString stringWithFormat:@"group %@", nameEntry.value];
    NSInteger nodeCount = -1;
    BOOL inPanel = NO;  // the 9320 reference controller's settings, not qlm's
    while (_error == nil) {
        QLMSetupEntry *entry = [self next];
        if (entry == nil) {
            [self failAt:nameEntry code:QLMSetupErrorStructure message:@"a group without Group_Nodes"];
            return nil;
        }
        NSString *key = entry.key;
        if ([key isEqualToString:@"Group_Nodes"]) {
            nodeCount = [self integer:entry];
            if (nodeCount < 0) {
                [self failAt:entry code:QLMSetupErrorStructure message:@"a negative Group_Nodes"];
            }
            break;
        } else if (inPanel) {
            continue;
        } else if ([key isEqualToString:@"9320DATA"]) {
            inPanel = YES;
        } else if ([key isEqualToString:@"Group_Calibrated"]) {
            group.calibrated = [self text:entry];
        } else if ([key isEqualToString:@"Group_Sensitivity"]) {
            group.groupSensitivity = [self number:entry];
        } else if ([key isEqualToString:@"Group_Crossover"]) {
            group.crossover = [self number:entry];
        } else if ([key isEqualToString:@"Group_Crossover_GlobalMode"]) {
            group.crossoverGlobalMode = [self integer:entry];
        } else if ([key isEqualToString:@"GroupDelayCompensation"]) {
            group.groupDelayCompensation = @([self number:entry]);
        } else if ([key isEqualToString:@"Group_BE_Mode"]) {
            group.bassExtensionMode = @([self number:entry]);
        } else if ([key isEqualToString:@"Group_BE_XOMin"]) {
            group.bassExtensionCrossoverMin = @([self number:entry]);
        } else if ([key isEqualToString:@"Group_BE_XOMax"]) {
            group.bassExtensionCrossoverMax = @([self number:entry]);
        } else if ([key isEqualToString:@"Video_Delay"]) {
            group.videoDelay = [self number:entry];
        } else if ([key isEqualToString:@"SubwooferBypass"]) {
            group.subwooferBypass = [self flag:entry];
        } else if ([key isEqualToString:@"VolumePreset1"]) {
            group.volumePreset1 = @([self number:entry]);
        } else if ([key isEqualToString:@"VolumePreset2"]) {
            group.volumePreset2 = @([self number:entry]);
        } else if ([key isEqualToString:@"Group_LP_Shelve"]) {
            group.lowShelf = [self parseBandOfType:QLMSetupBandLowShelf from:entry];
        } else if ([key isEqualToString:@"Group_HP_Shelve"]) {
            group.highShelf = [self parseBandOfType:QLMSetupBandHighShelf from:entry];
        } else if (![_groupIgnored containsObject:key]) {
            [self unknown:entry in:where];
        }
    }
    if (_error != nil) {
        return nil;
    }
    NSMutableArray<QLMSetupNode *> *nodes = [NSMutableArray array];
    for (NSInteger i = 0; i < nodeCount && _error == nil; i++) {
        QLMSetupNode *node = [self parseNodeInGroup:group.name];
        if (node != nil) {
            [nodes addObject:node];
        }
    }
    group.nodes = nodes;
    if (_error == nil) {
        [self expect:@"Group_End"];
    }
    return _error == nil ? group : nil;
}

static NSArray<QLMSetupNode *> *QLMNodesInDeviceOrder(NSArray<QLMSetupNode *> *nodes, NSArray<QLMSetupDevice *> *devices) {
    NSMutableArray<QLMSetupNode *> *ordered = [NSMutableArray arrayWithCapacity:nodes.count];
    for (QLMSetupDevice *device in devices) {
        for (QLMSetupNode *node in nodes) {
            if (device.serial != nil && [node.serial isEqualToString:device.serial] && ![ordered containsObject:node]) {
                [ordered addObject:node];
            }
        }
    }
    for (QLMSetupNode *node in nodes) {
        if (![ordered containsObject:node]) {
            [ordered addObject:node];
        }
    }
    return ordered;
}

- (void)parseGroupsInto:(QLMSetup *)setup {
    NSMutableArray<QLMSetupGroup *> *groups = [NSMutableArray array];
    for (NSUInteger i = 0; i < _groupCount && _error == nil; i++) {
        QLMSetupGroup *group = [self parseGroup];
        if (group != nil) {
            group.nodesInDeviceOrder = QLMNodesInDeviceOrder(group.nodes, setup.devices);
            [groups addObject:group];
        }
    }
    setup.groups = groups;
}

@end
