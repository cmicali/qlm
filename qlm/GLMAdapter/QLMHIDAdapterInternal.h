#import <IOKit/hid/IOHIDDevice.h>

#import "QLMHIDAdapter.h"

// For the tests, which stand in for IOKit so that none opens a device.

NS_ASSUME_NONNULL_BEGIN

typedef IOReturn (^QLMHIDOpen)(IOHIDDeviceRef device, IOOptionBits options);
// Hands a device just seized to System's queue, and returns its description.
typedef NSString *_Nonnull (^QLMHIDAttach)(IOHIDDeviceRef device);
// Closes a device, unless it was removed, and cancels it.
typedef void (^QLMHIDClose)(IOHIDDeviceRef device, BOOL removed);
typedef NSString *_Nullable (^QLMHIDHostCheck)(void);
// The matching for the adapter's HID device. The caller owns it.
typedef CFMutableDictionaryRef _Nonnull (^QLMHIDMatching)(void);

@interface QLMHIDAdapter ()

// IOHIDDeviceOpen.
@property (nonatomic, copy) QLMHIDOpen open;
// IOHIDDeviceSetDispatchQueue, its callbacks, and IOHIDDeviceActivate.
@property (nonatomic, copy) QLMHIDAttach attach;
// IOHIDDeviceClose and IOHIDDeviceCancel.
@property (nonatomic, copy) QLMHIDClose close;
// QLMHostCheckOtherHost, at every check before and after an open, and the
// watch's full check.
@property (nonatomic, copy) QLMHIDHostCheck hostCheck;
// QLMHostCheckAdapterClients, the watch's check each second.
@property (nonatomic, copy) QLMHIDHostCheck clientCheck;
// QLMHostCheckCreateHIDMatching. Set it before the start.
@property (nonatomic, copy) QLMHIDMatching makeMatching;

// The host watch's answer: a host refuses the adapter, and none opens it if
// it is free, at most once each second.
- (void)finishCheck:(nullable NSString *)host;
// An interest message from IOKit on the adapter.
- (void)adapterChanged;
// Opens the adapter's service if no host has it.
- (void)openIfFree;

// Opens the device once no other host has the adapter: seized, or not at
// all. Consumes the device. Nil, or why it was refused.
- (nullable NSError *)openDevice:(IOHIDDeviceRef)device;

@end

// Why IOHIDDeviceSetReport did not take a report, or nil when it did. The
// adapter closes the device on every error but QLMAdapterErrorNotTaken.
NSError *_Nullable QLMHIDWriteError(IOReturn result);

NS_ASSUME_NONNULL_END
