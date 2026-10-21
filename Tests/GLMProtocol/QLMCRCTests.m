#import <XCTest/XCTest.h>

#import "QLMCRC.h"

@interface QLMCRCTests : XCTestCase
@end

@implementation QLMCRCTests

// The CRC catalogue's check value for CRC-16/GSM.
- (void)testCheckValue {
    const uint8_t bytes[] = "123456789";
    XCTAssertEqual(QLMCRC16GSM(bytes, 9), 0xCE3C);
}

- (void)testEmptyInput {
    XCTAssertEqual(QLMCRC16GSM(NULL, 0), 0xFFFF);
}

// From the hlm protocol spec, revision 13: the keep-alive broadcast `FF 04`,
// and a monitor's bare ack `09` from address `01`.
- (void)testBusFrames {
    const uint8_t keepAlive[] = {0xFF, 0x04};
    XCTAssertEqual(QLMCRC16GSM(keepAlive, sizeof keepAlive), 0xBC84);

    const uint8_t ack[] = {0x01, 0x09};
    XCTAssertEqual(QLMCRC16GSM(ack, sizeof ack), 0x5DE7);
}

@end
