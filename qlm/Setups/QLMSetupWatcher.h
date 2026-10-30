#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Runs the block on the watcher's queue, `delay` from now.
typedef void (^QLMRunAfter)(NSTimeInterval delay, dispatch_block_t block);

// Watches one setup file, and calls the handler once a change to it has
// settled: a write in place, or a save that replaces the file. A change is a
// new size, modification time, or inode, so reading the file is none. The
// file may be missing at start, or vanish for a while.
//
// Call every method on the queue given. The handler runs there too.
@interface QLMSetupWatcher : NSObject

- (instancetype)initWithPath:(NSString *)path queue:(dispatch_queue_t)queue handler:(dispatch_block_t)handler;

@property (nonatomic, readonly) NSString *path;

// How long the file must stay still before the handler runs: 0.5 s. A save
// may take several writes.
@property (nonatomic) NSTimeInterval settleInterval;
// Puts off each settle check. Nil, the default, is dispatch_after on the
// queue. A test gives its virtual clock's. Set it before start.
@property (nonatomic, copy, nullable) QLMRunAfter runAfter;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
