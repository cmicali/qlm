#import "QLMFakeBus.h"

#include "QLMCommands.h"
#include "QLMReplies.h"

@implementation QLMFakeMonitor

- (instancetype)initWithHardwareID:(NSData *)hardwareID serialNumber:(NSString *)serialNumber systemInfo:(NSString *)systemInfo deviceClass:(uint8_t)deviceClass {
    NSParameterAssert(hardwareID.length == 3);
    self = [super init];
    if (self) {
        _hardwareID = [hardwareID copy];
        _serialNumber = [serialNumber copy];
        _systemInfo = [systemInfo copy];
        _deviceClass = deviceClass;
        _temperature = 38;
        _on = YES;
        _present = YES;
    }
    return self;
}

@end

@implementation QLMFakeBus {
    dispatch_queue_t _queue;
    NSMutableArray<NSData *> *_sent;
}

- (instancetype)initWithMonitors:(NSArray<QLMFakeMonitor *> *)monitors {
    self = [super init];
    if (self) {
        _monitors = [monitors copy];
        _sent = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSData *> *)sentMessages {
    __block NSArray<NSData *> *sent;
    [self perform:^{
        sent = [self->_sent copy];
    }];
    return sent;
}

- (void)perform:(dispatch_block_t)block {
    dispatch_queue_t queue = _queue;
    if (queue == NULL) {
        block();
    } else {
        dispatch_sync(queue, block);
    }
}

- (void)startOnQueue:(dispatch_queue_t)queue {
    _queue = queue;
}

- (void)stop {
    _queue = NULL;
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    dispatch_queue_t queue = _queue;
    NSAssert(queue != NULL, @"send before start");

    uint8_t frame[QLMFrameMax];
    size_t length = 0;
    QLMFrameStatus status = QLMFrameEncode(&message, frame, sizeof frame, &length);
    if (status != QLMFrameOK) {
        NSError *error = [NSError errorWithDomain:QLMAdapterErrorDomain code:QLMAdapterErrorForbidden userInfo:nil];
        dispatch_async(queue, ^{
            handler(NULL, error);
        });
        return;
    }
    QLMMessage decoded;
    memset(&decoded, 0, sizeof decoded);
    QLMFrameStatus decodeStatus = QLMFrameDecode(frame, length, &decoded);
    NSAssert(decodeStatus == QLMFrameOK, @"the codec does not round-trip");
    (void)decodeStatus;

    dispatch_async(queue, ^{
        NSMutableData *record = [NSMutableData dataWithBytes:&decoded.address length:1];
        [record appendBytes:decoded.payload length:decoded.length];
        [self->_sent addObject:record];
        if (self.disconnected) {
            handler(NULL, [NSError errorWithDomain:QLMAdapterErrorDomain code:QLMAdapterErrorDisconnected userInfo:nil]);
            return;
        }
        QLMMessage reply;
        BOOL answered = [self replyTo:&decoded into:&reply];
        handler(answered ? &reply : NULL, nil);
    });
}

static void QLMFakeReply(QLMMessage *reply, const uint8_t *payload, size_t length) {
    memset(reply, 0, sizeof *reply);
    reply->address = QLMAddressReply;
    reply->length = length;
    memcpy(reply->payload, payload, length);
}

static void QLMFakeTextReply(QLMMessage *reply, NSString *text, BOOL terminated) {
    const char *utf8 = text.UTF8String;
    size_t length = strlen(utf8) + (terminated ? 1 : 0);
    uint8_t payload[QLMPayloadMax];
    NSCAssert(length + 1 <= sizeof payload, @"text too long for a frame");
    payload[0] = 0x09;
    memcpy(payload + 1, utf8, length);
    QLMFakeReply(reply, payload, 1 + length);
}

// The spec's section 9: a probe is answered by one monitor without a lease,
// an assignment by the monitor whose hardware ID it names, and a unicast by
// the monitor holding that session. Broadcasts of volume, keep-alive, and
// power get no reply. Every other unicast, the DSP block's included, gets a
// bare ack.
- (BOOL)replyTo:(const QLMMessage *)message into:(QLMMessage *)reply {
    const uint8_t *payload = message->payload;
    if (message->address == QLMAddressBroadcast || message->address == QLMAddressMulticast) {
        if (payload[0] == 0xFE) {
            for (QLMFakeMonitor *monitor in _monitors) {
                if (monitor.present && monitor.session == 0) {
                    uint8_t bytes[4] = {0x09};
                    memcpy(bytes + 1, monitor.hardwareID.bytes, 3);
                    QLMFakeReply(reply, bytes, sizeof bytes);
                    return YES;
                }
            }
            return NO;
        }
        if (payload[0] == 0x02 && message->length == 5) {
            for (QLMFakeMonitor *monitor in _monitors) {
                if (monitor.present && memcmp(monitor.hardwareID.bytes, payload + 1, 3) == 0) {
                    monitor.session = payload[4];
                    uint8_t bytes[2] = {0x09, payload[4]};
                    QLMFakeReply(reply, bytes, sizeof bytes);
                    return YES;
                }
            }
        }
        // Section 7's 3A 03: 00 powers off, 7F and 01 wake. Sessions survive
        // a power change here, a simplification: real monitors re-enumerate.
        if (payload[0] == 0x3A && message->length == 3 && payload[1] == 0x03) {
            BOOL off = payload[2] == QLMPowerStepPowerOff;
            BOOL wake = payload[2] == QLMPowerStepWakeFirst || payload[2] == QLMPowerStepWakeSecond;
            for (QLMFakeMonitor *monitor in _monitors) {
                if (monitor.present && (off || wake)) {
                    monitor.on = wake;
                }
            }
        }
        return NO;
    }

    QLMFakeMonitor *target = nil;
    for (QLMFakeMonitor *monitor in _monitors) {
        if (monitor.present && monitor.session != 0 && monitor.session == message->address) {
            target = monitor;
            break;
        }
    }
    if (target == nil) {
        return NO;
    }
    if (target.dropReplies > 0) {
        target.dropReplies -= 1;
        return NO;
    }

    switch (payload[0]) {
    case 0x08: {
        uint8_t temperature = target.temperature;
        if (!target.on) {
            // Section 8.1's standby frame.
            uint8_t bytes[] = {0x09, 0x41, temperature, 0x47, 0x02, 0x84, 0x03, 0x8E};
            QLMFakeReply(reply, bytes, sizeof bytes);
        } else if (target.deviceClass == QLMTelemetryClassSubwoofer) {
            uint8_t bytes[] = {0x09, 0x41, temperature, 0x83, 0x00, temperature, 0x42, 0x89, 0x46, 0x80,
                               0x43, 0x80, 0x45, 0x80, 0x47, 0x01, 0x84, 0x01, 0x66};
            QLMFakeReply(reply, bytes, sizeof bytes);
        } else {
            uint8_t bytes[] = {0x09, 0x41, temperature, 0x81, 0x00, temperature, 0x83, 0x00, temperature, 0x42, 0x89,
                               0x43, 0x80, 0x45, 0x80, 0x47, 0x01, 0x84, 0x02, 0xB0};
            QLMFakeReply(reply, bytes, sizeof bytes);
        }
        return YES;
    }
    case 0x19:
        QLMFakeTextReply(reply, target.serialNumber, NO);
        return YES;
    case 0x39:
        QLMFakeTextReply(reply, target.systemInfo, YES);
        return YES;
    case 0x2B:
        if (message->length >= 2) {
            target.muteValue = payload[1];
        }
        // fall through: a bare ack
    default: {
        uint8_t ack = 0x09;
        QLMFakeReply(reply, &ack, 1);
        return YES;
    }
    }
}

@end
