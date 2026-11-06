#import "QLMTrafficLog.h"

#import "QLMFormat.h"

#include "QLMDescribe.h"

NSArray<NSString *> *QLMTrafficDirectionNames(void) {
    return @[@"both", @"sent", @"received"];
}

static NSString *QLMTrafficDirectionText(QLMTrafficKind kind) {
    switch (kind) {
    case QLMTrafficRequest: return @"→";
    case QLMTrafficSync: return @"→ sync";
    case QLMTrafficNotTaken: return @"→ not taken";
    case QLMTrafficReply: return @"←";
    case QLMTrafficNoAnswer: return @"←";
    case QLMTrafficStray: return @"← stray";
    case QLMTrafficUnreadable: return @"← unreadable";
    case QLMTrafficTimeout: return @"timeout";
    }
    return @"?";
}

static NSString *QLMTrafficKindName(QLMTrafficKind kind) {
    switch (kind) {
    case QLMTrafficRequest: return @"request";
    case QLMTrafficSync: return @"sync";
    case QLMTrafficNotTaken: return @"not taken";
    case QLMTrafficReply: return @"reply";
    case QLMTrafficNoAnswer: return @"no answer";
    case QLMTrafficStray: return @"stray";
    case QLMTrafficUnreadable: return @"unreadable";
    case QLMTrafficTimeout: return @"timeout";
    }
    return @"unknown";
}

static NSString *QLMTrafficTimeText(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    return [formatter stringFromDate:date];
}

@interface QLMTrafficRow ()
@property (nonatomic, readwrite) QLMTrafficEntry *entry;
@property (nonatomic, readwrite) NSString *timeText;
@property (nonatomic, readwrite) NSString *directionText;
@property (nonatomic, readwrite) NSString *targetText;
@property (nonatomic, readwrite) NSString *bytesText;
@property (nonatomic, readwrite) NSString *descriptionText;
@property (nonatomic, readwrite) NSInteger opcode;
@property (nonatomic, readwrite) NSString *targetKey;
@end

@implementation QLMTrafficRow

- (NSString *)line {
    return [NSString stringWithFormat:@"%@  #%llu  %@  %@  %@  %@", self.timeText, self.entry.number, self.directionText,
                                      self.targetText, self.bytesText.length > 0 ? self.bytesText : @"-", self.descriptionText];
}

- (NSDictionary<NSString *, id> *)JSON {
    QLMTrafficEntry *entry = self.entry;
    return @{
        @"number": @(entry.number),
        @"time": self.timeText,
        @"kind": QLMTrafficKindName(entry.kind),
        @"outgoing": @(entry.outgoing),
        @"target": self.targetText,
        @"bytes": self.bytesText,
        @"description": self.descriptionText,
        @"answers": entry.answers == 0 ? NSNull.null : @(entry.answers),
    };
}

@end

@implementation QLMTrafficLog {
    NSUInteger _limit;
    NSMutableArray<QLMTrafficRow *> *_rows;
    NSMutableArray<QLMTrafficRow *> *_shown;
    __weak id _system;
    uint64_t _lastNumber;  // the last entry taken from _system
    NSMutableDictionary<NSData *, NSNumber *> *_rates;  // the setup's design rate by hardware ID, 0 for none
    NSMutableDictionary<NSData *, NSString *> *_names;  // each monitor's text, once its serial is known
    NSMutableSet<NSNumber *> *_opcodes;
    NSMutableArray<NSArray<NSString *> *> *_targets;
}

- (instancetype)init {
    return [self initWithLimit:5000];
}

- (instancetype)initWithLimit:(NSUInteger)limit {
    self = [super init];
    if (self) {
        _limit = MAX(limit, 1u);
        _rows = [NSMutableArray array];
        _shown = [NSMutableArray array];
        _rates = [NSMutableDictionary dictionary];
        _names = [NSMutableDictionary dictionary];
        _opcodes = [NSMutableSet set];
        _targets = [NSMutableArray array];
    }
    return self;
}

- (void)setSetup:(nullable QLMSetup *)setup {
    _setup = setup;
    [_rates removeAllObjects];
    [_names removeAllObjects];
}

- (NSArray<QLMTrafficRow *> *)rows {
    return [_rows copy];
}

- (NSArray<QLMTrafficRow *> *)shownRows {
    return [_shown copy];
}

- (NSUInteger)rowCount {
    return _rows.count;
}

- (NSUInteger)shownCount {
    return _shown.count;
}

- (NSArray<NSNumber *> *)opcodes {
    return [_opcodes.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSArray<NSString *> *> *)targets {
    return [_targets copy];
}

#pragma mark - Names

// The design rate the setup file states for the monitor's bands, or 0.
- (double)designRateOf:(nullable NSData *)hardwareID {
    if (hardwareID == nil || self.setup == nil) {
        return 0;
    }
    NSNumber *rate = _rates[hardwareID];
    if (rate == nil) {
        double found = 0;
        for (QLMSetupGroup *group in self.setup.groups) {
            QLMSetupBand *band = [group nodeWithHardwareID:hardwareID].bands.firstObject;
            if (band != nil) {
                found = band.sampleRate;
                break;
            }
        }
        rate = @(found);
        _rates[hardwareID] = rate;
    }
    return rate.doubleValue;
}

// "Front Left, 1234567890ABCDE", or what of it is known.
- (nullable NSString *)monitorTextOf:(nullable NSData *)hardwareID {
    if (hardwareID == nil) {
        return nil;
    }
    NSString *known = _names[hardwareID];
    if (known != nil) {
        return known;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *name = [self.setup deviceWithHardwareID:hardwareID].name;
    if (name.length > 0) {
        [parts addObject:name];
    }
    for (QLMMonitorEntry *entry in self.monitorList.entries) {
        if ([entry.state.hardwareID isEqualToData:hardwareID] && entry.state.serialNumber.length > 0) {
            [parts addObject:entry.state.serialNumber];
            _names[hardwareID] = [parts componentsJoinedByString:@", "];
            break;
        }
    }
    if (parts.count == 0) {
        [parts addObject:[@"hardware ID " stringByAppendingString:QLMHexText(hardwareID)]];
    }
    return [parts componentsJoinedByString:@", "];
}

static NSString *QLMAddressText(uint8_t address) {
    char text[32];
    QLMDescribeAddress(address, text, sizeof text);
    return @(text);
}

#pragma mark - Rows

- (QLMTrafficRow *)rowFor:(QLMTrafficEntry *)entry {
    QLMTrafficRow *row = [[QLMTrafficRow alloc] init];
    row.entry = entry;
    row.timeText = QLMTrafficTimeText(entry.date);
    row.directionText = QLMTrafficDirectionText(entry.kind);
    row.bytesText = QLMHexText(entry.bytes);

    QLMMessage message = entry.message;
    QLMMessage request = entry.outgoing ? message : entry.requestMessage;
    BOOL hasRequest = request.length > 0;
    row.opcode = hasRequest ? request.payload[0] : -1;

    if (!hasRequest) {
        row.targetText = entry.kind == QLMTrafficStray ? @"from adapter 01" : @"-";
        row.targetKey = @"";
    } else {
        NSString *monitor = [self monitorTextOf:entry.hardwareID];
        NSString *address = QLMAddressText(request.address);
        row.targetText = monitor != nil ? [NSString stringWithFormat:@"%@, %@", address, monitor] : address;
        if (entry.hardwareID != nil) {
            row.targetKey = QLMHexText(entry.hardwareID);
        } else if (request.address == QLMAddressBroadcast || request.address == QLMAddressAdapter ||
                   request.address == QLMAddressMulticast) {
            row.targetKey = [NSString stringWithFormat:@"%02X", request.address];
        } else {
            row.targetKey = address;
        }
        [self noteTarget:row.targetKey title:monitor ?: address];
    }

    char text[QLMDescriptionMax];
    if (entry.outgoing) {
        QLMDescribeContext context = {entry.ceilingDecibels, [self designRateOf:entry.hardwareID]};
        QLMDescribeRequest(&message, &context, text, sizeof text);
        row.descriptionText = @(text);
    } else {
        NSString *words = nil;
        switch (entry.kind) {
        case QLMTrafficTimeout: words = @"no reply in time"; break;
        case QLMTrafficUnreadable: words = @"a reply that did not read"; break;
        default:
            QLMDescribeReply(&message, hasRequest ? &request : NULL, text, sizeof text);
            words = @(text);
            break;
        }
        if (entry.answers != 0) {
            words = [NSString stringWithFormat:@"%@, to #%llu", words, entry.answers];
        }
        row.descriptionText = words;
    }
    if (row.opcode >= 0 && ![_opcodes containsObject:@(row.opcode)]) {
        [_opcodes addObject:@(row.opcode)];
        _choicesChanges += 1;
    }
    return row;
}

- (void)noteTarget:(NSString *)key title:(NSString *)title {
    for (NSArray<NSString *> *target in _targets) {
        if ([target[0] isEqualToString:key]) {
            return;
        }
    }
    [_targets addObject:@[key, title]];
    _choicesChanges += 1;
}

- (BOOL)passes:(QLMTrafficRow *)row {
    if (self.direction == QLMTrafficDirectionOut && !row.entry.outgoing) {
        return NO;
    }
    if (self.direction == QLMTrafficDirectionIn && row.entry.outgoing) {
        return NO;
    }
    if (self.opcode != nil && row.opcode != self.opcode.integerValue) {
        return NO;
    }
    return self.targetKey == nil || [row.targetKey isEqualToString:self.targetKey];
}

- (QLMTrafficChange)addEntries:(NSArray<QLMTrafficEntry *> *)entries fromSystem:(id)system {
    if (system != _system) {
        _system = system;
        _lastNumber = 0;
    }
    QLMTrafficChange change = QLMTrafficChangeNone;
    for (QLMTrafficEntry *entry in entries) {
        if (entry.number <= _lastNumber) {
            continue;
        }
        _lastNumber = entry.number;
        QLMTrafficRow *row = [self rowFor:entry];
        [_rows addObject:row];
        if ([self passes:row]) {
            [_shown addObject:row];
            change = QLMTrafficChangeAppended;
        }
    }
    // Drops a tenth at a time, so the filter's pass runs rarely.
    if (_rows.count > _limit) {
        [_rows removeObjectsInRange:NSMakeRange(0, _rows.count - _limit + _limit / 10)];
        [self refilter];
        change = QLMTrafficChangeReset;
    }
    return change;
}

- (void)clear {
    [_rows removeAllObjects];
    [_shown removeAllObjects];
    [_opcodes removeAllObjects];
    [_targets removeAllObjects];
    _choicesChanges += 1;
}

- (void)refilter {
    [_shown removeAllObjects];
    for (QLMTrafficRow *row in _rows) {
        if ([self passes:row]) {
            [_shown addObject:row];
        }
    }
}

- (void)setDirection:(QLMTrafficDirection)direction {
    _direction = direction;
    [self refilter];
}

- (void)setOpcode:(nullable NSNumber *)opcode {
    _opcode = opcode;
    [self refilter];
}

- (void)setTargetKey:(nullable NSString *)targetKey {
    _targetKey = [targetKey copy];
    [self refilter];
}

+ (NSString *)textOfRows:(NSArray<QLMTrafficRow *> *)rows {
    NSMutableString *text = [NSMutableString stringWithString:@"time  #  direction  target  bytes  what it does\n"];
    for (QLMTrafficRow *row in rows) {
        [text appendString:row.line];
        [text appendString:@"\n"];
    }
    return text;
}

@end
