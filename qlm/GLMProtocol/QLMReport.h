#ifndef QLMREPORT_H
#define QLMREPORT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "QLMFrame.h"

// The adapter over USB: a HID device on vendor page FFA0, with no report IDs,
// 64-byte input and output reports, and a 1-byte feature report.
enum {
    QLMAdapterVendorID = 0x1781,
    QLMAdapterProductID = 0x0E39,
    QLMAdapterUsagePage = 0xFFA0,
};

// Each report carries one frame after a prefix byte. Host to adapter, the
// prefix is 80 plus the frame's length, and zeros pad the rest. Adapter to
// host, the prefix is always 3F, and a frame that does not fit runs on into
// the next report.
enum {
    QLMReportLength = 64,
    QLMReportFrameMax = QLMReportLength - 1,
    QLMReportOutputPrefix = 0x80,
    QLMReportInputPrefix = 0x3F,
};

// A reply may span up to three input reports.
#define QLMReportAssemblyMax (3 * QLMReportFrameMax)

typedef enum {
    QLMReportOK = 0,
    QLMReportPending,         // the frame runs on into the next input report
    QLMReportNoAnswer,        // the adapter's own reply: no monitor answered
    QLMReportErrorLength,     // not a report's length, or a frame that does not fit
    QLMReportErrorForbidden,  // the allowlist refused the message
    QLMReportErrorPrefix,
    QLMReportErrorPadding,    // a nonzero byte after the frame
    QLMReportErrorOverflow,   // no closing flag within QLMReportAssemblyMax
    QLMReportErrorFrame,      // the assembled frame does not decode
} QLMReportStatus;

// Encodes the message through the allowlist and packs it as one output
// report. Every byte qlm hands the adapter comes from here.
QLMReportStatus QLMReportPackOutput(const QLMMessage *message, uint8_t report[QLMReportLength]);

// Finds the frame in an output report, as a capture holds one. `frame`
// points into `report`.
QLMReportStatus QLMReportUnpackOutput(const uint8_t *report, size_t length, const uint8_t **frame, size_t *frameLength);

// Gathers one reply frame from consecutive input reports.
typedef struct {
    size_t length;
    uint8_t frame[QLMReportAssemblyMax];
} QLMReportAssembly;

void QLMReportAssemblyReset(QLMReportAssembly *assembly);

// A frame has begun, and its closing flag has not arrived.
bool QLMReportAssemblyIsPending(const QLMReportAssembly *assembly);

// Adds one input report. When the closing flag arrives, decodes the frame
// into `reply`: QLMReportOK for a monitor's reply, QLMReportNoAnswer for the
// adapter's. Either way the escaped frame stays in `frame` until the next
// call. After an error the next report starts a new frame.
QLMReportStatus QLMReportReadInput(QLMReportAssembly *assembly, const uint8_t *report, size_t length, QLMMessage *reply);

#endif
