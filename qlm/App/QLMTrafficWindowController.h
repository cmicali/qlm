#import <Cocoa/Cocoa.h>

#import "QLMSystem.h"
#import "QLMTrafficLog.h"

NS_ASSUME_NONNULL_BEGIN

// The window with every frame between qlm and the GLM adapter, both ways,
// as it happens, with each frame's bytes and what it does. It only reads:
// it sends nothing, and changes nothing System sends. It takes System's
// traffic only while it is open, and draws only while it is seen. On the
// main queue.
@interface QLMTrafficWindowController : NSWindowController

- (instancetype)initWithMonitorList:(QLMMonitorList *)monitorList;

// Setting it takes the new System's traffic while the window is open.
@property (nonatomic, nullable) QLMSystem *system;
@property (nonatomic, nullable) QLMSetup *setup;
@property (nonatomic, readonly) QLMTrafficLog *log;
// Shown and not closed, minimized or not. It takes System's traffic then.
@property (nonatomic, readonly, getter=isOpen) BOOL open;
// The rows the table draws. While paused, they hold still.
@property (nonatomic, readonly) NSArray<QLMTrafficRow *> *shown;

// Paused, the list holds still, filters and all. The frames still
// arrive, and show at once on resume.
@property (nonatomic) BOOL paused;
- (void)clear;

// Each filter as its popup sets it, and the popup with it. The opcode or
// target must be one the popup offers, else the reply is why not.
- (void)filterDirection:(QLMTrafficDirection)direction;
- (nullable NSString *)filterOpcode:(nullable NSNumber *)opcode;
- (nullable NSString *)filterTarget:(nullable NSString *)targetKey;

#if DEBUG
// Draws the latest rows while the window is open, seen or not, for a debug
// verb that reads what the window shows.
- (void)drawWhileOpen;
#endif

@end

NS_ASSUME_NONNULL_END
