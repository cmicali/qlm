#import "QLMTestSupport.h"

#import "QLMSetupReader.h"

NSData *QLMBytes(const uint8_t *bytes, size_t length) {
    return [NSData dataWithBytes:bytes length:length];
}

NSString *QLMFixturePath(NSString *name) {
    NSString *tests = [@(__FILE__) stringByDeletingLastPathComponent];
    return [[tests stringByAppendingPathComponent:@"Setups/Fixtures"] stringByAppendingPathComponent:name];
}

static NSString *QLMCapturesDirectory(void) {
    NSString *tests = [@(__FILE__) stringByDeletingLastPathComponent];
    return [[tests stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"captures"];
}

NSArray<NSString *> *QLMCaptureScenarios(void) {
    NSString *directory = QLMCapturesDirectory();
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *scenarios = [NSMutableArray array];
    for (NSString *name in [manager contentsOfDirectoryAtPath:directory error:NULL]) {
        NSString *reports = [[directory stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"reports.txt"];
        if ([manager fileExistsAtPath:reports]) {
            [scenarios addObject:name];
        }
    }
    return [scenarios sortedArrayUsingSelector:@selector(compare:)];
}

QLMCapture *QLMReadCapture(NSString *scenario, NSError **error) {
    static NSMutableDictionary<NSString *, QLMCapture *> *captures;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        captures = [NSMutableDictionary dictionary];
    });
    @synchronized(captures) {
        QLMCapture *capture = captures[scenario];
        if (capture == nil) {
            NSString *path = [[QLMCapturesDirectory() stringByAppendingPathComponent:scenario] stringByAppendingPathComponent:@"reports.txt"];
            capture = [QLMCapture captureWithContentsOfFile:path error:error];
            if (capture != nil) {
                captures[scenario] = capture;
            }
        }
        return capture;
    }
}

@implementation XCTestCase (QLMAdapter)

- (BOOL)qlm_send:(QLMMessage)message to:(id<QLMAdapter>)adapter queue:(dispatch_queue_t)queue reply:(QLMMessage *)reply
           error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL answered = NO;
    __block NSError *failure = nil;
    dispatch_async(queue, ^{
        [adapter sendMessage:message replyHandler:^(const QLMMessage *received, NSError *sendError) {
            if (received != NULL) {
                answered = YES;
                if (reply != NULL) {
                    *reply = *received;
                }
            }
            failure = sendError;
            dispatch_semaphore_signal(done);
        }];
    });
    XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    if (error != NULL) {
        *error = failure;
    }
    return answered;
}

@end

QLMSetup *QLMReadFixtureSetup(void) {
    static QLMSetup *setup;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *error = nil;
        setup = [QLMSetupReader readFileAtPath:QLMFixturePath(@"Main.sam") error:&error];
        NSCAssert(setup != nil, @"the fixture does not parse: %@", error);
    });
    return setup;
}
