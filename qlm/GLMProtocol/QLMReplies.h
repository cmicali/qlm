#ifndef QLMREPLIES_H
#define QLMREPLIES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "QLMFrame.h"

// Every reply comes from QLMAddressReply with a payload that starts with 09.
// A 06 or 07 may follow the 09 before the data: the monitor is busy writing
// settings. A bare 09 06 or 09 07 is a poll with no telemetry this round.
//
// TRAP: 09 06 is also a session acknowledgement for session 06. Only the
// command just sent tells them apart, so the caller picks the parser.

bool QLMReplyIsAck(const QLMMessage *message);
bool QLMReplyIsBusy(const QLMMessage *message);
bool QLMReplySessionAck(const QLMMessage *message, uint8_t *session);
bool QLMReplyHardwareID(const QLMMessage *message, uint8_t hardwareID[3]);

// The serial number (15 ASCII characters, no NUL) and the system info (ASCII,
// NUL-terminated). Copies the text, NUL-terminated, into `out`.
bool QLMReplyText(const QLMMessage *message, char *out, size_t capacity);

// Reads the model and the firmware version from system info text, in either
// form: semicolon-separated fields (model-, ver-) or space-delimited with the
// model first. The firmware is empty when the text has none. False when no
// model is found or a field does not fit its buffer.
bool QLMSystemInfoParse(const char *text, char *model, size_t modelCapacity, char *firmware, size_t firmwareCapacity);

// Telemetry: 09, an optional busy marker, 41, the temperature in degrees C,
// then tag-value fields with no length byte. A field not present is
// QLMTelemetryAbsent. The 47 status is the only authority on power: 01 is on,
// anything else is not.
#define QLMTelemetryAbsent (-1)

enum {
    QLMTelemetryStatusOn = 0x01,
    QLMTelemetryStatusStandby = 0x02,
    QLMTelemetryClassSubwoofer = 0x01,
    QLMTelemetryClassTwoWay = 0x02,
    QLMTelemetryClassStandby = 0x03,
};

typedef struct {
    bool busy;
    uint8_t temperature;
    int16_t inputMeter;   // 42
    int16_t hfMeter;      // 43, floored on subwoofers
    int16_t midMeter;     // 44, expected on three-way models, never seen
    int16_t lfMeter;      // 45
    int16_t subMeter;     // 46, subwoofers only
    int16_t status;       // 47
    int16_t sensor81;     // 81, second byte
    int16_t sensor83;     // 83, second byte
    int16_t deviceClass;  // 84, first byte
    int16_t stateMetric;  // 84, second byte, meaning unknown
    uint8_t unknownTag;   // where the walk stopped, or 0
} QLMTelemetry;

typedef enum {
    QLMTelemetryOK = 0,
    QLMTelemetryErrorNotTelemetry,
    QLMTelemetryErrorTruncated,
    QLMTelemetryErrorUnknownTag,
} QLMTelemetryStatus;

// Fills `telemetry` as far as the walk gets. On an unknown tag the fields
// before it are valid and unknownTag names it.
QLMTelemetryStatus QLMReplyTelemetry(const QLMMessage *message, QLMTelemetry *telemetry);

#endif
