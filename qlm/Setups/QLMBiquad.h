#ifndef QLMBIQUAD_H
#define QLMBIQUAD_H

#include <stdbool.h>
#include <stdint.h>

// One second-order section, normalized by a0, in the textbook form
// y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2. The wire wants a1 and a2 with
// their signs flipped; QLMBiquadPack does that.
typedef struct {
    double b0, b1, b2, a1, a2;
} QLMBiquad;

// GLM designs the shelves in Q form with fixed Qs.
#define QLMBiquadLowShelfQ 0.3
#define QLMBiquadHighShelfQ 0.5

// RBJ designs at the given rate. A gain of exactly 0 dB gives the bypass.
QLMBiquad QLMBiquadBypass(void);
QLMBiquad QLMBiquadPeak(double frequency, double gainDecibels, double q, double sampleRate);
QLMBiquad QLMBiquadLowShelf(double frequency, double gainDecibels, double sampleRate);
QLMBiquad QLMBiquadHighShelf(double frequency, double gainDecibels, double sampleRate);

bool QLMBiquadIsBypass(const QLMBiquad *biquad);
// Both poles inside the unit circle.
bool QLMBiquadIsStable(const QLMBiquad *biquad);
// |H| at a frequency, for tests and display.
double QLMBiquadMagnitude(const QLMBiquad *biquad, double frequency, double sampleRate);

// The five little-endian floats a PEQ frame carries: b0, b1, b2, -a1, -a2.
#define QLMBiquadPackedSize 20
void QLMBiquadPack(const QLMBiquad *biquad, uint8_t out[QLMBiquadPackedSize]);

#endif
