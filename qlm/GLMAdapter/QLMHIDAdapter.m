#import "QLMHIDAdapterInternal.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDDevice.h>
#import <IOKit/hid/IOHIDKeys.h>

#import "QLMHostCheck.h"
#import "QLMReportLink.h"

static const NSTimeInterval QLMHIDWatchInterval = 1.0;

@interface QLMHIDAdapter ()
- (void)takeArrivals;
- (void)receiveReport:(const uint8_t *)report length:(CFIndex)length result:(IOReturn)result sender:(void *)sender;
- (void)removed:(void *)sender;
@end

static void QLMHIDArrived(void *context, io_iterator_t iterator) {
    [(__bridge QLMHIDAdapter *)context takeArrivals];
}

static void QLMHIDInput(void *context, IOReturn result, void *sender, IOHIDReportType type, uint32_t reportID, uint8_t *report,
                        CFIndex length) {
    if (type == kIOHIDReportTypeInput) {
        [(__bridge QLMHIDAdapter *)context receiveReport:report length:length result:result sender:sender];
    }
}

static void QLMHIDRemoved(void *context, IOReturn result, void *sender) {
    [(__bridge QLMHIDAdapter *)context removed:sender];
}

static NSString *_Nullable QLMHIDStringProperty(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    return value != NULL && CFGetTypeID(value) == CFStringGetTypeID() ? (__bridge NSString *)value : nil;
}

static NSNumber *_Nullable QLMHIDNumberProperty(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    return value != NULL && CFGetTypeID(value) == CFNumberGetTypeID() ? (__bridge NSNumber *)value : nil;
}

@implementation QLMHIDAdapter {
    dispatch_queue_t _queue;
    dispatch_queue_t _checkQueue;
    BOOL _running;
    BOOL _checking;
    // Keeps self alive while IOKit holds it as a callback context.
    const void *_runningSelf;
    IONotificationPortRef _port;
    io_iterator_t _arrivals;
    io_service_t _service;
    IOHIDDeviceRef _device;
    // One link for each arrival of the adapter, kept across closes, so that
    // a reopen knows which replies may still come. A replug is a new
    // registry entry, and gets a new link.
    QLMReportLink *_link;
    id<QLMClock> _clock;
    uint64_t _linkEntry;
    uint8_t _input[QLMReportLength];
    id<QLMTimer> _watch;
    NSError *_problem;  // why a send fails while no device is open
    NSString *_deviceDescription;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _replyTimeout = 0.1;
        _checkQueue = dispatch_queue_create("com.commonwealthrecordings.qlm.hostcheck", DISPATCH_QUEUE_SERIAL);
        _problem = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is connected.");
        _deviceDescription = @"the GLM adapter over USB, not open";
        _open = ^IOReturn(IOHIDDeviceRef device, IOOptionBits options) {
            return IOHIDDeviceOpen(device, options);
        };
    }
    return self;
}

- (BOOL)seized {
    return _device != NULL;
}

- (NSString *)deviceDescription {
    return _deviceDescription;
}

- (void)setReplyTimeout:(NSTimeInterval)replyTimeout {
    _replyTimeout = replyTimeout;
    _link.replyTimeout = replyTimeout;
}

#pragma mark - Lifecycle

- (void)startOnQueue:(dispatch_queue_t)queue clock:(id<QLMClock>)clock {
    if (_running) {
        return;
    }
    _queue = queue;
    _clock = clock;
    _running = YES;
    _runningSelf = CFBridgingRetain(self);
    _problem = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is connected.");

    _port = IONotificationPortCreate(kIOMainPortDefault);
    IONotificationPortSetDispatchQueue(_port, queue);
    kern_return_t result = IOServiceAddMatchingNotification(_port, kIOFirstMatchNotification, QLMHostCheckCreateHIDMatching(),
                                                            QLMHIDArrived, (__bridge void *)self, &_arrivals);
    if (result == KERN_SUCCESS) {
        [self takeArrivals];
    } else {
        NSString *description = [NSString stringWithFormat:@"IOKit did not watch for the GLM adapter (0x%08x).", result];
        _problem = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, description);
    }

    __weak QLMHIDAdapter *weakSelf = self;
    _watch = [_clock every:QLMHIDWatchInterval queue:queue run:^{
        [weakSelf checkHosts];
    }];
}

- (void)stop {
    if (!_running) {
        return;
    }
    _running = NO;
    [_watch cancel];
    _watch = nil;
    [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The adapter is stopped.") removed:NO];
    if (_arrivals != IO_OBJECT_NULL) {
        IOObjectRelease(_arrivals);
        _arrivals = IO_OBJECT_NULL;
    }
    IONotificationPortDestroy(_port);
    _port = NULL;
    [self forgetService];
    const void *runningSelf = _runningSelf;
    _runningSelf = NULL;
    dispatch_async(_queue, ^{
        CFRelease(runningSelf);
    });
}

#pragma mark - Finding and opening

// While none is open, the newest adapter replaces one that would not open.
- (void)takeArrivals {
    io_service_t service;
    while ((service = IOIteratorNext(_arrivals)) != IO_OBJECT_NULL) {
        if (_device == NULL) {
            [self forgetService];
            _service = service;
        } else {
            IOObjectRelease(service);
        }
    }
    [self openIfFree];
}

- (void)forgetService {
    if (_service != IO_OBJECT_NULL) {
        IOObjectRelease(_service);
        _service = IO_OBJECT_NULL;
    }
}

- (void)refuse:(NSString *)host {
    NSError *error = QLMAdapterErrorMake(QLMAdapterErrorBusy, host);
    if (_device != NULL) {
        [self closeWithError:error removed:NO];
    } else {
        _problem = error;
    }
}

- (void)openIfFree {
    if (!_running || _device != NULL || _service == IO_OBJECT_NULL) {
        return;
    }
    NSString *host = QLMHostCheckOtherHost();
    if (host != nil) {
        [self refuse:host];
        return;
    }
    uint64_t entry = 0;
    IORegistryEntryGetRegistryEntryID(_service, &entry);
    if (entry != _linkEntry) {
        _link = nil;
        _linkEntry = entry;
    }
    if (_link.failure != nil) {
        _problem = _link.failure;
        return;
    }
    IOHIDDeviceRef device = IOHIDDeviceCreate(kCFAllocatorDefault, _service);
    if (device == NULL) {
        _problem = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"IOKit did not make a HID device of the GLM adapter.");
        return;
    }
    NSError *refusal = [self openDevice:device];
    if (refusal != nil) {
        _problem = refusal;
    }
}

// TRAP: never fall back to a shared open. GLM could then open the adapter
// too, and drive the bus alongside qlm until the next host check.
- (NSError *)openDevice:(IOHIDDeviceRef)device {
    IOReturn result = _open(device, kIOHIDOptionsTypeSeizeDevice);
    if (result != kIOReturnSuccess) {
        CFRelease(device);
        if (result == kIOReturnExclusiveAccess) {
            return QLMAdapterErrorMake(QLMAdapterErrorBusy, @"Another process has seized the GLM adapter.");
        }
        NSString *description =
            [NSString stringWithFormat:@"qlm could not seize the GLM adapter (0x%08x). It opens the adapter only seized.", result];
        return QLMAdapterErrorMake(QLMAdapterErrorBusy, description);
    }
    // GLM may have started between the check and the open.
    NSString *host = QLMHostCheckOtherHost();
    if (host != nil) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeSeizeDevice);
        CFRelease(device);
        return QLMAdapterErrorMake(QLMAdapterErrorBusy, host);
    }

    const void *context = CFBridgingRetain(self);
    IOHIDDeviceSetDispatchQueue(device, _queue);
    IOHIDDeviceRegisterInputReportCallback(device, _input, sizeof _input, QLMHIDInput, (void *)context);
    IOHIDDeviceRegisterRemovalCallback(device, QLMHIDRemoved, (void *)context);
    IOHIDDeviceSetCancelHandler(device, ^{
        CFRelease(device);
        CFRelease(context);
    });
    IOHIDDeviceActivate(device);

    _device = device;
    _problem = nil;
    NSNumber *location = QLMHIDNumberProperty(device, CFSTR(kIOHIDLocationIDKey));
    _deviceDescription = [NSString stringWithFormat:@"%@ by %@ over USB, serial %@, location 0x%08x, seized",
                          QLMHIDStringProperty(device, CFSTR(kIOHIDProductKey)) ?: @"?",
                          QLMHIDStringProperty(device, CFSTR(kIOHIDManufacturerKey)) ?: @"?",
                          QLMHIDStringProperty(device, CFSTR(kIOHIDSerialNumberKey)) ?: @"?", location.unsignedIntValue];

    if (_link != nil) {
        [_link reopen];
        return nil;
    }
    __weak QLMHIDAdapter *weakSelf = self;
    _link = [[QLMReportLink alloc] initWithQueue:_queue clock:_clock writer:^NSError *(const uint8_t *report) {
        QLMHIDAdapter *strongSelf = weakSelf;
        return strongSelf != nil ? [strongSelf writeReport:report]
                                 : QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The adapter is gone.");
    }];
    _link.replyTimeout = _replyTimeout;
    return nil;
}

- (void)closeWithError:(NSError *)error removed:(BOOL)removed {
    _problem = error;
    if (_device == NULL) {
        return;
    }
    IOHIDDeviceRef device = _device;
    _device = NULL;
    [_link closeWithError:error];
    _deviceDescription = removed ? @"the GLM adapter over USB, unplugged" : @"the GLM adapter over USB, closed";
    if (!removed) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeSeizeDevice);
    }
    IOHIDDeviceCancel(device);
}

- (void)removed:(void *)sender {
    if (sender != _device) {
        return;
    }
    [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The GLM adapter was unplugged.") removed:YES];
    [self forgetService];
}

#pragma mark - Watching for another host

// The process scan takes milliseconds, so it runs off System's queue.
- (void)checkHosts {
    if (!_running || _checking) {
        return;
    }
    _checking = YES;
    dispatch_queue_t queue = _queue;
    __weak QLMHIDAdapter *weakSelf = self;
    dispatch_async(_checkQueue, ^{
        NSString *host = QLMHostCheckOtherHost();
        dispatch_async(queue, ^{
            [weakSelf finishCheck:host];
        });
    });
}

- (void)finishCheck:(nullable NSString *)host {
    _checking = NO;
    if (!_running) {
        return;
    }
    if (host != nil) {
        [self refuse:host];
    } else {
        [self openIfFree];
    }
}

#pragma mark - Reports

// A device is open only seized, so a report goes out only while qlm owns the
// adapter.
// TRAP: IOHIDDeviceSetReport blocks System's queue until the report is out,
// up to the device's RequestTimeout of 5 s if the adapter stops taking them.
- (NSError *_Nullable)writeReport:(const uint8_t *)report {
    if (_device == NULL) {
        return _problem ?: QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is open.");
    }
    IOReturn result = IOHIDDeviceSetReport(_device, kIOHIDReportTypeOutput, 0, report, QLMReportLength);
    if (result == kIOReturnSuccess) {
        return nil;
    }
    NSError *error = nil;
    if (result == kIOReturnExclusiveAccess) {
        error = QLMAdapterErrorMake(QLMAdapterErrorBusy, @"Another process has seized the GLM adapter.");
    } else if (result == kIOReturnTimeout) {
        return QLMAdapterErrorMake(QLMAdapterErrorTimeout, @"The GLM adapter did not take the report.");
    } else {
        NSString *description = [NSString stringWithFormat:@"The GLM adapter did not take the report (0x%08x).", result];
        error = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, description);
    }
    __weak QLMHIDAdapter *weakSelf = self;
    dispatch_async(_queue, ^{
        [weakSelf closeWithError:error removed:NO];
    });
    return error;
}

- (void)receiveReport:(const uint8_t *)report length:(CFIndex)length result:(IOReturn)result sender:(void *)sender {
    if (sender != _device || result != kIOReturnSuccess || length < 0) {
        return;
    }
    [_link receiveReport:report length:(size_t)length];
}

- (void)sendMessage:(QLMMessage)message replyHandler:(QLMAdapterReplyHandler)handler {
    dispatch_queue_t queue = _queue;
    NSAssert(queue != NULL, @"send before start");
    if (_device != NULL) {
        [_link sendMessage:message replyHandler:handler];
        return;
    }
    // Through the allowlist even so, so a refusal reads the same either way.
    uint8_t report[QLMReportLength];
    NSError *error = nil;
    if (QLMAdapterPackReport(&message, report, &error)) {
        error = _problem ?: QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is open.");
    }
    dispatch_async(queue, ^{
        handler(NULL, error);
    });
}

@end
