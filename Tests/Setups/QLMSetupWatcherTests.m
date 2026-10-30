#import <XCTest/XCTest.h>

#import "QLMSetupWatcher.h"

// No capture names how GLM saves a setup file, so both kinds of save are
// covered: a write in place, and a save that replaces the file. The watcher
// hears the file system, so these tests run in real time. They wait for each
// change with a generous deadline, and a slow host can only make one too many
// go unseen.
@interface QLMSetupWatcherTests : XCTestCase
@property (nonatomic) NSString *folder;
@property (nonatomic) NSString *path;
@property (nonatomic) NSUInteger changes;
@property (nonatomic, nullable) QLMSetupWatcher *watcher;
@end

@implementation QLMSetupWatcherTests

- (void)setUp {
    self.folder = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:self.folder withIntermediateDirectories:YES attributes:nil error:NULL];
    self.path = [self.folder stringByAppendingPathComponent:@"Main.sam"];
    [self write:@"first" atomically:NO];
}

- (void)tearDown {
    [self.watcher stop];
    [NSFileManager.defaultManager removeItemAtPath:self.folder error:NULL];
}

- (void)startWatching {
    __weak QLMSetupWatcherTests *weakSelf = self;
    self.watcher = [[QLMSetupWatcher alloc] initWithPath:self.path queue:dispatch_get_main_queue() handler:^{
        weakSelf.changes += 1;
    }];
    self.watcher.settleInterval = 0.05;
    [self.watcher start];
}

- (void)write:(NSString *)text atomically:(BOOL)atomically {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([data writeToFile:self.path options:atomically ? NSDataWritingAtomic : 0 error:NULL]);
}

// Runs the main queue past the settle interval, with time to spare.
- (void)settle {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:self.watcher.settleInterval + 0.25]];
}

// Runs the main queue until the handler has run `count` times in all, then
// settles, so one change too many would show.
- (void)waitForChanges:(NSUInteger)count {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (self.changes < count && [deadline timeIntervalSinceNow] > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    [self settle];
    XCTAssertEqual(self.changes, count);
}

- (void)testWriteInPlace {
    [self startWatching];
    [self write:@"second" atomically:NO];
    [self waitForChanges:1];
}

- (void)testSaveThatReplacesTheFile {
    [self startWatching];
    [self write:@"second" atomically:YES];
    [self waitForChanges:1];
    // The new file is watched in turn.
    [self write:@"third" atomically:YES];
    [self waitForChanges:2];
    [self write:@"fourth, in place" atomically:NO];
    [self waitForChanges:3];
}

// The writes all land before the main queue, the watcher's, runs again, so
// it hears them as one burst. The default settle interval leaves the file
// system time to report them all.
- (void)testWritesCloseTogetherMakeOneChange {
    [self startWatching];
    self.watcher.settleInterval = 0.5;
    [self write:@"a" atomically:NO];
    [self write:@"bb" atomically:YES];
    [self write:@"ccc" atomically:NO];
    [self waitForChanges:1];
}

- (void)testReadingIsNoChange {
    [self startWatching];
    XCTAssertNotNil([NSData dataWithContentsOfFile:self.path]);
    [self settle];
    XCTAssertEqual(self.changes, 0u);
}

- (void)testAnotherFileInTheFolderIsNoChange {
    [self startWatching];
    [[@"other" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[self.folder stringByAppendingPathComponent:@"Other.sam"]
                                                           atomically:YES];
    [self settle];
    XCTAssertEqual(self.changes, 0u);
}

- (void)testFileThatComesBack {
    [self startWatching];
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtPath:self.path error:NULL]);
    [self settle];
    XCTAssertEqual(self.changes, 0u);
    [self write:@"back" atomically:NO];
    [self waitForChanges:1];
}

- (void)testFileMissingAtStart {
    XCTAssertTrue([NSFileManager.defaultManager removeItemAtPath:self.path error:NULL]);
    [self startWatching];
    [self write:@"new" atomically:YES];
    [self waitForChanges:1];
}

- (void)testStopEndsTheCalls {
    [self startWatching];
    [self.watcher stop];
    [self write:@"second" atomically:NO];
    [self settle];
    XCTAssertEqual(self.changes, 0u);
}

@end
