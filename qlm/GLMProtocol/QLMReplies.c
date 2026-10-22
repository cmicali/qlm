#include "QLMReplies.h"

#include <string.h>

static bool QLMReplyIsReply(const QLMMessage *message) {
    return message != NULL && message->address == QLMAddressReply && message->length >= 1 && message->payload[0] == 0x09;
}

static bool QLMReplyIsBusyMarker(uint8_t byte) {
    return byte == 0x06 || byte == 0x07;
}

bool QLMReplyIsAck(const QLMMessage *message) {
    return QLMReplyIsReply(message) && message->length == 1;
}

bool QLMReplyIsBusy(const QLMMessage *message) {
    return QLMReplyIsReply(message) && message->length == 2 && QLMReplyIsBusyMarker(message->payload[1]);
}

bool QLMReplySessionAck(const QLMMessage *message, uint8_t *session) {
    if (!QLMReplyIsReply(message) || message->length != 2) {
        return false;
    }
    if (session != NULL) {
        *session = message->payload[1];
    }
    return true;
}

bool QLMReplyHardwareID(const QLMMessage *message, uint8_t hardwareID[3]) {
    if (!QLMReplyIsReply(message) || message->length != 4) {
        return false;
    }
    if (hardwareID != NULL) {
        memcpy(hardwareID, message->payload + 1, 3);
    }
    return true;
}

bool QLMReplyText(const QLMMessage *message, char *out, size_t capacity) {
    if (!QLMReplyIsReply(message) || out == NULL || capacity == 0) {
        return false;
    }
    size_t start = 1;
    if (message->length > start && QLMReplyIsBusyMarker(message->payload[start])) {
        start++;
    }
    size_t count = 0;
    for (size_t i = start; i < message->length; i++) {
        uint8_t byte = message->payload[i];
        if (byte == 0) {
            break;
        }
        if (byte < 0x20 || byte > 0x7E || count + 1 >= capacity) {
            return false;
        }
        out[count++] = (char)byte;
    }
    out[count] = '\0';
    return count > 0;
}

static bool QLMCopyField(const char *start, size_t length, char *out, size_t capacity) {
    if (length + 1 > capacity) {
        return false;
    }
    memcpy(out, start, length);
    out[length] = '\0';
    return true;
}

bool QLMSystemInfoParse(const char *text, char *model, size_t modelCapacity, char *firmware, size_t firmwareCapacity) {
    if (text == NULL || model == NULL || firmware == NULL || modelCapacity == 0 || firmwareCapacity == 0) {
        return false;
    }
    model[0] = '\0';
    firmware[0] = '\0';
    if (strchr(text, ';') == NULL && strstr(text, "model-") == NULL) {
        size_t length = strcspn(text, " ");
        return length > 0 && QLMCopyField(text, length, model, modelCapacity);
    }
    for (const char *field = text; *field != '\0';) {
        size_t length = strcspn(field, ";");
        if (length > 6 && strncmp(field, "model-", 6) == 0) {
            if (!QLMCopyField(field + 6, length - 6, model, modelCapacity)) {
                return false;
            }
        } else if (length > 4 && strncmp(field, "ver-", 4) == 0) {
            if (!QLMCopyField(field + 4, length - 4, firmware, firmwareCapacity)) {
                return false;
            }
        }
        field += length;
        if (*field == ';') {
            field++;
        }
    }
    return model[0] != '\0';
}

// The value length of each tag. Zero for a tag the spec does not list.
static size_t QLMTelemetryValueLength(uint8_t tag) {
    switch (tag) {
    case 0x42: case 0x43: case 0x44: case 0x45: case 0x46: case 0x47:
        return 1;
    case 0x81: case 0x83: case 0x84:
        return 2;
    default:
        return 0;
    }
}

QLMTelemetryStatus QLMReplyTelemetry(const QLMMessage *message, QLMTelemetry *telemetry) {
    if (telemetry == NULL) {
        return QLMTelemetryErrorNotTelemetry;
    }
    telemetry->busy = false;
    telemetry->temperature = 0;
    telemetry->inputMeter = QLMTelemetryAbsent;
    telemetry->hfMeter = QLMTelemetryAbsent;
    telemetry->midMeter = QLMTelemetryAbsent;
    telemetry->lfMeter = QLMTelemetryAbsent;
    telemetry->subMeter = QLMTelemetryAbsent;
    telemetry->status = QLMTelemetryAbsent;
    telemetry->sensor81 = QLMTelemetryAbsent;
    telemetry->sensor83 = QLMTelemetryAbsent;
    telemetry->deviceClass = QLMTelemetryAbsent;
    telemetry->stateMetric = QLMTelemetryAbsent;
    telemetry->unknownTag = 0;

    if (!QLMReplyIsReply(message)) {
        return QLMTelemetryErrorNotTelemetry;
    }
    size_t i = 1;
    if (i < message->length && QLMReplyIsBusyMarker(message->payload[i])) {
        telemetry->busy = true;
        i++;
    }
    if (i >= message->length || message->payload[i] != 0x41) {
        return QLMTelemetryErrorNotTelemetry;
    }
    i++;
    if (i >= message->length) {
        return QLMTelemetryErrorTruncated;
    }
    telemetry->temperature = message->payload[i++];

    while (i < message->length) {
        uint8_t tag = message->payload[i];
        size_t valueLength = QLMTelemetryValueLength(tag);
        if (valueLength == 0) {
            telemetry->unknownTag = tag;
            return QLMTelemetryErrorUnknownTag;
        }
        if (i + valueLength >= message->length) {
            return QLMTelemetryErrorTruncated;
        }
        const uint8_t *value = message->payload + i + 1;
        switch (tag) {
        case 0x42: telemetry->inputMeter = value[0]; break;
        case 0x43: telemetry->hfMeter = value[0]; break;
        case 0x44: telemetry->midMeter = value[0]; break;
        case 0x45: telemetry->lfMeter = value[0]; break;
        case 0x46: telemetry->subMeter = value[0]; break;
        case 0x47: telemetry->status = value[0]; break;
        case 0x81: telemetry->sensor81 = value[1]; break;
        case 0x83: telemetry->sensor83 = value[1]; break;
        case 0x84:
            telemetry->deviceClass = value[0];
            telemetry->stateMetric = value[1];
            break;
        default: break;
        }
        i += 1 + valueLength;
    }
    return QLMTelemetryOK;
}
