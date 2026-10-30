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

@class QLMReportLink;

// The GLM adapter as a capture saw it, at the level of reports, behind a
// QLMReportLink as the HID adapter is. Each output report the link writes
// gets the input reports that answered it in the capture, split as the
// adapter sent them, after replyDelay. A report the capture never sent, or
// any report while silent, gets none.
@interface QLMCaptureDevice : NSObject <QLMAdapter>

- (instancetype)initWithCapture:(QLMCapture *)capture;

@property (nonatomic, readonly, nullable) QLMReportLink *link;  // made by startOnQueue:
@property (atomic) NSTimeInterval replyDelay;                   // 1 ms
@property (atomic) BOOL silent;
// Every output report written, as 64 bytes. Read on the queue.
@property (nonatomic, readonly) NSArray<NSData *> *writtenReports;
@property (nonatomic, readonly) NSUInteger unmatchedReports;

// A frame as the adapter delivers it: one input report per 63 bytes, each
// starting with 3F and padded with zeros.
+ (NSArray<NSData *> *)inputReportsForFrame:(NSData *)frame;

@end

@interface XCTestCase (QLMAdapter)

// Sends on the adapter's queue and waits for the handler, failing the test
// if it never comes. Returns whether a monitor answered.
- (BOOL)qlm_send:(QLMMessage)message to:(id<QLMAdapter>)adapter queue:(dispatch_queue_t)queue reply:(nullable QLMMessage *)reply
           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif
