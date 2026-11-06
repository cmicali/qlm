#ifndef QLMDESCRIBE_H
#define QLMDESCRIBE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "QLMFrame.h"

// Plain words for a frame on the bus, for the traffic view and its text.
// Each reads only bytes, and says "unknown" where docs/protocol.md does. It
// covers every frame in the captures, GLM's refused frames among them.

// Room for any description, NUL included.
#define QLMDescriptionMax 320

// What the bytes cannot say. NAN or 0 when not known.
typedef struct {
    // The user's ceiling as the frame went out. A volume frame at it, or
    // above it, says so.
    double ceilingDecibels;
    // The design rate of the PEQ bands of the monitor a frame names, in Hz.
    // The setup file states it per band. With 0, a band's frequency reads as
    // a fraction of the rate.
    double designRate;
} QLMDescribeContext;

// "broadcast FF", "adapter multicast F0", "adapter 01", or "session 0B".
void QLMDescribeAddress(uint8_t address, char *out, size_t capacity);

// What a frame the host sends does: "volume −30.0 dB, at the ceiling",
// "lease session 0B to hardware ID 12 34 56", "PEQ slot 05: peak 1 kHz,
// Q 2, −3.0 dB". The context may be NULL.
void QLMDescribeRequest(const QLMMessage *request, const QLMDescribeContext *context, char *out, size_t capacity);

// What a reply says, read against the request it answers, which may be
// NULL when none was waiting. Replies name no request, so without one only
// the no-answer frame and the two shapes that answer one request each read.
void QLMDescribeReply(const QLMMessage *reply, const QLMMessage *request, char *out, size_t capacity);

// A PEQ band read back from the five floats a 10 0E frame carries.
typedef enum {
    QLMBandShapeFlat = 0,  // 1, 0, 0, 0, 0
    QLMBandShapePeak,
    QLMBandShapeLowShelf,
    QLMBandShapeHighShelf,
    QLMBandShapeUnknown,   // no RBJ peak or shelf gives it
} QLMBandShape;

typedef struct {
    QLMBandShape shape;
    // Hz at the design rate given, or a fraction of the rate with none.
    double frequency;
    double q;
    double gainDecibels;
    // How far off the frequency and Q may read, as a fraction of each.
    // A float's rounding moves cos w0 by about 1e-7, so a low w0 reads
    // loosely: a few percent at 25 Hz at 96 kHz.
    double spread;
} QLMBandReading;

// Inverts the RBJ designs Setups' QLMBiquad makes. Floats carry about
// seven digits, so a band reads back to about four, but less near DC.
QLMBandReading QLMReadPEQBand(const uint8_t coefficients[20], double designRate);

#endif
