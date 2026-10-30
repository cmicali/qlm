#include "QLMReport.h"

#include <string.h>

#include "QLMReplies.h"

_Static_assert(QLMReportAssemblyMax <= 1 + QLMPayloadMax + 2 + 1, "an assembled frame must fit a message");

static bool QLMReportIsZero(const uint8_t *bytes, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (bytes[i] != 0) {
            return false;
        }
    }
    return true;
}

QLMReportStatus QLMReportPackOutput(const QLMMessage *message, uint8_t report[QLMReportLength]) {
    if (report == NULL) {
        return QLMReportErrorLength;
    }
    memset(report, 0, QLMReportLength);
    uint8_t frame[QLMFrameMax];
    size_t length = 0;
    QLMFrameStatus status = QLMFrameEncode(message, frame, sizeof frame, &length);
    if (status == QLMFrameErrorForbidden) {
        return QLMReportErrorForbidden;
    }
    if (status != QLMFrameOK || length > QLMReportFrameMax) {
        return QLMReportErrorLength;
    }
    report[0] = (uint8_t)(QLMReportOutputPrefix | length);
    memcpy(report + 1, frame, length);
    return QLMReportOK;
}

bool QLMReportExpectsReply(const QLMMessage *message) {
    if (message == NULL || message->length == 0) {
        return false;
    }
    return message->address != QLMAddressBroadcast || message->payload[0] == 0xFE;
}

QLMReportStatus QLMReportUnpackOutput(const uint8_t *report, size_t length, const uint8_t **frame, size_t *frameLength) {
    if (report == NULL || length != QLMReportLength) {
        return QLMReportErrorLength;
    }
    if ((report[0] & QLMReportOutputPrefix) == 0) {
        return QLMReportErrorPrefix;
    }
    size_t count = (size_t)(report[0] ^ QLMReportOutputPrefix);
    if (count == 0 || count > QLMReportFrameMax) {
        return QLMReportErrorLength;
    }
    if (!QLMReportIsZero(report + 1 + count, QLMReportFrameMax - count)) {
        return QLMReportErrorPadding;
    }
    if (frame != NULL) {
        *frame = report + 1;
    }
    if (frameLength != NULL) {
        *frameLength = count;
    }
    return QLMReportOK;
}

void QLMReportAssemblyReset(QLMReportAssembly *assembly) {
    if (assembly != NULL) {
        assembly->length = 0;
    }
}

// Only the closing flag can end the frame: an escaped frame holds no other 7E.
static bool QLMReportAssemblyIsComplete(const QLMReportAssembly *assembly) {
    return assembly->length > 0 && assembly->frame[assembly->length - 1] == QLMFrameFlag;
}

bool QLMReportAssemblyIsPending(const QLMReportAssembly *assembly) {
    return assembly != NULL && assembly->length > 0 && !QLMReportAssemblyIsComplete(assembly);
}

static QLMReportStatus QLMReportAssemblyFail(QLMReportAssembly *assembly, QLMReportStatus status) {
    QLMReportAssemblyReset(assembly);
    return status;
}

QLMReportStatus QLMReportReadInput(QLMReportAssembly *assembly, const uint8_t *report, size_t length, QLMMessage *reply) {
    if (assembly == NULL || reply == NULL) {
        return QLMReportErrorLength;
    }
    if (QLMReportAssemblyIsComplete(assembly)) {
        QLMReportAssemblyReset(assembly);
    }
    if (report == NULL || length != QLMReportLength) {
        return QLMReportAssemblyFail(assembly, QLMReportErrorLength);
    }
    if (report[0] != QLMReportInputPrefix) {
        return QLMReportAssemblyFail(assembly, QLMReportErrorPrefix);
    }
    const uint8_t *body = report + 1;
    const uint8_t *flag = memchr(body, QLMFrameFlag, QLMReportFrameMax);
    size_t count = flag == NULL ? QLMReportFrameMax : (size_t)(flag - body) + 1;
    if (assembly->length + count > QLMReportAssemblyMax) {
        return QLMReportAssemblyFail(assembly, QLMReportErrorOverflow);
    }
    if (!QLMReportIsZero(body + count, QLMReportFrameMax - count)) {
        return QLMReportAssemblyFail(assembly, QLMReportErrorPadding);
    }
    memcpy(assembly->frame + assembly->length, body, count);
    assembly->length += count;
    if (flag == NULL) {
        return QLMReportPending;
    }
    if (QLMFrameDecode(assembly->frame, assembly->length, reply) != QLMFrameOK) {
        return QLMReportAssemblyFail(assembly, QLMReportErrorFrame);
    }
    return QLMReplyIsNoAnswer(reply) ? QLMReportNoAnswer : QLMReportOK;
}
