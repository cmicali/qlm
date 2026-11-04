#ifndef QLMKNOBMATH_H
#define QLMKNOBMATH_H

#include <math.h>

// The knob's angle math. Angles are in degrees, clockwise from straight up,
// in a view whose y grows down. The sweep is the pack's: -135 at the range's
// bottom to +135 at its top. Only the pointer turns.

#define QLM_KNOB_START_DEGREES (-135.0)
#define QLM_KNOB_END_DEGREES 135.0
#define QLM_KNOB_SWEEP_DEGREES 270.0
// GLM's volume step.
#define QLM_KNOB_STEP_DECIBELS 0.5

static inline double QLMKnobClamp(double value, double low, double high) {
    return value < low ? low : value > high ? high : value;
}

// The level's place in the range, 0 to 1. An empty range is at 0.
static inline double QLMKnobFraction(double decibels, double minimum, double maximum) {
    if (!(maximum > minimum) || !isfinite(decibels)) {
        return 0;
    }
    return QLMKnobClamp((decibels - minimum) / (maximum - minimum), 0, 1);
}

static inline double QLMKnobAngleForDecibels(double decibels, double minimum, double maximum) {
    return QLM_KNOB_START_DEGREES + QLMKnobFraction(decibels, minimum, maximum) * QLM_KNOB_SWEEP_DEGREES;
}

// An angle outside the sweep is its nearer end.
static inline double QLMKnobDecibelsForAngle(double degrees, double minimum, double maximum) {
    double fraction = (QLMKnobClamp(degrees, QLM_KNOB_START_DEGREES, QLM_KNOB_END_DEGREES) - QLM_KNOB_START_DEGREES)
                      / QLM_KNOB_SWEEP_DEGREES;
    return minimum + fraction * (maximum - minimum);
}

// The nearest 0.5 dB step in the range. A range end off the steps gives
// the nearest step inside it.
static inline double QLMKnobSnap(double decibels, double minimum, double maximum) {
    double low = ceil(minimum / QLM_KNOB_STEP_DECIBELS) * QLM_KNOB_STEP_DECIBELS;
    double high = floor(maximum / QLM_KNOB_STEP_DECIBELS) * QLM_KNOB_STEP_DECIBELS;
    double stepped = round(decibels / QLM_KNOB_STEP_DECIBELS) * QLM_KNOB_STEP_DECIBELS;
    if (high < low) {
        return low;
    }
    return QLMKnobClamp(stepped, low, high);
}

// One step up or down from the level, snapped and kept in the range.
static inline double QLMKnobStep(double decibels, int steps, double minimum, double maximum) {
    return QLMKnobSnap(QLMKnobSnap(decibels, minimum, maximum) + steps * QLM_KNOB_STEP_DECIBELS, minimum, maximum);
}

// Tick `index` of `count`, spread over the sweep, both ends included. One
// tick sits at the top.
static inline double QLMKnobTickAngle(int index, int count) {
    if (count <= 1) {
        return 0;
    }
    return QLM_KNOB_START_DEGREES + index * QLM_KNOB_SWEEP_DEGREES / (count - 1);
}

// The angle from the center to a point (dx, dy), y down, in -180 to 180.
static inline double QLMKnobAngleOfOffset(double dx, double dy) {
    return atan2(dx, -dy) * 180.0 / M_PI;
}

// The level a drag points at. In the dead zone below the knob, between the
// sweep's ends, it holds the end nearer the previous level, so the pointer
// never jumps from one end to the other.
static inline double QLMKnobDecibelsForDrag(double dx, double dy, double previous, double minimum, double maximum) {
    double degrees = QLMKnobAngleOfOffset(dx, dy);
    if (degrees > QLM_KNOB_END_DEGREES || degrees < QLM_KNOB_START_DEGREES) {
        return QLMKnobFraction(previous, minimum, maximum) >= 0.5 ? QLMKnobSnap(maximum, minimum, maximum)
                                                                  : QLMKnobSnap(minimum, minimum, maximum);
    }
    return QLMKnobSnap(QLMKnobDecibelsForAngle(degrees, minimum, maximum), minimum, maximum);
}

// A point at `radius` from (cx, cy) along `degrees`, y down.
static inline void QLMKnobPointAt(double cx, double cy, double radius, double degrees, double *x, double *y) {
    double radians = degrees * M_PI / 180.0;
    *x = cx + radius * sin(radians);
    *y = cy - radius * cos(radians);
}

#endif
