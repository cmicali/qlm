#import <Cocoa/Cocoa.h>

#import "QLMFakeBus.h"

NS_ASSUME_NONNULL_BEGIN

// Plays the fake bus the app runs on, so the UI can be seen reacting: a turn
// of the knob, a monitor in standby, unplugged, or hot, and GLM holding the
// adapter. It touches the bus only inside perform:. On the main queue.
@interface QLMFakeBusWindowController : NSWindowController

- (instancetype)init;

// Setting it rebuilds the controls.
@property (nonatomic, nullable) QLMFakeBus *bus;

// Reads the bus again: System's power steps change the monitors too.
- (void)refresh;

// Turns the bus's knob, in tenths of a dB, as the slider does, or says why
// a turn is outside its travel.
+ (nullable NSString *)turnKnobOf:(QLMFakeBus *)bus to:(NSInteger)tenths;

@end

NS_ASSUME_NONNULL_END
