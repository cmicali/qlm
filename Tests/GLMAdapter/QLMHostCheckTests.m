#import "QLMTestSupport.h"

#import <IOKit/IOKitLib.h>

#import "QLMHostCheck.h"
#import "QLMHIDAdapter.h"
#include "QLMReport.h"

// Sources: this Mac's IORegistry and process table with GLM 5 running, read
// with ioreg and ps: GLM's executable is
// /Applications/GLMv5.app/Contents/MacOS/GLMv5, and it holds an
// IOHIDLibUserClient on the adapter's HID device whose IOUserClientCreator is
// "pid 20129, GLMv5". The tests never open the adapter or scan the system.
@interface QLMHostCheckTests : XCTestCase
@end

@implementation QLMHostCheckTests

- (void)testFindsGLMByItsExecutable {
    XCTAssertTrue(QLMHostCheckIsGLMExecutable(@"/Applications/GLMv5.app/Contents/MacOS/GLMv5"));
    XCTAssertTrue(QLMHostCheckIsGLMExecutable(@"/Users/someone/Applications/GLMv5.app/Contents/MacOS/GLMv5"));
    XCTAssertFalse(QLMHostCheckIsGLMExecutable(@"/Applications/Logic Pro.app/Contents/MacOS/Logic Pro"));
    XCTAssertFalse(QLMHostCheckIsGLMExecutable(@"/usr/local/bin/qlmctl"));
}

- (void)testReadsAUserClientsCreator {
    pid_t pid = 0;
    NSString *name = nil;
    XCTAssertTrue(QLMHostCheckParseCreator(@"pid 20129, GLMv5", &pid, &name));
    XCTAssertEqual(pid, 20129);
    XCTAssertEqualObjects(name, @"GLMv5");
    XCTAssertTrue(QLMHostCheckParseCreator(@"pid 898, NIHostIntegratio", &pid, &name));
    XCTAssertEqualObjects(name, @"NIHostIntegratio");

    XCTAssertFalse(QLMHostCheckParseCreator(@"pid 0, kernel", &pid, &name));
    XCTAssertFalse(QLMHostCheckParseCreator(@"pid 12", &pid, &name));
    XCTAssertFalse(QLMHostCheckParseCreator(@"GLMv5", &pid, &name));
    XCTAssertFalse(QLMHostCheckParseCreator(@"", &pid, &name));
}

// The adapter's vendor, product, and usage page, which the captures'
// descriptors confirm (QLMGoldenTests).
- (void)testMatchesOnlyTheAdapter {
    CFMutableDictionaryRef matching = QLMHostCheckCreateHIDMatching();
    NSDictionary *dictionary = CFBridgingRelease(matching);
    XCTAssertEqualObjects(dictionary[@kIOProviderClassKey], @"IOHIDDevice");
    NSDictionary *properties = dictionary[@kIOPropertyMatchKey];
    XCTAssertEqualObjects(properties[@"VendorID"], @(0x1781));
    XCTAssertEqualObjects(properties[@"ProductID"], @(0x0E39));
    XCTAssertEqualObjects(properties[@"PrimaryUsagePage"], @(0xFFA0));
    XCTAssertEqual(properties.count, 3u);
}

// Before it starts, the HID adapter has opened nothing, and a send without a
// start is a programming error, so only the description is checked.
- (void)testTheHIDAdapterStartsClosed {
    QLMHIDAdapter *adapter = [[QLMHIDAdapter alloc] init];
    XCTAssertFalse(adapter.seized);
    XCTAssertEqualObjects(adapter.deviceDescription, @"the GLM adapter over USB, not open");
    XCTAssertEqualWithAccuracy(adapter.replyTimeout, 0.1, 1e-9);
}

@end
