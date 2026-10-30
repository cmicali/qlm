#import "QLMTestSupport.h"

#import <IOKit/IOKitLib.h>

#import "QLMHostCheck.h"
#import "QLMHIDAdapterInternal.h"
#include "QLMReport.h"

// Sources: this Mac's IORegistry and process table, read with ioreg and ps on
// macOS 27.0.1 on 2026-10-30. GLM's executable is
// /Applications/GLMv5.app/Contents/MacOS/GLMv5. While it runs, it holds an
// IOHIDLibUserClient on the adapter's HID device whose IOUserClientCreator is
// "pid 74853, GLMv5", and whose DebugState has ClientOpened Yes and
// ClientSeized No. Spotify holds an AppleUSBHostDeviceUserClient on the
// adapter's USB device, and on every other USB device, with only
// IOUserClientCreator and IOUserClientDefaultLocking, whether GLM runs or not.
// The adapter's USB device has no UsbExclusiveOwner, and its interface's is
// AppleUserUSBHostHIDDevice. An interface MIDIServer has opened has
// UsbExclusiveOwner "pid 906, MIDIServer", beside MIDIServer's
// AppleUSBHostInterfaceUserClient. The tests never open the adapter or scan
// the system.
@interface QLMHostCheckTests : XCTestCase
@end

static const pid_t QLMTestPid = 4242;

// GLM's client on the adapter's HID device, as ioreg showed it.
static NSDictionary *QLMGLMClient(void) {
    return @{
        @"IOUserClientCreator": @"pid 74853, GLMv5",
        @"DebugState": @{@"ClientSeized": @NO, @"ClientOptions": @1, @"Privileged": @NO, @"ClientOpened": @YES,
                         @"ClientSuspended": @NO},
    };
}

// A nil state leaves its key out.
static NSDictionary *QLMHIDClient(NSString *creator, id opened, id seized) {
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithDictionary:@{@"ClientOptions": @0, @"Privileged": @NO}];
    state[@"ClientOpened"] = opened;
    state[@"ClientSeized"] = seized;
    return @{@"IOUserClientCreator": creator, @"DebugState": state};
}

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

// Any client GLM created holds the adapter, whatever its class.
- (void)testGLMsClientHoldsTheAdapter {
    NSString *glm = @"GLM is running (pid 74853). Quit GLM first.";
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMGLMClient(), QLMTestPid), glm);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(@"pid 74853, GLMv5", @NO, @NO), QLMTestPid),
                          glm);
    NSDictionary *enumerating = @{@"IOUserClientCreator": @"pid 74853, GLMv5", @"IOUserClientDefaultLocking": @YES};
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"AppleUSBHostDeviceUserClient", enumerating, QLMTestPid), glm);
}

// Spotify enumerates every USB device. Its client must not block qlm.
- (void)testAnEnumeratingClientDoesNotHoldTheAdapter {
    NSDictionary *spotify = @{@"IOUserClientCreator": @"pid 74517, Spotify", @"IOUserClientDefaultLocking": @YES};
    XCTAssertNil(QLMHostCheckClientHolder(@"AppleUSBHostDeviceUserClient", spotify, QLMTestPid));
    NSDictionary *midi = @{@"IOUserClientCreator": @"pid 906, MIDIServer", @"IOUserClientDefaultLocking": @YES};
    XCTAssertNil(QLMHostCheckClientHolder(@"AppleUSBHostInterfaceUserClient", midi, QLMTestPid));
}

// Another process holds the HID device as GLM does once it opens or seizes
// it. One that has neither opened nor seized it only enumerates.
- (void)testAnOpenedHIDClientHoldsTheAdapter {
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(@"pid 68381, openlogi-agent", @YES, @NO),
                                                   QLMTestPid),
                          @"openlogi-agent (pid 68381) holds the GLM adapter.");
    XCTAssertNotNil(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(@"pid 68381, openlogi-agent", @NO, @YES),
                                             QLMTestPid));
    XCTAssertNil(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(@"pid 68381, openlogi-agent", @NO, @NO), QLMTestPid));
}

// TRAP: when unsure, a client holds the adapter.
- (void)testAClientHoldsTheAdapterWhenUnsure {
    NSString *creator = @"pid 68381, openlogi-agent";
    NSString *holds = @"openlogi-agent (pid 68381) holds the GLM adapter.";
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", @{@"IOUserClientCreator": creator}, QLMTestPid), holds);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", @{@"IOUserClientCreator": creator, @"DebugState": @[]},
                                                   QLMTestPid),
                          holds);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(creator, nil, @NO), QLMTestPid), holds);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(creator, @NO, nil), QLMTestPid), holds);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(creator, @0, @0), QLMTestPid), holds);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(creator, @"No", @"No"), QLMTestPid), holds);
    // A class not known to enumerate.
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDEventServiceUserClient", QLMHIDClient(creator, @NO, @NO), QLMTestPid),
                          holds);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"", @{@"IOUserClientCreator": creator}, QLMTestPid), holds);

    NSString *unknown = @"A client of unknown origin holds the GLM adapter.";
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"AppleUSBHostDeviceUserClient", @{}, QLMTestPid), unknown);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"AppleUSBHostDeviceUserClient", @{@"IOUserClientCreator": @"pid 0, kernel"},
                                                   QLMTestPid),
                          unknown);
    XCTAssertEqualObjects(QLMHostCheckClientHolder(@"IOHIDLibUserClient", @{@"IOUserClientCreator": @74853}, QLMTestPid), unknown);
}

// qlm's own client, opened and seized, never refuses qlm.
- (void)testThisProcessNeverHoldsTheAdapter {
    XCTAssertNil(QLMHostCheckClientHolder(@"IOHIDLibUserClient", QLMHIDClient(@"pid 4242, qlmctl", @YES, @YES), QLMTestPid));
    XCTAssertNil(QLMHostCheckClientHolder(@"IOHIDEventServiceUserClient", @{@"IOUserClientCreator": @"pid 4242, qlmctl"}, QLMTestPid));
}

// A process that has opened the adapter's USB device or interface holds it.
// A driver that owns one does not.
- (void)testAProcessThatOpenedTheUSBDeviceHoldsTheAdapter {
    XCTAssertNil(QLMHostCheckEntryOwner(@{}, QLMTestPid));
    XCTAssertNil(QLMHostCheckEntryOwner(@{@"UsbExclusiveOwner": @"AppleUserUSBHostHIDDevice"}, QLMTestPid));
    XCTAssertEqualObjects(QLMHostCheckEntryOwner(@{@"UsbExclusiveOwner": @"pid 906, MIDIServer"}, QLMTestPid),
                          @"MIDIServer (pid 906) holds the GLM adapter.");
    XCTAssertEqualObjects(QLMHostCheckEntryOwner(@{@"UsbExclusiveOwner": @"pid 74853, GLMv5"}, QLMTestPid),
                          @"GLM is running (pid 74853). Quit GLM first.");
    XCTAssertNil(QLMHostCheckEntryOwner(@{@"UsbExclusiveOwner": @"pid 4242, qlmctl"}, QLMTestPid));

    NSString *unknown = @"A process of unknown origin has opened the GLM adapter.";
    XCTAssertEqualObjects(QLMHostCheckEntryOwner(@{@"UsbExclusiveOwner": @"pid 906"}, QLMTestPid), unknown);
    XCTAssertEqualObjects(QLMHostCheckEntryOwner(@{@"UsbExclusiveOwner": @906}, QLMTestPid), unknown);
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
