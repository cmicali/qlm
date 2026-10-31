#import <IOKit/hid/IOHIDDevice.h>

#import "QLMHIDAdapter.h"

// For the tests, which stand in for IOKit so that none opens a device.

NS_ASSUME_NONNULL_BEGIN

typedef IOReturn (^QLMHIDOpen)(IOHIDDeviceRef device, IOOptionBits options);

@interface QLMHIDAdapter ()

// IOHIDDeviceOpen.
@property (nonatomic, copy) QLMHIDOpen open;

// Opens the device once no other host has the adapter: seized, or not at
// all. Consumes the device. Nil, or why it was refused.
- (nullable NSError *)openDevice:(IOHIDDeviceRef)device;

@end

// Why IOHIDDeviceSetReport did not take a report, or nil when it did. The
// adapter closes the device on every error but QLMAdapterErrorNotTaken.
NSError *_Nullable QLMHIDWriteError(IOReturn result);

NS_ASSUME_NONNULL_END
