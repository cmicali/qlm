#import "QLMTestSupport.h"

#import "QLMSetupReader.h"

NSData *QLMBytes(const uint8_t *bytes, size_t length) {
    return [NSData dataWithBytes:bytes length:length];
}

NSString *QLMFixturePath(NSString *name) {
    NSString *tests = [@(__FILE__) stringByDeletingLastPathComponent];
    return [[tests stringByAppendingPathComponent:@"Setups/Fixtures"] stringByAppendingPathComponent:name];
}

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
