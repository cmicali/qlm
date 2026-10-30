#include "QLMFrame.h"

#include <string.h>

#include "QLMCRC.h"

bool QLMAddressIsLeasable(uint8_t address) {
    return address >= QLMAddressSessionFirst && address <= QLMAddressSessionLast && address != QLMAddressMulticast &&
           address != QLMFrameFlag && address != QLMFrameEscape;
}

QLMMessage QLMMessageMake(uint8_t address, const uint8_t *payload, size_t length) {
    QLMMessage message;
    memset(&message, 0, sizeof message);
    message.address = address;
    message.length = length < QLMPayloadMax ? length : QLMPayloadMax;
    if (payload != NULL) {
        memcpy(message.payload, payload, message.length);
    }
    return message;
}

bool QLMFrameAllows(const uint8_t *payload, size_t length) {
    if (payload == NULL || length == 0) {
        return false;
    }
    switch (payload[0]) {
    case 0x02: // assign a session ID, only one qlm may lease
        return length == 5 && QLMAddressIsLeasable(payload[4]);
    case 0x04: // keep-alive
    case 0x08: // telemetry poll
    case 0x17: // prepare for configuration
    case 0x19: // serial number
    case 0x1F: // volume
    case 0x2B: // mute and LED
    case 0x39: // system info
    case 0x3B: // crossover
    case 0x3D: // input select sync
    case 0x40: // input routing
    case 0xFE: // discovery probe
        return true;
    case 0x10: // DSP: delay, level compensation, PEQ
        if (length < 2) {
            return false;
        }
        if (payload[1] == 0x02 || payload[1] == 0x0E) {
            return true;
        }
        if (payload[1] == 0x01) {
            return length >= 3 && (payload[2] == 0x00 || payload[2] == 0x09);
        }
        return false;
    case 0x2D: // the preamble to broadcast 3D 00 00, this payload only
        return length == 2 && payload[1] == 0x00;
    case 0x3A: // power only, never the standalone settings
        return length >= 2 && payload[1] == 0x03;
    default:
        return false;
    }
}

static bool QLMFramePut(uint8_t *out, size_t capacity, size_t *count, uint8_t byte, bool escape) {
    if (escape && (byte == QLMFrameFlag || byte == QLMFrameEscape)) {
        if (*count + 2 > capacity) {
            return false;
        }
        out[(*count)++] = QLMFrameEscape;
        out[(*count)++] = byte ^ QLMFrameEscapeXor;
        return true;
    }
    if (*count + 1 > capacity) {
        return false;
    }
    out[(*count)++] = byte;
    return true;
}

QLMFrameStatus QLMFrameEncode(const QLMMessage *message, uint8_t *out, size_t capacity, size_t *outLength) {
    if (outLength != NULL) {
        *outLength = 0;
    }
    if (message == NULL || out == NULL || message->length == 0 || message->length > QLMPayloadMax) {
        return QLMFrameErrorLength;
    }
    // TRAP: the address is not escaped; on the bus its ninth bit marks it. No
    // capture has an address above 19, so whether the adapter escapes a 7D or
    // 7E there is unknown, and neither goes out.
    if (!QLMFrameAllows(message->payload, message->length) || message->address == QLMFrameFlag ||
        message->address == QLMFrameEscape) {
        return QLMFrameErrorForbidden;
    }
    // GLM sends 2D only as a broadcast.
    if (message->payload[0] == 0x2D && message->address != QLMAddressBroadcast) {
        return QLMFrameErrorForbidden;
    }

    uint8_t raw[1 + QLMPayloadMax];
    raw[0] = message->address;
    memcpy(raw + 1, message->payload, message->length);
    uint16_t crc = QLMCRC16GSM(raw, 1 + message->length);

    size_t count = 0;
    bool ok = QLMFramePut(out, capacity, &count, message->address, false);
    for (size_t i = 0; ok && i < message->length; i++) {
        ok = QLMFramePut(out, capacity, &count, message->payload[i], true);
    }
    ok = ok && QLMFramePut(out, capacity, &count, (uint8_t)(crc >> 8), true);
    ok = ok && QLMFramePut(out, capacity, &count, (uint8_t)(crc & 0xFF), true);
    ok = ok && QLMFramePut(out, capacity, &count, QLMFrameFlag, false);
    if (!ok) {
        return QLMFrameErrorLength;
    }
    if (outLength != NULL) {
        *outLength = count;
    }
    return QLMFrameOK;
}

QLMFrameStatus QLMFrameDecode(const uint8_t *bytes, size_t length, QLMMessage *message) {
    if (bytes == NULL || message == NULL || length == 0) {
        return QLMFrameErrorLength;
    }
    if (bytes[length - 1] != QLMFrameFlag) {
        return QLMFrameErrorFlag;
    }

    uint8_t raw[1 + QLMPayloadMax + 2];
    raw[0] = bytes[0];
    size_t count = 1;
    for (size_t i = 1; i + 1 < length; i++) {
        uint8_t byte = bytes[i];
        if (byte == QLMFrameFlag) {
            return QLMFrameErrorFlag;
        }
        if (byte == QLMFrameEscape) {
            i++;
            if (i + 1 >= length) {
                return QLMFrameErrorEscape;
            }
            uint8_t escaped = bytes[i] ^ QLMFrameEscapeXor;
            if (escaped != QLMFrameFlag && escaped != QLMFrameEscape) {
                return QLMFrameErrorEscape;
            }
            byte = escaped;
        }
        if (count >= sizeof raw) {
            return QLMFrameErrorLength;
        }
        raw[count++] = byte;
    }
    if (count < 1 + 1 + 2) {
        return QLMFrameErrorLength;
    }

    uint16_t expected = (uint16_t)((raw[count - 2] << 8) | raw[count - 1]);
    if (QLMCRC16GSM(raw, count - 2) != expected) {
        return QLMFrameErrorCRC;
    }
    message->address = raw[0];
    message->length = count - 3;
    memcpy(message->payload, raw + 1, message->length);
    return QLMFrameOK;
}
