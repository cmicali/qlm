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

// The adapter answers every probe and unicast with one frame: the monitor's
// reply, or a bare 7E from 01 when no monitor answered. QLMReportReadInput
// tells them apart, so an adapter passes the 7E on as no reply.
bool QLMReplyIsNoAnswer(const QLMMessage *message);

bool QLMReplyIsAck(const QLMMessage *message);
bool QLMReplyIsBusy(const QLMMessage *message);
bool QLMReplySessionAck(const QLMMessage *message, uint8_t *session);
bool QLMReplyHardwareID(const QLMMessage *message, uint8_t hardwareID[3]);

// The serial number (14 or 15 ASCII characters, no NUL) and the system info
// (ASCII, NUL-terminated). Copies the text, NUL-terminated, into `out`.
bool QLMReplyText(const QLMMessage *message, char *out, size_t capacity);

// Reads the model and the firmware version from system info text, in either
// form: semicolon-separated fields (model-, ver-) or space-delimited with the
// model first. The firmware is empty when the text has none. False when no
// model is found or a field does not fit its buffer.
bool QLMSystemInfoParse(const char *text, char *model, size_t modelCapacity, char *firmware, size_t firmwareCapacity);

// Telemetry: 09, an optional busy marker, 41, the temperature in degrees C,
// then tag-value fields with no length byte. A field not present is
// QLMTelemetryAbsent. The 47 status is the only authority on power: 01 is on,
// anything else is not. Tags 88 and 89 have known lengths but no known
// meaning, so the walk steps over them. docs/telemetry.md has the evidence.
// A poll before the monitor's next frame, one a second, gets a bare 09.
#define QLMTelemetryAbsent (-1)

enum {
    QLMTelemetryStatusOn = 0x01,
    QLMTelemetryStatusStandby = 0x02,
    QLMTelemetryClassSubwoofer = 0x01,
    QLMTelemetryClassTwoWay = 0x02,
    QLMTelemetryClassStandby = 0x03,
    QLMTelemetryOutputSilent = 0x80,  // an output meter's floor; a count is about a dB
};

typedef struct {
    bool busy;
    uint8_t temperature;
    int16_t inputMeter;   // 42, before the volume
    int16_t hfMeter;      // 43, floored on subwoofers
    int16_t midMeter;     // 44, three-way models: the 8351B
    int16_t lfMeter;      // 45
    int16_t subMeter;     // 46, subwoofers only
    int16_t status;       // 47
    int16_t wakeSeconds;  // 49, seconds since the monitor last woke, mod 256
    int16_t sensor81;     // 81, second byte
    int16_t sensor82;     // 82, second byte, three-way models
    int16_t sensor83;     // 83, second byte
    int16_t deviceClass;  // 84, first byte
    int16_t stateMetric;  // 84, second byte, meaning unknown
    int32_t wakeSteps;    // 8A: the seconds since the wake over 256, so 49 is its low byte; one frame in 30 s
    uint8_t unknownTag;   // where the walk stopped, or 0
} QLMTelemetry;

typedef enum {
    QLMTelemetryOK = 0,
    QLMTelemetryErrorNotTelemetry,
    QLMTelemetryErrorTruncated,
    QLMTelemetryErrorUnknownTag,
    QLMTelemetryErrorPartial,
} QLMTelemetryStatus;

// Fills `telemetry` as far as the walk gets. On an unknown tag the fields
// before it are valid and unknownTag names it.
//
// TRAP: a monitor sometimes splits a frame in two, at a field, across two
// polls. Every whole frame has 84, and ends with it, or with 84 and 8A. Two
// in the captures then add a bare 04, and read as an unknown tag. The first
// part has no 84 and reads as QLMTelemetryErrorPartial, with its fields
// filled. The second has no 41 and reads as QLMTelemetryErrorNotTelemetry.
QLMTelemetryStatus QLMReplyTelemetry(const QLMMessage *message, QLMTelemetry *telemetry);

// The adapter's reply to 01 08: 09, then fields with no length byte. The top
// two bits of a tag give its value's length: 00 none, 01 one byte, 10 two,
// and 11 four. 30 or 31 says whether the knob is in, and 32 or 33 the mic.
// The knob's position, DF, is a signed big-endian count of tenths of a dB.
// The mic's readings, DE and DD, have no known scale. Each has* says its tag
// was read, since 0 is a reading.
typedef struct {
    bool knob;
    bool mic;
    bool hasKnobPosition;
    bool hasMicDE;
    bool hasMicDD;
    int32_t knobTenths;
    uint32_t micDE;
    uint32_t micDD;
    uint8_t unknownTag;  // the first tag the walk stepped over, or 0
} QLMAdapterStatus;

typedef enum {
    QLMAdapterStatusOK = 0,
    QLMAdapterStatusErrorNotStatus,
    QLMAdapterStatusErrorTruncated,
} QLMAdapterStatusResult;

// The tag rule lets the walk step over a tag it does not know.
QLMAdapterStatusResult QLMReplyAdapterStatus(const QLMMessage *message, QLMAdapterStatus *status);

// Replies name no request, so only a reply's shape can say what it answers.
// These two shapes belong to one request each in every capture.
//
// The adapter's status, exactly: 33, or 32 34 DE DD with the mic, then 31,
// or 30 36 DF with the knob, and nothing after. Only 01 08 gets one.
// TRAP: QLMReplyAdapterStatus's walk reads a serial, and most other replies,
// as a status. Use this to tell a status reply from any other.
bool QLMReplyIsAdapterStatus(const QLMMessage *message);

// System info text, with a model- field. Only 39 gets one.
bool QLMReplyIsSystemInfo(const QLMMessage *message);

#endif
