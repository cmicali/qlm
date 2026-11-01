#import <Foundation/Foundation.h>

// For System and its tests.

NS_ASSUME_NONNULL_BEGIN

// A monitor leased after a probe no monitor answered was switched on or
// woken since that probe when its wake count puts its wake no earlier than
// this before it. Then, with no group active, the snapshot says
// wokeWithoutGroup.
extern const NSTimeInterval QLMPowerOnMargin;

NS_ASSUME_NONNULL_END
