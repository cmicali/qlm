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

NS_ASSUME_NONNULL_END
