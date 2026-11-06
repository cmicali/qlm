#include "QLMDescribe.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "QLMCommands.h"
#include "QLMReplies.h"

static const char QLMMinus[] = "\xE2\x88\x92";

typedef struct {
    char *out;
    size_t capacity;
    size_t length;
} QLMText;

static void QLMPut(QLMText *text, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void QLMPut(QLMText *text, const char *format, ...) {
    if (text->length + 1 >= text->capacity) {
        return;
    }
    va_list args;
    va_start(args, format);
    int written = vsnprintf(text->out + text->length, text->capacity - text->length, format, args);
    va_end(args);
    if (written > 0) {
        size_t room = text->capacity - text->length - 1;
        text->length += (size_t)written < room ? (size_t)written : room;
    }
}

static QLMText QLMTextStart(char *out, size_t capacity) {
    QLMText text = {out, capacity, 0};
    if (capacity > 0) {
        out[0] = '\0';
    }
    return text;
}

// A true minus sign, and no negative zero.
static void QLMPutSigned(QLMText *text, double value, int decimals, bool plus) {
    double rounded = round(value * pow(10, decimals)) / pow(10, decimals);
    if (rounded < 0) {
        QLMPut(text, "%s%.*f", QLMMinus, decimals, -rounded);
    } else {
        QLMPut(text, "%s%.*f", plus && rounded > 0 ? "+" : "", decimals, rounded);
    }
}

static void QLMPutDecibels(QLMText *text, double decibels, int decimals) {
    QLMPutSigned(text, decibels, decimals, false);
    QLMPut(text, " dB");
}

// Three significant figures: "60 Hz", "1 kHz", "12.5 kHz".
static void QLMPutFrequency(QLMText *text, double hertz) {
    if (!(hertz > 0) || !isfinite(hertz)) {
        QLMPut(text, "? Hz");
        return;
    }
    double scale = pow(10, floor(log10(hertz)) - 2);
    double rounded = round(hertz / scale) * scale;
    if (rounded >= 1000) {
        QLMPut(text, "%g kHz", rounded / 1000);
    } else {
        QLMPut(text, "%g Hz", rounded);
    }
}

static uint32_t QLMWord24(const uint8_t *bytes) {
    return (uint32_t)bytes[0] << 16 | (uint32_t)bytes[1] << 8 | bytes[2];
}

void QLMDescribeAddress(uint8_t address, char *out, size_t capacity) {
    QLMText text = QLMTextStart(out, capacity);
    switch (address) {
    case QLMAddressBroadcast: QLMPut(&text, "broadcast FF"); break;
    case QLMAddressMulticast: QLMPut(&text, "adapter multicast F0"); break;
    case QLMAddressAdapter: QLMPut(&text, "adapter 01"); break;
    default: QLMPut(&text, "session %02X", address); break;
    }
}

#pragma mark - Requests

static void QLMPutVolume(QLMText *text, uint32_t word, const QLMDescribeContext *context) {
    if (word == QLMVolumeWordDuck) {
        QLMPut(text, "duck under an apply, 00 00 02, below the bottom stop");
        return;
    }
    double decibels = QLMVolumeDecibelsForWord(word);
    double step = QLMNearestStepDecibels(decibels);
    QLMPut(text, "volume ");
    if (word == QLMVolumeWordMin) {
        QLMPut(text, "%s100 dB, the bottom stop", QLMMinus);
    } else if (step > QLMVolumeDecibelsMin && QLMVolumeWordForDecibels(step) == word) {
        QLMPutDecibels(text, step, 1);
    } else {
        QLMPutDecibels(text, decibels, 2);
        QLMPut(text, ", not one of GLM's steps");
    }
    if (context != NULL && isfinite(context->ceilingDecibels)) {
        QLMMessage ceiling = QLMCommandVolume(QLMVolumeDecibelsMax, context->ceilingDecibels);
        uint32_t ceilingWord = QLMWord24(ceiling.payload + 1);
        if (word == ceilingWord) {
            QLMPut(text, ", at the ceiling");
        } else if (word > ceilingWord) {
            QLMPut(text, ", ABOVE the ceiling ");
            QLMPutDecibels(text, context->ceilingDecibels, 1);
        }
    }
}

static void QLMPutMute(QLMText *text, uint8_t address, uint8_t value) {
    if (address == QLMAddressAdapter) {
        switch (value) {
        case QLMMuteValueAdapterUnmuted: QLMPut(text, "adapter's mute off"); return;
        case QLMMuteValueAdapterMuted: QLMPut(text, "adapter's mute on, as mute all sends it"); return;
        default: break;
        }
    } else {
        switch (value) {
        case QLMMuteValueMuted: QLMPut(text, "mute on"); return;
        case QLMMuteValueUnmuted: QLMPut(text, "mute off"); return;
        case QLMMuteValueOutsideLead: QLMPut(text, "outside the group, first of two"); return;
        case QLMMuteValueOutside: QLMPut(text, "outside the group"); return;
        default: break;
        }
    }
    QLMPut(text, "mute and LED %02X: mute %s, LED bits %u, a value GLM never sends", value, (value & 1) ? "on" : "off",
           (value >> 1) & 3);
}

static void QLMPutPower(QLMText *text, uint8_t step) {
    switch (step) {
    case QLMPowerStepStandbyPrepare: QLMPut(text, "power: prepare for standby"); break;
    case QLMPowerStepPowerOff: QLMPut(text, "power: off to standby"); break;
    case QLMPowerStepWakeFirst: QLMPut(text, "power: wake, first step"); break;
    case QLMPowerStepWakeSecond: QLMPut(text, "power: wake, second step"); break;
    default: QLMPut(text, "power step %02X, unknown", step); break;
    }
}

static void QLMPutRouting(QLMText *text, const uint8_t *p) {
    if (p[1] == 0x00 && p[2] == 0x02 && p[3] == 0x00 && p[4] >= 1 && p[4] <= 3) {
        static const char *const channels[] = {"", "A", "B", "A and B"};
        QLMPut(text, "routing: AES3, channel %s", channels[p[4]]);
    } else if (p[1] == 0x01 && p[2] == 0x02 && p[3] == 0x00 && p[4] == 0x00) {
        QLMPut(text, "routing 40 01 02 00 00, as GLM sends each subwoofer, meaning unknown");
    } else {
        QLMPut(text, "routing: input %u, source %u, pair %u, channel %u, unverified", p[1], p[2], p[3], p[4]);
    }
}

static const char *QLMBandShapeName(QLMBandShape shape) {
    switch (shape) {
    case QLMBandShapePeak: return "peak";
    case QLMBandShapeLowShelf: return "low shelf";
    case QLMBandShapeHighShelf: return "high shelf";
    default: return "";
    }
}

static void QLMPutBand(QLMText *text, const uint8_t *p, const QLMDescribeContext *context) {
    double rate = context != NULL ? context->designRate : 0;
    QLMBandReading band = QLMReadPEQBand(p + 3, rate);
    QLMPut(text, "PEQ slot %02X: ", p[2]);
    if (band.shape == QLMBandShapeFlat) {
        QLMPut(text, "flat");
    } else if (band.shape == QLMBandShapeUnknown) {
        QLMPut(text, "no peak or shelf, unknown");
    } else {
        QLMPut(text, "%s ", QLMBandShapeName(band.shape));
        if (band.spread > 3e-3) {
            QLMPut(text, "about ");
        }
        if (rate > 0) {
            QLMPutFrequency(text, band.frequency);
        } else {
            QLMPut(text, "%.4g of the design rate", band.frequency);
        }
        QLMPut(text, ", Q %.3g, ", band.q);
        QLMPutSigned(text, band.gainDecibels, 1, true);
        QLMPut(text, " dB");
    }
    if (p[23] != 0x00) {
        QLMPut(text, ", last byte %02X, unknown", p[23]);
    }
}

static void QLMPutLevelWord(QLMText *text, uint32_t word) {
    QLMPut(text, "level ");
    if (word == 0) {
        QLMPut(text, "word 0, silent");
        return;
    }
    QLMPutDecibels(text, QLMVolumeDecibelsForWord(word), 2);
}

// The DSP frames, 10 and a subcommand.
static bool QLMPutDSP(QLMText *text, const QLMMessage *m, const QLMDescribeContext *context) {
    const uint8_t *p = m->payload;
    if (m->length < 2) {
        return false;
    }
    switch (p[1]) {
    case 0x01:
        if (m->length == 6 && p[2] == 0x00) {
            QLMPutLevelWord(text, QLMWord24(p + 3));
            return true;
        }
        if (m->length == 6 && p[2] == 0x09) {
            QLMPut(text, "10 01 09 %02X %02X %02X, meaning unknown", p[3], p[4], p[5]);
            return true;
        }
        if (m->length >= 3 && p[2] == 0x05) {
            QLMPut(text, "10 01 05, part of hlm's store sequence");
            return true;
        }
        return false;
    case 0x02:
        if (m->length == 6) {
            uint32_t samples = (uint32_t)p[2] << 24 | (uint32_t)p[3] << 16 | (uint32_t)p[4] << 8 | p[5];
            QLMPut(text, "delay %u samples, %.4g ms at 48 kHz", samples, samples / 48.0);
            return true;
        }
        return false;
    case 0x0E:
        if (m->length == 24) {
            QLMPutBand(text, p, context);
            return true;
        }
        return false;
    default:
        return false;
    }
}

// False for a form docs/protocol.md doesn't give.
static bool QLMPutRequest(QLMText *text, const QLMMessage *m, const QLMDescribeContext *context) {
    const uint8_t *p = m->payload;
    size_t n = m->length;
    switch (p[0]) {
    case 0xFE:
        QLMPut(text, "probe");
        return n == 1;
    case 0x02: {
        uint8_t id[3];
        if (!QLMLeaseHardwareID(m, id)) {
            return false;
        }
        QLMPut(text, "lease session %02X to hardware ID %02X %02X %02X", p[4], id[0], id[1], id[2]);
        return true;
    }
    case 0x03:
        QLMPut(text, "drop every lease");
        return n == 1;
    case 0x04:
        QLMPut(text, "keep-alive");
        return n == 1;
    case 0x05:
        if (n >= 2 && p[1] == 0x04) {
            QLMPut(text, "generator stop, refused by qlm");
        } else {
            QLMPut(text, "test signal, refused by qlm");
        }
        return true;
    case 0x08:
        QLMPut(text, m->address == QLMAddressAdapter ? "status poll" : "poll");
        return n == 1;
    case 0x10:
        return QLMPutDSP(text, m, context);
    case 0x15:
        QLMPut(text, "flash commit, refused by qlm");
        return true;
    case 0x17:
        QLMPut(text, "17 01, first in a block, meaning unknown");
        return n == 2 && p[1] == 0x01;
    case 0x19:
        QLMPut(text, "ask for the serial");
        return n == 2 && p[1] == 0x01;
    case 0x1F:
        if (n != 4) {
            return false;
        }
        QLMPutVolume(text, QLMWord24(p + 1), context);
        return true;
    case 0x22:
        QLMPut(text, "ask for the adapter's identity, refused by qlm");
        return n == 1;
    case 0x2B:
        if (n != 2) {
            return false;
        }
        QLMPutMute(text, m->address, p[1]);
        return true;
    case 0x2D:
        QLMPut(text, "2D 00, before 3D 00 00, meaning unknown");
        return n == 2 && p[1] == 0x00;
    case 0x39:
        QLMPut(text, "ask for system info");
        return n == 1;
    case 0x3A:
        if (n == 3 && p[1] == 0x03) {
            QLMPutPower(text, p[2]);
            return true;
        }
        if (n >= 2 && (p[1] == 0x01 || p[1] == 0x02 || p[1] == 0x06)) {
            QLMPut(text, "standalone setting 3A %02X, refused by qlm", p[1]);
            return true;
        }
        return false;
    case 0x3B:
        if (n != 3) {
            return false;
        }
        if (p[1] == 0x00 && p[2] == 0x01) {
            QLMPut(text, "crossover 00 01, which hlm reads as full band");
        } else {
            QLMPut(text, "crossover %u Hz", (unsigned)(p[1] << 8 | p[2]));
        }
        return true;
    case 0x3C:
    case 0x3E:
    case 0x42:
        QLMPut(text, "%02X 00 00, as GLM sends a subwoofer, meaning unknown", p[0]);
        return n == 3 && p[1] == 0x00 && p[2] == 0x00;
    case 0x3D:
        QLMPut(text, "3D 00 00, meaning unknown");
        return n == 3 && p[1] == 0x00 && p[2] == 0x00;
    case 0x40:
        if (n != 5) {
            return false;
        }
        QLMPutRouting(text, p);
        return true;
    case 0x43:
        QLMPut(text, "43 00 %02X, as GLM sends the 8351B, meaning unknown", n == 3 ? p[2] : 0);
        return n == 3 && p[1] == 0x00;
    case 0x4B:
        QLMPut(text, "4B 00 00 00 %02X, as GLM sends the 8351B, meaning unknown", n == 5 ? p[4] : 0);
        return n == 5 && p[1] == 0x00 && p[2] == 0x00 && p[3] == 0x00;
    case 0x51:
        QLMPut(text, "51 82, meaning unknown, refused by qlm");
        return n == 2 && p[1] == 0x82;
    default:
        return false;
    }
}

void QLMDescribeRequest(const QLMMessage *request, const QLMDescribeContext *context, char *out, size_t capacity) {
    QLMText text = QLMTextStart(out, capacity);
    if (request == NULL || request->length == 0) {
        QLMPut(&text, "empty frame");
        return;
    }
    if (!QLMPutRequest(&text, request, context)) {
        text = QLMTextStart(out, capacity);
        QLMPut(&text, "opcode %02X with %zu bytes, unknown", request->payload[0], request->length);
    }
}

#pragma mark - Replies

static void QLMPutStatus(QLMText *text, const QLMMessage *reply) {
    QLMAdapterStatus status;
    if (QLMReplyAdapterStatus(reply, &status) != QLMAdapterStatusOK) {
        QLMPut(text, "status that does not read");
        return;
    }
    QLMPut(text, "status: ");
    if (!status.knob) {
        QLMPut(text, "no knob");
    } else if (status.hasKnobPosition) {
        QLMPut(text, "knob at ");
        QLMPutDecibels(text, status.knobTenths / 10.0, 1);
    } else {
        QLMPut(text, "knob in, no position");
    }
    if (!status.mic) {
        QLMPut(text, ", no mic");
    } else {
        QLMPut(text, ", mic in");
        if (status.hasMicDE) {
            QLMPut(text, ", DE %u", status.micDE);
        }
        if (status.hasMicDD) {
            QLMPut(text, ", DD %u", status.micDD);
        }
        QLMPut(text, ", raw counts");
    }
    if (status.unknownTag != 0) {
        QLMPut(text, ", tag %02X unknown", status.unknownTag);
    }
}

static void QLMPutTelemetryFields(QLMText *text, const QLMTelemetry *t) {
    if (t->status == QLMTelemetryStatusOn) {
        QLMPut(text, "on");
    } else if (t->status == QLMTelemetryStatusStandby) {
        QLMPut(text, "standby");
    } else if (t->status != QLMTelemetryAbsent) {
        QLMPut(text, "power state %02X, unknown", t->status);
    } else {
        QLMPut(text, "no power state");
    }
    QLMPut(text, ", %u \xC2\xB0" "C", t->temperature);
    switch (t->deviceClass) {
    case QLMTelemetryAbsent: break;
    case QLMTelemetryClassSubwoofer: QLMPut(text, ", subwoofer"); break;
    case QLMTelemetryClassTwoWay: QLMPut(text, ", two- or three-way"); break;
    case QLMTelemetryClassStandby: QLMPut(text, ", class 03 of standby"); break;
    default: QLMPut(text, ", class %02X, unknown", t->deviceClass); break;
    }
    const struct {
        const char *name;
        int16_t value;
    } meters[] = {{"in", t->inputMeter}, {"HF", t->hfMeter}, {"mid", t->midMeter}, {"LF", t->lfMeter}, {"sub", t->subMeter}};
    const char *separator = "; meters ";
    for (size_t i = 0; i < sizeof meters / sizeof meters[0]; i++) {
        if (meters[i].value != QLMTelemetryAbsent) {
            QLMPut(text, "%s%s %d", separator, meters[i].name, meters[i].value);
            separator = ", ";
        }
    }
    int32_t wake = QLMTelemetryWakeCount(t);
    if (wake != QLMTelemetryAbsent) {
        QLMPut(text, "; woke %d s ago", wake);
    } else if (t->wakeSeconds != QLMTelemetryAbsent) {
        QLMPut(text, "; woke %d s ago, mod 256", t->wakeSeconds);
    }
}

static void QLMPutTelemetry(QLMText *text, const QLMMessage *reply) {
    QLMTelemetry telemetry;
    QLMTelemetryStatus status = QLMReplyTelemetry(reply, &telemetry);
    bool busy = reply->length >= 2 && QLMReplyIsBusyMarker(reply->payload[1]);
    switch (status) {
    case QLMTelemetryOK:
    case QLMTelemetryErrorUnknownTag:
        QLMPut(text, "telemetry%s: ", busy ? ", busy" : "");
        QLMPutTelemetryFields(text, &telemetry);
        if (status == QLMTelemetryErrorUnknownTag) {
            QLMPut(text, "; then tag %02X, unknown", telemetry.unknownTag);
        }
        return;
    case QLMTelemetryErrorPartial:
        QLMPut(text, "first part of a split frame%s: ", busy ? ", busy" : "");
        QLMPutTelemetryFields(text, &telemetry);
        return;
    case QLMTelemetryErrorTruncated:
        QLMPut(text, "telemetry cut off mid-field");
        return;
    case QLMTelemetryErrorNotTelemetry:
        if (reply->length == 1) {
            QLMPut(text, "no new telemetry");
        } else if (QLMReplyIsBusy(reply)) {
            QLMPut(text, "busy, no new telemetry");
        } else {
            QLMPut(text, "no 41: the second part of a split frame");
        }
        return;
    }
}

static void QLMPutText(QLMText *text, const char *what, const QLMMessage *reply) {
    char value[QLMPayloadMax + 1];
    if (!QLMReplyText(reply, value, sizeof value)) {
        QLMPut(text, "%s that does not read", what);
        return;
    }
    QLMPut(text, "%s %s", what, value);
}

static void QLMPutSystemInfo(QLMText *text, const QLMMessage *reply) {
    char info[QLMPayloadMax + 1];
    char model[64];
    char firmware[64];
    if (QLMReplyText(reply, info, sizeof info) &&
        QLMSystemInfoParse(info, model, sizeof model, firmware, sizeof firmware)) {
        QLMPut(text, "system info: %s", model);
        if (firmware[0] != '\0') {
            QLMPut(text, ", firmware %s", firmware);
        }
        return;
    }
    QLMPutText(text, "system info", reply);
}

void QLMDescribeReply(const QLMMessage *reply, const QLMMessage *request, char *out, size_t capacity) {
    QLMText text = QLMTextStart(out, capacity);
    if (QLMReplyIsNoAnswer(reply)) {
        QLMPut(&text, "no answer");
        return;
    }
    if (reply == NULL || reply->address != QLMAddressReply || reply->length == 0 || reply->payload[0] != 0x09) {
        QLMPut(&text, "a frame of no reply's shape");
        return;
    }
    if (request == NULL || request->length == 0) {
        if (QLMReplyIsAdapterStatus(reply)) {
            QLMPutStatus(&text, reply);
        } else if (QLMReplyIsSystemInfo(reply)) {
            QLMPutSystemInfo(&text, reply);
        } else {
            QLMPut(&text, "a reply with no request to read it by");
        }
        return;
    }
    uint8_t opcode = request->payload[0];
    uint8_t id[3];
    if (opcode == 0xFE && QLMReplyHardwareID(reply, id)) {
        QLMPut(&text, "hardware ID %02X %02X %02X", id[0], id[1], id[2]);
        return;
    }
    uint8_t session = 0;
    if (QLMLeaseHardwareID(request, id) && QLMReplySessionAck(reply, &session)) {
        QLMPut(&text, "lease taken, session %02X", session);
        if (session != request->payload[4]) {
            QLMPut(&text, ", not the %02X asked", request->payload[4]);
        }
        return;
    }
    if (opcode == 0x08 && request->address == QLMAddressAdapter) {
        if (QLMReplyIsAdapterStatus(reply)) {
            QLMPutStatus(&text, reply);
        } else {
            QLMPut(&text, "no status's shape");
        }
        return;
    }
    if (opcode == 0x08) {
        QLMPutTelemetry(&text, reply);
        return;
    }
    if (opcode == 0x19) {
        QLMPutText(&text, "serial", reply);
        return;
    }
    if (opcode == 0x39) {
        QLMPutSystemInfo(&text, reply);
        return;
    }
    if (opcode == 0x22) {
        QLMPutText(&text, "the adapter's identity:", reply);
        return;
    }
    if (opcode == 0x51) {
        QLMPutText(&text, "51 82's reply, meaning unknown:", reply);
        return;
    }
    if (QLMReplyIsAck(reply)) {
        QLMPut(&text, "ack");
        return;
    }
    if (QLMReplyIsBusy(reply)) {
        QLMPut(&text, "ack, busy %02X", reply->payload[1]);
        return;
    }
    QLMPut(&text, "a reply of %zu bytes, unexpected for %02X", reply->length, opcode);
}

#pragma mark - PEQ bands

static double QLMFloatAt(const uint8_t *bytes) {
    uint32_t bits = (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 | (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

// An RBJ shelf of linear gain A (10^(dB/40)) with the given poles: its
// cos w0, its s (2 sqrt(A) alpha), and the numerator it would have. False
// where no shelf has those poles.
typedef struct {
    double c, s, b0, b1, b2;
} QLMShelfFit;

static bool QLMFitShelf(bool low, double A, double a1, double a2, QLMShelfFit *fit) {
    double sign = low ? 1 : -1;
    double r = -sign * a1 / (1 + a2);
    double c = sign * (r * (A + 1) - (A - 1)) / ((A + 1) - r * (A - 1));
    if (!(c > -1 && c < 1)) {
        return false;
    }
    double a0 = 2 * ((A + 1) + sign * (A - 1) * c) / (1 + a2);
    double s = (1 - a2) * a0 / 2;
    if (!(s > 0)) {
        return false;
    }
    double edge = (A + 1) - sign * (A - 1) * c;
    fit->c = c;
    fit->s = s;
    fit->b0 = A * (edge + s) / a0;
    fit->b1 = sign * 2 * A * ((A - 1) - sign * (A + 1) * c) / a0;
    fit->b2 = A * (edge - s) / a0;
    return true;
}

static double QLMShelfMiss(bool low, double gain, double b0, double b1, double b2, double a1, double a2) {
    QLMShelfFit fit;
    if (!QLMFitShelf(low, pow(10, gain / 40), a1, a2, &fit)) {
        return INFINITY;
    }
    return fmax(fabs(fit.b0 - b0), fmax(fabs(fit.b1 - b1), fabs(fit.b2 - b2)));
}

// TRAP: a band's gain at DC or at Nyquist divides two tiny numbers at a
// low w0, and floats leave it off by a dB or more. So the shelf's gain is
// the one whose rebuilt numerator matches, searched from -40 to +40 dB.
static bool QLMReadShelf(bool low, double b0, double b1, double b2, double a1, double a2, QLMBandReading *band) {
    double best = 0;
    double bestMiss = INFINITY;
    for (double gain = -40; gain <= 40; gain += 0.5) {
        double miss = QLMShelfMiss(low, gain, b0, b1, b2, a1, a2);
        if (miss < bestMiss) {
            bestMiss = miss;
            best = gain;
        }
    }
    double lo = best - 0.5;
    double hi = best + 0.5;
    for (int i = 0; i < 40; i++) {
        double m1 = lo + (hi - lo) / 3;
        double m2 = hi - (hi - lo) / 3;
        if (QLMShelfMiss(low, m1, b0, b1, b2, a1, a2) < QLMShelfMiss(low, m2, b0, b1, b2, a1, a2)) {
            hi = m2;
        } else {
            lo = m1;
        }
    }
    best = (lo + hi) / 2;
    QLMShelfFit fit;
    double A = pow(10, best / 40);
    if (!(QLMShelfMiss(low, best, b0, b1, b2, a1, a2) < 1e-5) || !QLMFitShelf(low, A, a1, a2, &fit)) {
        return false;
    }
    double w0 = acos(fit.c);
    double alpha = fit.s / (2 * sqrt(A));
    band->shape = low ? QLMBandShapeLowShelf : QLMBandShapeHighShelf;
    band->frequency = w0 / (2 * M_PI);
    band->q = sin(w0) / (2 * alpha);
    band->gainDecibels = best;
    return true;
}

QLMBandReading QLMReadPEQBand(const uint8_t coefficients[20], double designRate) {
    QLMBandReading band = {QLMBandShapeUnknown, 0, 0, 0, 0};
    double b0 = QLMFloatAt(coefficients);
    double b1 = QLMFloatAt(coefficients + 4);
    double b2 = QLMFloatAt(coefficients + 8);
    // The wire carries -a1 and -a2.
    double a1 = -QLMFloatAt(coefficients + 12);
    double a2 = -QLMFloatAt(coefficients + 16);
    if (b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0) {
        band.shape = QLMBandShapeFlat;
        return band;
    }
    if (!(fabs(a2) < 1 && fabs(a1) < 1 + a2)) {
        return band;
    }
    bool read = false;
    if (b1 == a1) {
        // A peak: b1 and a1 are both -2 cos w0 over a0, the same float.
        double c = -a1 / (1 + a2);
        double alphaOverA = (1 - a2) / (1 + a2);
        double alphaTimesA = (b0 - b2) / (1 + a2);
        if (c > -1 && c < 1 && alphaOverA > 0 && alphaTimesA > 0) {
            double w0 = acos(c);
            band.shape = QLMBandShapePeak;
            band.frequency = w0 / (2 * M_PI);
            band.q = sin(w0) / (2 * sqrt(alphaOverA * alphaTimesA));
            band.gainDecibels = 20 * log10(alphaTimesA / alphaOverA);
            read = true;
        }
    } else {
        QLMBandReading low = band;
        QLMBandReading high = band;
        bool isLow = QLMReadShelf(true, b0, b1, b2, a1, a2, &low);
        bool isHigh = QLMReadShelf(false, b0, b1, b2, a1, a2, &high);
        // A shelf with no gain is flat, and either shape fits it.
        if (isLow != isHigh || (isLow && fabs(low.gainDecibels) < 0.01)) {
            band = isLow ? low : high;
            read = true;
        }
    }
    if (!read) {
        return band;
    }
    double w0 = 2 * M_PI * band.frequency;
    band.spread = 1.5e-7 / (w0 * w0);
    if (designRate > 0) {
        band.frequency *= designRate;
    }
    return band;
}
