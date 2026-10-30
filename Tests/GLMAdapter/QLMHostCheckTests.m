#import "QLMTestSupport.h"

#import <IOKit/IOKitLib.h>

#import "QLMHostCheck.h"
#import "QLMHIDAdapterInternal.h"
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

// A failed seize refuses the adapter. qlm never opens it shared, where GLM
// could open it too and drive the bus alongside qlm. The stand-in for IOKit
// fails every open, so a shared retry shows as a second call.
- (void)testAFailedSeizeRefusesTheAdapterAndOpensNothing {
    QLMHIDAdapter *adapter = [[QLMHIDAdapter alloc] init];
    NSMutableArray<NSNumber *> *opens = [NSMutableArray array];
    adapter.open = ^IOReturn(IOHIDDeviceRef device, IOOptionBits options) {
        [opens addObject:@(options)];
        return kIOReturnNotPrivileged;
    };
    // Only the stand-in and CFRelease touch it.
    IOHIDDeviceRef device = (IOHIDDeviceRef)CFBridgingRetain([[NSObject alloc] init]);
    NSError *refusal = [adapter openDevice:device];
    XCTAssertEqualObjects(opens, @[@(kIOHIDOptionsTypeSeizeDevice)]);
    XCTAssertEqualObjects(refusal.domain, QLMAdapterErrorDomain);
    XCTAssertEqual(refusal.code, QLMAdapterErrorBusy);
    XCTAssertEqualObjects(refusal.localizedDescription,
                          @"qlm could not seize the GLM adapter (0xe00002c1). It opens the adapter only seized.");
    // No device is open, so no report can be written.
    XCTAssertFalse(adapter.seized);
    XCTAssertEqualObjects(adapter.deviceDescription, @"the GLM adapter over USB, not open");

    opens = [NSMutableArray array];
    adapter.open = ^IOReturn(IOHIDDeviceRef device, IOOptionBits options) {
        [opens addObject:@(options)];
        return kIOReturnExclusiveAccess;
    };
    refusal = [adapter openDevice:(IOHIDDeviceRef)CFBridgingRetain([[NSObject alloc] init])];
    XCTAssertEqualObjects(opens, @[@(kIOHIDOptionsTypeSeizeDevice)]);
    XCTAssertEqual(refusal.code, QLMAdapterErrorBusy);
    XCTAssertEqualObjects(refusal.localizedDescription, @"Another process has seized the GLM adapter.");
    XCTAssertFalse(adapter.seized);
}

@end
