#ifndef QLMTESTSUPPORT_H
#define QLMTESTSUPPORT_H

#import <XCTest/XCTest.h>

#include <string.h>

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
        QLMMessage message_;                                                               \
        memset(&message_, 0, sizeof message_);                                             \
        message_.address = (addr);                                                         \
        message_.length = sizeof payload_;                                                 \
        memcpy(message_.payload, payload_, sizeof payload_);                               \
        message_;                                                                          \
    })

#endif
