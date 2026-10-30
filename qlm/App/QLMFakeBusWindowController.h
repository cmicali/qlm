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

@end

// TRAP: the fake bus keeps a lease forever. A real monitor drops its lease
// within 23 to 42 s of the host going quiet (qlm-first-discover), and System
// finds it again only by a probe, which a leased monitor ignores. So when
// the host comes back after a gap, this lapses every fake monitor's lease.
// Call it inside the bus's perform:.
void QLMFakeBusDropLeases(QLMFakeBus *bus);

NS_ASSUME_NONNULL_END
