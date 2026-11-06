#import "QLMTraffic.h"

#include <stdlib.h>

#include "QLMReport.h"

@implementation QLMTrafficEntry

- (instancetype)initWithNumber:(uint64_t)number
                          date:(NSDate *)date
                          kind:(QLMTrafficKind)kind
                         bytes:(NSData *)bytes
                       answers:(uint64_t)answers
                       request:(nullable NSData *)request
                    hardwareID:(nullable NSData *)hardwareID
               ceilingDecibels:(double)ceilingDecibels {
    self = [super init];
    if (self) {
        _number = number;
        _date = date;
        _kind = kind;
        _bytes = [bytes copy];
        _answers = answers;
        _request = [request copy];
        _hardwareID = [hardwareID copy];
        _ceilingDecibels = ceilingDecibels;
    }
    return self;
}

- (BOOL)outgoing {
    return QLMTrafficKindIsOutgoing(_kind);
}

- (QLMMessage)message {
    return QLMAdapterRecordMessage(_bytes);
}

- (QLMMessage)requestMessage {
    return QLMAdapterRecordMessage(_request);
}

@end

typedef struct {
    uint64_t number;
    CFAbsoluteTime time;
    QLMTrafficKind kind;
    uint64_t answers;
    double ceiling;
    bool hasMessage;
    bool hasHardwareID;
    uint8_t hardwareID[3];
    QLMMessage message;
} QLMTrafficSlot;

@implementation QLMTrafficRecorder {
    QLMTrafficSlot *_slots;
    NSUInteger _capacity;
    uint64_t _inFlight;  // the request awaiting its reply, or 0
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _capacity = MAX(capacity, 1u);
        _slots = calloc(_capacity, sizeof *_slots);
    }
    return self;
}

- (void)dealloc {
    free(_slots);
}

- (const QLMTrafficSlot *_Nullable)slotNumbered:(uint64_t)number {
    if (number == 0) {
        return NULL;
    }
    const QLMTrafficSlot *slot = &_slots[number % _capacity];
    return slot->number == number ? slot : NULL;
}

- (void)record:(QLMTrafficKind)kind
       message:(const QLMMessage *_Nullable)message
    hardwareID:(const uint8_t *_Nullable)hardwareID
       ceiling:(double)ceilingDecibels {
    _lastNumber += 1;
    QLMTrafficSlot *slot = &_slots[_lastNumber % _capacity];
    slot->number = _lastNumber;
    slot->time = CFAbsoluteTimeGetCurrent();
    slot->kind = kind;
    slot->answers = 0;
    slot->ceiling = ceilingDecibels;
    slot->hasMessage = message != NULL;
    if (message != NULL) {
        slot->message = *message;
    }
    slot->hasHardwareID = hardwareID != NULL;
    if (hardwareID != NULL) {
        memcpy(slot->hardwareID, hardwareID, sizeof slot->hardwareID);
    }
    switch (kind) {
    case QLMTrafficRequest:
    case QLMTrafficSync:
        _inFlight = message != NULL && QLMReportExpectsReply(message) ? _lastNumber : 0;
        break;
    case QLMTrafficTimeout:
    case QLMTrafficReply:
    case QLMTrafficNoAnswer:
    case QLMTrafficUnreadable: {
        slot->answers = _inFlight;
        const QLMTrafficSlot *request = [self slotNumbered:_inFlight];
        if (request != NULL) {
            slot->ceiling = request->ceiling;
            slot->hasHardwareID = request->hasHardwareID;
            memcpy(slot->hardwareID, request->hardwareID, sizeof slot->hardwareID);
        }
        if (kind != QLMTrafficTimeout) {
            _inFlight = 0;
        }
        break;
    }
    case QLMTrafficNotTaken:
        _inFlight = 0;
        break;
    case QLMTrafficStray:
        break;
    }
}

- (QLMTrafficEntry *)entryFor:(const QLMTrafficSlot *)slot {
    const QLMTrafficSlot *request = [self slotNumbered:slot->answers];
    return [[QLMTrafficEntry alloc] initWithNumber:slot->number
                                              date:[NSDate dateWithTimeIntervalSinceReferenceDate:slot->time]
                                              kind:slot->kind
                                             bytes:slot->hasMessage ? QLMAdapterRecord(&slot->message) : [NSData data]
                                           answers:slot->answers
                                           request:request != NULL && request->hasMessage ? QLMAdapterRecord(&request->message) : nil
                                        hardwareID:slot->hasHardwareID ? [NSData dataWithBytes:slot->hardwareID length:3] : nil
                                   ceilingDecibels:slot->ceiling];
}

- (NSArray<QLMTrafficEntry *> *)entriesAfter:(uint64_t)number {
    uint64_t oldest = _lastNumber >= _capacity ? _lastNumber - _capacity + 1 : 1;
    uint64_t first = MAX(number + 1, oldest);
    NSMutableArray<QLMTrafficEntry *> *entries = [NSMutableArray array];
    for (uint64_t n = first; n <= _lastNumber; n++) {
        [entries addObject:[self entryFor:&_slots[n % _capacity]]];
    }
    return entries;
}

@end
