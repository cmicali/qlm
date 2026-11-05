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

// Reads the bus again while any of the window is on screen: System's power
// steps change the monitors too. A show, or a return into view, reads it too.
- (void)refresh;
#if DEBUG
// Draws the latest snapshot while the window is open, seen or not, for a
// debug verb that reads what the window shows.
- (void)drawWhileOpen;
#endif

@end

NS_ASSUME_NONNULL_END
