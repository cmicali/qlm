#ifndef QLMTESTSUPPORT_H
#define QLMTESTSUPPORT_H

#import <XCTest/XCTest.h>

#include <string.h>

#import "QLMAdapter.h"
#import "QLMCapture.h"
#include "QLMFrame.h"
#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

// Asserts that `actual` holds exactly the listed bytes.
#define QLMAssertBytes(actual, actualLength, ...)                                           \
    do {                                                                                   \
        const uint8_t expected_[] = {__VA_ARGS__};                                         \
        XCTAssertEqual((size_t)(actualLength), sizeof expected_);                           \
        if ((size_t)(actualLength) == sizeof expected_) {                                  \
            XCTAssertEqual(memcmp((actual), expected_, sizeof expected_), 0);              \
        }                                                                                  \
    } while (0)

// Builds a QLMMessage from an address and payload bytes.
#define QLMMakeMessage(addr, ...)                                                          \
    ({                                                                                     \
        const uint8_t payload_[] = {__VA_ARGS__};                                          \
        QLMMessageMake((addr), payload_, sizeof payload_);                                 \
    })

NSData *QLMBytes(const uint8_t *bytes, size_t length);

// A file in Tests/Setups/Fixtures/.
NSString *QLMFixturePath(NSString *name);

// Fixtures/Main.sam, parsed once and shared. Never change it.
QLMSetup *QLMReadFixtureSetup(void);

// Every directory under captures/ with a reports.txt, sorted.
NSArray<NSString *> *QLMCaptureScenarios(void);

// captures/<scenario>/reports.txt, read once and shared.
QLMCapture *_Nullable QLMReadCapture(NSString *scenario, NSError **error);

@interface XCTestCase (QLMAdapter)

// Sends on the adapter's queue and waits for the handler, failing the test
// if it never comes. Returns whether a monitor answered.
- (BOOL)qlm_send:(QLMMessage)message to:(id<QLMAdapter>)adapter queue:(dispatch_queue_t)queue reply:(nullable QLMMessage *)reply
           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif
