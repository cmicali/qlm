#import "QLMFakeBus.h"

#include "QLMCommands.h"
#include "QLMReplies.h"

@implementation QLMFakeMonitor {
    NSTimeInterval _stepsSentAt;  // when a frame last carried 8A, or NAN
}

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
        _stepsSentAt = NAN;
    }
    return self;
}

- (void)setWokeAt:(NSNumber *)wokeAt {
    _wokeAt = wokeAt;
    _stepsSentAt = NAN;
}

// 49, and 8A when due, before and after the frame's closing 84, which is
// its last three bytes.
- (void)putWakeCountInto:(NSMutableData *)frame at:(NSTimeInterval)now {
    if (_wokeAt == nil) {
        return;
    }
    NSUInteger seconds = (NSUInteger)MAX(0, floor(now - _wokeAt.doubleValue));
    const uint8_t count[2] = {0x49, (uint8_t)(seconds % 256)};
    [frame replaceBytesInRange:NSMakeRange(frame.length - 3, 0) withBytes:count length:sizeof count];
    if (isnan(_stepsSentAt) || now - _stepsSentAt >= 30) {
        _stepsSentAt = now;
        const uint8_t steps[3] = {0x8A, (uint8_t)(seconds / 256 >> 8), (uint8_t)(seconds / 256)};
        [frame appendBytes:steps length:sizeof steps];
    }
}

@end

@implementation QLMFakeBus {
    dispatch_queue_t _queue;
    id<QLMClock> _clock;
    NSMutableArray<NSData *> *_sent;
}

- (instancetype)initWithMonitors:(NSArray<QLMFakeMonitor *> *)monitors {
    self = [super init];
    if (self) {
        _monitors = [monitors copy];
        _sent = [NSMutableArray array];
        _recordsSentMessages = YES;
        // The shape of the adapter's own replies in captures/startup-idle.
        _adapterSystemInfo = @"c-0;model-GLM Adapter;ver-1.4.0.6113;hw-0.0.202;build-2025.05.19.s  ";
        _adapterSerialNumber = @"H00000F001";
        _knobTenths = @(-1004);
    }
    return self;
}

- (NSString *)deviceDescription {
    return [NSString stringWithFormat:@"a fake bus of %lu monitors", (unsigned long)_monitors.count];
}

+ (instancetype)demoBusWithSubwoofer:(BOOL)withSubwoofer {
    const uint8_t leftID[3] = {0x11, 0x22, 0x33};
    const uint8_t rightID[3] = {0x44, 0x55, 0x66};
    QLMFakeMonitor *left = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:leftID length:3]
                                                        serialNumber:@"8330apm21001234"
                                                          systemInfo:@"c-1;model-8330A;ver-1.14.7"
                                                         deviceClass:QLMTelemetryClassTwoWay];
    left.temperature = 38;
    QLMFakeMonitor *right = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:rightID length:3]
                                                         serialNumber:@"8330apm21005678"
                                                           systemInfo:@"c-1;model-8330A;ver-1.14.7"
                                                          deviceClass:QLMTelemetryClassTwoWay];
    right.temperature = 41;
    NSMutableArray<QLMFakeMonitor *> *monitors = [NSMutableArray arrayWithObjects:left, right, nil];
    if (withSubwoofer) {
        const uint8_t subID[3] = {0x77, 0x88, 0x99};
        QLMFakeMonitor *sub = [[QLMFakeMonitor alloc] initWithHardwareID:[NSData dataWithBytes:subID length:3]
                                                           serialNumber:@"7350apm21009999"
                                                             systemInfo:@"c-1;model-7350A;ver-1.14.7"
                                                            deviceClass:QLMTelemetryClassSubwoofer];
        sub.temperature = 33;
        [monitors addObject:sub];
    }
    return [[self alloc] initWithMonitors:monitors];
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

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    _queue = queue;
    _clock = clock;
}

- (void)stop {
    _queue = NULL;
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    dispatch_queue_t queue = _queue;
    NSAssert(queue != NULL, @"send before start");

    uint8_t report[QLMReportLength];
    NSError *refusal = nil;
    if (!QLMAdapterPackReport(&message, report, &refusal)) {
        [_clock async:queue run:^{
            handler(NULL, refusal);
        }];
        return;
    }

    [_clock async:queue run:^{
        NSString *busy = self.busyReason;
        if (busy != nil) {
            handler(NULL, QLMAdapterErrorMake(QLMAdapterErrorBusy, busy));
            return;
        }
        if (self.recordsSentMessages) {
            [self->_sent addObject:QLMAdapterRecord(&message)];
        }
        if (self.disconnected) {
            handler(NULL, [NSError errorWithDomain:QLMAdapterErrorDomain code:QLMAdapterErrorDisconnected userInfo:nil]);
            return;
        }
        QLMMessage reply;
        BOOL answered = [self replyTo:&message into:&reply];
        handler(answered ? &reply : NULL, nil);
    }];
}

// A status tag and its 4-byte value, big-endian.
static size_t QLMFakePutField(uint8_t *bytes, size_t length, uint8_t tag, uint32_t value) {
    bytes[length] = tag;
    bytes[length + 1] = (uint8_t)(value >> 24);
    bytes[length + 2] = (uint8_t)(value >> 16);
    bytes[length + 3] = (uint8_t)(value >> 8);
    bytes[length + 4] = (uint8_t)value;
    return length + 5;
}

static void QLMFakeTextReply(QLMMessage *reply, NSString *text, BOOL terminated) {
    const char *utf8 = text.UTF8String;
    size_t length = strlen(utf8) + (terminated ? 1 : 0);
    uint8_t payload[QLMPayloadMax];
    NSCAssert(length + 1 <= sizeof payload, @"text too long for a frame");
    payload[0] = 0x09;
    memcpy(payload + 1, utf8, length);
    *reply = QLMMessageMake(QLMAddressReply, payload, 1 + length);
}

// docs/adapter-status.md: 01 08 gets the status fields, with the mic's
// readings and the knob's position when each is in; 01 39 and 01 19 01 the
// adapter's identity. Any other message to 01 gets a bare ack, as 01 2B does.
- (BOOL)adapterReplyTo:(const QLMMessage *)message into:(QLMMessage *)reply {
    if (_adapterDropReplies > 0) {
        _adapterDropReplies -= 1;
        return NO;
    }
    switch (message->payload[0]) {
    case 0x08: {
        uint8_t bytes[QLMPayloadMax] = {0x09};
        size_t length = 1;
        if (_micIn || _micDE != nil || _micDD != nil) {
            bytes[length++] = 0x32;
            bytes[length++] = 0x34;
            if (_micDE != nil) {
                length = QLMFakePutField(bytes, length, 0xDE, _micDE.unsignedIntValue);
            }
            if (_micDD != nil) {
                length = QLMFakePutField(bytes, length, 0xDD, _micDD.unsignedIntValue);
            }
        } else {
            bytes[length++] = 0x33;
        }
        if (_knobTenths != nil) {
            bytes[length++] = 0x30;
            bytes[length++] = 0x36;
            length = QLMFakePutField(bytes, length, 0xDF, (uint32_t)_knobTenths.intValue);
        } else {
            bytes[length++] = 0x31;
        }
        *reply = QLMMessageMake(QLMAddressReply, bytes, length);
        return YES;
    }
    case 0x19:
        QLMFakeTextReply(reply, _adapterSerialNumber, NO);
        return YES;
    case 0x39:
        QLMFakeTextReply(reply, _adapterSystemInfo, YES);
        return YES;
    default: {
        uint8_t ack = 0x09;
        *reply = QLMMessageMake(QLMAddressReply, &ack, 1);
        return YES;
    }
    }
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
                    *reply = QLMMessageMake(QLMAddressReply, bytes, sizeof bytes);
                    return YES;
                }
            }
            return NO;
        }
        if (payload[0] == 0x02 && message->length == 5) {
            for (QLMFakeMonitor *monitor in _monitors) {
                if (monitor.present && memcmp(monitor.hardwareID.bytes, payload + 1, 3) == 0) {
                    monitor.session = payload[4];
                    if (monitor.dropReplies > 0) {
                        monitor.dropReplies -= 1;
                        return NO;
                    }
                    uint8_t bytes[2] = {0x09, payload[4]};
                    *reply = QLMMessageMake(QLMAddressReply, bytes, sizeof bytes);
                    return YES;
                }
            }
        }
        // Section 7's 3A 03: 00 powers off, 7F and 01 wake. Sessions survive
        // a power change here, a simplification: real monitors re-enumerate.
        if (payload[0] == 0x3A && message->length == 3 && payload[1] == 0x03) {
            BOOL off = payload[2] == QLMPowerStepPowerOff;
            BOOL wake = payload[2] == QLMPowerStepWakeFirst || payload[2] == QLMPowerStepWakeSecond;
            if (off || wake) {
                for (QLMFakeMonitor *monitor in _monitors) {
                    if (monitor.present) {
                        if (wake && !monitor.on && monitor.wokeAt != nil) {
                            monitor.wokeAt = @(_clock.now);
                        }
                        monitor.on = wake;
                    }
                }
            }
        }
        return NO;
    }
    if (message->address == QLMAddressAdapter) {
        return [self adapterReplyTo:message into:reply];
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
            *reply = QLMMessageMake(QLMAddressReply, bytes, sizeof bytes);
        } else {
            NSMutableData *frame;
            if (target.deviceClass == QLMTelemetryClassSubwoofer) {
                uint8_t bytes[] = {0x09, 0x41, temperature, 0x83, 0x00, temperature, 0x42, 0x89, 0x46, 0x80,
                                   0x43, 0x80, 0x45, 0x80, 0x47, 0x01, 0x84, 0x01, 0x66};
                frame = [NSMutableData dataWithBytes:bytes length:sizeof bytes];
            } else {
                uint8_t bytes[] = {0x09, 0x41, temperature, 0x81, 0x00, temperature, 0x83, 0x00, temperature, 0x42, 0x89,
                                   0x43, 0x80, 0x45, 0x80, 0x47, 0x01, 0x84, 0x02, 0xB0};
                frame = [NSMutableData dataWithBytes:bytes length:sizeof bytes];
            }
            [target putWakeCountInto:frame at:_clock.now];
            *reply = QLMMessageMake(QLMAddressReply, frame.bytes, frame.length);
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
        *reply = QLMMessageMake(QLMAddressReply, &ack, 1);
        return YES;
    }
    }
}

@end
