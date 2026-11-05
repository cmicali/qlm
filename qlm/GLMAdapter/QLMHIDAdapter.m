#import "QLMHIDAdapterInternal.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDDevice.h>
#import <IOKit/hid/IOHIDKeys.h>

#import "QLMHostCheck.h"
#import "QLMHostWatch.h"
#import "QLMReportLink.h"

// The adapter's HID device, its interface, and its USB device: an open of
// any of them is an open of the adapter.
enum { QLMHIDWatchedEntries = 8 };
// TRAP: qlm's own open and close send interest messages too, so a check
// that finds no host could reopen in a loop: after a write error that
// closes the device, or a seize that fails with no host to see. A reopen
// waits this long after the last try.
static const NSTimeInterval QLMHIDReopenInterval = 1;

@interface QLMHIDAdapter ()
- (void)takeArrivals;
- (void)takeTerminations;
- (void)receiveReport:(const uint8_t *)report length:(CFIndex)length result:(IOReturn)result sender:(void *)sender;
- (void)removed:(void *)sender;
@end

static void QLMHIDArrived(void *context, io_iterator_t iterator) {
    [(__bridge QLMHIDAdapter *)context takeArrivals];
}

static void QLMHIDTerminated(void *context, io_iterator_t iterator) {
    [(__bridge QLMHIDAdapter *)context takeTerminations];
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

// Any message: an open, an attempt at one while qlm holds the seize, a
// close, or a termination.
static void QLMHIDInterest(void *context, io_service_t service, natural_t type, void *argument) {
    [(__bridge QLMHIDAdapter *)context adapterChanged];
}

NSError *QLMHIDWriteError(IOReturn result) {
    if (result == kIOReturnSuccess) {
        return nil;
    }
    if (result == kIOReturnExclusiveAccess) {
        return QLMAdapterErrorMake(QLMAdapterErrorBusy, @"Another process has seized the GLM adapter.");
    }
    // TRAP: not QLMAdapterErrorTimeout, which says the frame went out and no
    // reply came. Counted so, a hang would drop monitors that still hold
    // their leases.
    if (result == kIOReturnTimeout) {
        return QLMAdapterErrorMake(QLMAdapterErrorNotTaken, @"The GLM adapter did not take the report.");
    }
    NSString *description = [NSString stringWithFormat:@"The GLM adapter did not take the report (0x%08x).", result];
    return QLMAdapterErrorMake(QLMAdapterErrorDisconnected, description);
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
    BOOL _running;
    // Keeps self alive while IOKit holds it as a callback context.
    const void *_runningSelf;
    IONotificationPortRef _port;
    io_iterator_t _arrivals;
    io_iterator_t _terminations;
    io_service_t _service;
    IOHIDDeviceRef _device;
    // One link for each arrival of the adapter, kept across closes, so that
    // a reopen knows which replies may still come. A replug is a new
    // registry entry, and gets a new link.
    QLMReportLink *_link;
    id<QLMClock> _clock;
    uint64_t _linkEntry;
    uint8_t _input[QLMReportLength];
    QLMHostWatch *_hostWatch;
    dispatch_block_t _endLaunchWatch;
    io_object_t _interests[QLMHIDWatchedEntries];
    int _interestCount;
    NSTimeInterval _lastOpenTry;  // on the clock; -INFINITY before the first
    BOOL _reopenScheduled;
    NSUInteger _reopenGeneration;  // a stop, a refusal, or a new service drops a scheduled reopen
    NSError *_problem;  // why a send fails while no device is open
    NSString *_deviceDescription;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _replyTimeout = 0.1;
        _problem = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"No GLM adapter is connected.");
        _deviceDescription = @"the GLM adapter over USB, not open";
        _lastOpenTry = -INFINITY;
        _open = ^IOReturn(IOHIDDeviceRef device, IOOptionBits options) {
            return IOHIDDeviceOpen(device, options);
        };
        __weak QLMHIDAdapter *weakSelf = self;
        _attach = ^NSString *(IOHIDDeviceRef device) {
            return [weakSelf attachDevice:device];
        };
        _close = ^(IOHIDDeviceRef device, BOOL removed) {
            if (!removed) {
                IOHIDDeviceClose(device, kIOHIDOptionsTypeSeizeDevice);
            }
            IOHIDDeviceCancel(device);
        };
        _hostCheck = ^NSString * {
            return QLMHostCheckOtherHost();
        };
        _clientCheck = ^NSString * {
            return QLMHostCheckAdapterClients();
        };
        _makeMatching = ^CFMutableDictionaryRef {
            return QLMHostCheckCreateHIDMatching();
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

    __weak QLMHIDAdapter *weakSelf = self;
    QLMHostWatch *watch = [[QLMHostWatch alloc] initWithQueue:queue clock:clock check:_hostCheck clientCheck:_clientCheck
                                                        found:^(NSString *host) {
        [weakSelf finishCheck:host];
    }];
    _hostWatch = watch;
    [watch start];
    if (_launchWatch != nil) {
        _endLaunchWatch = _launchWatch(^(NSString *executablePath) {
            [watch appChangedAtPath:executablePath];
        });
    }

    _port = IONotificationPortCreate(kIOMainPortDefault);
    IONotificationPortSetDispatchQueue(_port, queue);
    kern_return_t result = IOServiceAddMatchingNotification(_port, kIOFirstMatchNotification, _makeMatching(),
                                                            QLMHIDArrived, (__bridge void *)self, &_arrivals);
    if (result == KERN_SUCCESS) {
        [self takeArrivals];
    } else {
        NSString *description = [NSString stringWithFormat:@"IOKit did not watch for the GLM adapter (0x%08x).", result];
        _problem = QLMAdapterErrorMake(QLMAdapterErrorDisconnected, description);
    }
    // The removal callback needs an open device. After a reopen that failed,
    // none is open.
    if (IOServiceAddMatchingNotification(_port, kIOTerminatedNotification, _makeMatching(), QLMHIDTerminated,
                                         (__bridge void *)self, &_terminations) == KERN_SUCCESS) {
        [self takeTerminations];
    }
}

- (void)stop {
    if (!_running) {
        return;
    }
    _running = NO;
    [self cancelReopen];
    [_hostWatch stop];
    _hostWatch = nil;
    if (_endLaunchWatch != nil) {
        _endLaunchWatch();
        _endLaunchWatch = nil;
    }
    [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The adapter is stopped.") removed:NO];
    if (_arrivals != IO_OBJECT_NULL) {
        IOObjectRelease(_arrivals);
        _arrivals = IO_OBJECT_NULL;
    }
    if (_terminations != IO_OBJECT_NULL) {
        IOObjectRelease(_terminations);
        _terminations = IO_OBJECT_NULL;
    }
    [self forgetService];
    IONotificationPortDestroy(_port);
    _port = NULL;
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
            [self watchService];
        } else {
            IOObjectRelease(service);
        }
    }
    [self openIfFree];
}

- (void)takeTerminations {
    io_service_t service;
    while ((service = IOIteratorNext(_terminations)) != IO_OBJECT_NULL) {
        uint64_t entry = 0;
        uint64_t ours = 0;
        IORegistryEntryGetRegistryEntryID(service, &entry);
        IOObjectRelease(service);
        if (_service != IO_OBJECT_NULL && IORegistryEntryGetRegistryEntryID(_service, &ours) == KERN_SUCCESS && entry == ours) {
            [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The GLM adapter was unplugged.") removed:YES];
            [self forgetService];
        }
    }
}

- (void)forgetService {
    [self cancelReopen];
    [self unwatchService];
    if (_service != IO_OBJECT_NULL) {
        IOObjectRelease(_service);
        _service = IO_OBJECT_NULL;
    }
}

// IOKit sends an interest message to a service each time a process opens it,
// tries to, or closes it. An open of the adapter goes through its HID
// device, its USB interface, or its USB device, so each is watched, from the
// HID device up to the USB device.
- (void)watchService {
    [self unwatchService];
    io_registry_entry_t entry = _service;
    IOObjectRetain(entry);
    while (entry != IO_OBJECT_NULL && _interestCount < QLMHIDWatchedEntries) {
        io_object_t interest = IO_OBJECT_NULL;
        if (IOServiceAddInterestNotification(_port, entry, kIOGeneralInterest, QLMHIDInterest, (__bridge void *)self, &interest)
            == KERN_SUCCESS) {
            _interests[_interestCount++] = interest;
        }
        io_registry_entry_t parent = IO_OBJECT_NULL;
        BOOL top = IOObjectConformsTo(entry, "IOUSBHostDevice");
        if (top || IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) != KERN_SUCCESS) {
            parent = IO_OBJECT_NULL;
        }
        IOObjectRelease(entry);
        entry = parent;
    }
    if (entry != IO_OBJECT_NULL) {
        IOObjectRelease(entry);
    }
}

- (void)unwatchService {
    for (int i = 0; i < _interestCount; i++) {
        IOObjectRelease(_interests[i]);
    }
    _interestCount = 0;
}

- (void)adapterChanged {
    [_hostWatch adapterChanged];
}

- (void)refuse:(NSString *)host {
    [self cancelReopen];
    [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorBusy, host) removed:NO];
}

- (void)openIfFree {
    if (!_running || _device != NULL || _service == IO_OBJECT_NULL) {
        return;
    }
    NSString *host = _hostCheck();
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
    // System's reconnect opens it.
    if (_link.gaveUp) {
        return;
    }
    NSError *refusal = [self openService];
    if (refusal != nil) {
        _problem = refusal;
        return;
    }
    if (_link != nil) {
        [_link reopen];
        return;
    }
    __weak QLMHIDAdapter *weakSelf = self;
    _link = [[QLMReportLink alloc] initWithQueue:_queue clock:_clock writer:^NSError *(const uint8_t *report) {
        QLMHIDAdapter *strongSelf = weakSelf;
        return strongSelf != nil ? [strongSelf writeReport:report]
                                 : QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The adapter is gone.");
    }];
    _link.replyTimeout = _replyTimeout;
}

// Nil once the device is open, or why not.
- (nullable NSError *)openService {
    _lastOpenTry = _clock.now;
    IOHIDDeviceRef device = IOHIDDeviceCreate(kCFAllocatorDefault, _service);
    if (device == NULL) {
        return QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"IOKit did not make a HID device of the GLM adapter.");
    }
    return [self openDevice:device];
}

// Another host closes the link, as at any time. Any other failure leaves it
// given up, for System's next try, and sends still fail as it gave up.
// TRAP: a failed seize alone is no other host. qlm's own close may not have
// let go yet.
- (QLMReconnectResult)reconnect {
    if (!_link.gaveUp || _service == IO_OBJECT_NULL) {
        return QLMReconnectNotNeeded;
    }
    NSString *host = _hostCheck();
    if (host == nil) {
        if (_device != NULL) {
            [self releaseDevice:NO];
        }
        NSError *refusal = [self openService];
        if (refusal == nil) {
            [_link resync];
            return QLMReconnectReopened;
        }
        _problem = refusal;
        host = _hostCheck();
    }
    if (host != nil) {
        [self refuse:host];
        return QLMReconnectNotNeeded;
    }
    return QLMReconnectFailed;
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
    NSString *host = _hostCheck();
    if (host != nil) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeSeizeDevice);
        CFRelease(device);
        return QLMAdapterErrorMake(QLMAdapterErrorBusy, host);
    }

    _deviceDescription = _attach(device);
    _device = device;
    _problem = nil;
    return nil;
}

- (NSString *)attachDevice:(IOHIDDeviceRef)device {
    const void *context = CFBridgingRetain(self);
    IOHIDDeviceSetDispatchQueue(device, _queue);
    IOHIDDeviceRegisterInputReportCallback(device, _input, sizeof _input, QLMHIDInput, (void *)context);
    IOHIDDeviceRegisterRemovalCallback(device, QLMHIDRemoved, (void *)context);
    IOHIDDeviceSetCancelHandler(device, ^{
        CFRelease(device);
        CFRelease(context);
    });
    IOHIDDeviceActivate(device);
    NSNumber *location = QLMHIDNumberProperty(device, CFSTR(kIOHIDLocationIDKey));
    return [NSString stringWithFormat:@"%@ by %@ over USB, serial %@, location 0x%08x, seized",
                                      QLMHIDStringProperty(device, CFSTR(kIOHIDProductKey)) ?: @"?",
                                      QLMHIDStringProperty(device, CFSTR(kIOHIDManufacturerKey)) ?: @"?",
                                      QLMHIDStringProperty(device, CFSTR(kIOHIDSerialNumberKey)) ?: @"?", location.unsignedIntValue];
}

// A link that gave up stays open across a failed reopen, so it closes here
// too.
- (void)closeWithError:(NSError *)error removed:(BOOL)removed {
    _problem = error;
    if (_device == NULL && !_link.gaveUp) {
        return;
    }
    [_link closeWithError:error];
    if (_device != NULL) {
        [self releaseDevice:removed];
    }
}

// Closes the device, and leaves the link to the caller.
- (void)releaseDevice:(BOOL)removed {
    IOHIDDeviceRef device = _device;
    _device = NULL;
    _deviceDescription = removed ? @"the GLM adapter over USB, unplugged" : @"the GLM adapter over USB, closed";
    _close(device, removed);
}

- (void)removed:(void *)sender {
    if (sender != _device) {
        return;
    }
    [self closeWithError:QLMAdapterErrorMake(QLMAdapterErrorDisconnected, @"The GLM adapter was unplugged.") removed:YES];
    [self forgetService];
}

#pragma mark - Watching for another host

// The host watch's answer. TRAP: the seize keeps GLM from opening the
// adapter while qlm holds it, so the watch is the rule that qlm lets go
// when GLM launches, and a net under the seize.
- (void)finishCheck:(nullable NSString *)host {
    if (!_running) {
        return;
    }
    if (host != nil) {
        [self refuse:host];
    } else {
        [self reopenIfFree];
    }
}

- (void)cancelReopen {
    _reopenGeneration += 1;
    _reopenScheduled = NO;
}

// TRAP: openIfFree scans every process before it reads the link, so a
// reopen that could not open goes no further. Else each second's client
// check would run the scan on System's queue.
- (BOOL)canReopen {
    return _device == NULL && _service != IO_OBJECT_NULL && _link.failure == nil && !_link.gaveUp;
}

- (void)reopenIfFree {
    if (![self canReopen]) {
        return;
    }
    NSTimeInterval wait = _lastOpenTry + QLMHIDReopenInterval - _clock.now;
    if (wait <= 0) {
        _lastOpenTry = _clock.now;
        [self openIfFree];
        return;
    }
    if (_reopenScheduled) {
        return;
    }
    _reopenScheduled = YES;
    NSUInteger generation = _reopenGeneration;
    __weak QLMHIDAdapter *weakSelf = self;
    [_clock after:wait queue:_queue run:^{
        QLMHIDAdapter *strongSelf = weakSelf;
        if (strongSelf == nil || generation != strongSelf->_reopenGeneration) {
            return;
        }
        strongSelf->_reopenScheduled = NO;
        if (strongSelf->_running) {
            [strongSelf reopenIfFree];
        }
    }];
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
    NSError *error = QLMHIDWriteError(IOHIDDeviceSetReport(_device, kIOHIDReportTypeOutput, 0, report, QLMReportLength));
    if (error == nil || error.code == QLMAdapterErrorNotTaken) {
        return error;
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
    [self sendMessage:message rewrite:nil replyHandler:handler];
}

- (void)sendMessage:(QLMMessage)message rewrite:(nullable QLMAdapterRewrite)rewrite replyHandler:(QLMAdapterReplyHandler)handler {
    dispatch_queue_t queue = _queue;
    NSAssert(queue != NULL, @"send before start");
    if (_device != NULL || _link.gaveUp) {
        [_link sendMessage:message rewrite:rewrite replyHandler:handler];
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
