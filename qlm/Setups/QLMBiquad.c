#include "QLMBiquad.h"

#include <math.h>
#include <string.h>

QLMBiquad QLMBiquadBypass(void) {
    QLMBiquad biquad = {1, 0, 0, 0, 0};
    return biquad;
}

// TRAP: the division is in float. Dividing in double and rounding after
// misses GLM's coefficients by a bit or two.
static QLMBiquad QLMBiquadNormalize(double b0, double b1, double b2, double a0, double a1, double a2) {
    float scale = (float)a0;
    QLMBiquad biquad = {(float)b0 / scale, (float)b1 / scale, (float)b2 / scale, (float)a1 / scale, (float)a2 / scale};
    return biquad;
}

QLMBiquad QLMBiquadPeak(double frequency, double gainDecibels, double q, double sampleRate) {
    if (gainDecibels == 0) {
        return QLMBiquadBypass();
    }
    double w0 = 2 * M_PI * frequency / sampleRate;
    double A = pow(10, gainDecibels / 40);
    double alpha = sin(w0) / (2 * q);
    double c = cos(w0);
    return QLMBiquadNormalize(1 + alpha * A, -2 * c, 1 - alpha * A, 1 + alpha / A, -2 * c, 1 - alpha / A);
}

// TRAP: GLM rounds a shelf's w0 to float before its sine and cosine. In
// double, a high shelf at 8 kHz misses GLM's by a bit or more in four of
// its five coefficients.
static double QLMShelfW0(double frequency, double sampleRate) {
    return (float)(2 * M_PI * frequency / sampleRate);
}

QLMBiquad QLMBiquadLowShelf(double frequency, double gainDecibels, double q, double sampleRate) {
    if (gainDecibels == 0) {
        return QLMBiquadBypass();
    }
    double w0 = QLMShelfW0(frequency, sampleRate);
    double A = pow(10, gainDecibels / 40);
    double alpha = sin(w0) / (2 * q);
    double c = cos(w0);
    double s = 2 * sqrt(A) * alpha;
    return QLMBiquadNormalize(A * ((A + 1) - (A - 1) * c + s), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - s),
                              (A + 1) + (A - 1) * c + s, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - s);
}

QLMBiquad QLMBiquadHighShelf(double frequency, double gainDecibels, double q, double sampleRate) {
    if (gainDecibels == 0) {
        return QLMBiquadBypass();
    }
    double w0 = QLMShelfW0(frequency, sampleRate);
    double A = pow(10, gainDecibels / 40);
    double alpha = sin(w0) / (2 * q);
    double c = cos(w0);
    double s = 2 * sqrt(A) * alpha;
    return QLMBiquadNormalize(A * ((A + 1) + (A - 1) * c + s), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - s),
                              (A + 1) - (A - 1) * c + s, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - s);
}

bool QLMBiquadIsBypass(const QLMBiquad *biquad) {
    return biquad->b0 == 1 && biquad->b1 == 0 && biquad->b2 == 0 && biquad->a1 == 0 && biquad->a2 == 0;
}

bool QLMBiquadIsStable(const QLMBiquad *biquad) {
    // The Jury conditions for z^2 + a1 z + a2.
    return fabs(biquad->a2) < 1 && fabs(biquad->a1) < 1 + biquad->a2;
}

double QLMBiquadMagnitude(const QLMBiquad *biquad, double frequency, double sampleRate) {
    double w = 2 * M_PI * frequency / sampleRate;
    double c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w);
    double nr = biquad->b0 + biquad->b1 * c1 + biquad->b2 * c2;
    double ni = -(biquad->b1 * s1 + biquad->b2 * s2);
    double dr = 1 + biquad->a1 * c1 + biquad->a2 * c2;
    double di = -(biquad->a1 * s1 + biquad->a2 * s2);
    return sqrt((nr * nr + ni * ni) / (dr * dr + di * di));
}

static void QLMPutFloat(uint8_t *out, double value) {
    float f = (float)value;
    uint32_t bits;
    memcpy(&bits, &f, sizeof bits);
    out[0] = (uint8_t)bits;
    out[1] = (uint8_t)(bits >> 8);
    out[2] = (uint8_t)(bits >> 16);
    out[3] = (uint8_t)(bits >> 24);
}

void QLMBiquadPack(const QLMBiquad *biquad, uint8_t out[QLMBiquadPackedSize]) {
    QLMPutFloat(out, biquad->b0);
    QLMPutFloat(out + 4, biquad->b1);
    QLMPutFloat(out + 8, biquad->b2);
    // 0 - x, not -x: the bypass must not carry a negative zero.
    QLMPutFloat(out + 12, 0.0 - biquad->a1);
    QLMPutFloat(out + 16, 0.0 - biquad->a2);
}
