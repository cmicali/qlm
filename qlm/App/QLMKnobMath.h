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

// Below the knob, between the sweep's ends.
static inline int QLMKnobInDeadZone(double degrees) {
    return degrees > QLM_KNOB_END_DEGREES || degrees < QLM_KNOB_START_DEGREES;
}

// The most one drag event may turn the knob. A larger turn is the mouse
// crossing the gap below the knob, or passing over its center, in one event.
#define QLM_KNOB_MAX_STEP_DEGREES 45.0

// One step of a drag, which is relative: the level moves by the angle the
// mouse turned about the center since the last step, at the sweep's rate,
// and stays in the range. The listener comes first, so a click moves
// nothing, and a step from or into the dead zone, or one that turns more
// than QLM_KNOB_MAX_STEP_DEGREES, keeps the level. Both angles are then in
// the sweep, so the turn is their plain difference, never wrapped. `level`
// is unsnapped, so a slow drag still adds up. Snap what it returns to send
// it.
static inline double QLMKnobDragStep(double level, double fromDegrees, double toDegrees, double minimum, double maximum) {
    double turned = toDegrees - fromDegrees;
    if (QLMKnobInDeadZone(fromDegrees) || QLMKnobInDeadZone(toDegrees) || !(maximum > minimum)
        || !(fabs(turned) <= QLM_KNOB_MAX_STEP_DEGREES)) {
        return level;
    }
    double moved = turned / QLM_KNOB_SWEEP_DEGREES * (maximum - minimum);
    return QLMKnobClamp(level + moved, minimum, maximum);
}

// A point at `radius` from (cx, cy) along `degrees`, y down.
static inline void QLMKnobPointAt(double cx, double cy, double radius, double degrees, double *x, double *y) {
    double radians = degrees * M_PI / 180.0;
    *x = cx + radius * sin(radians);
    *y = cy - radius * cos(radians);
}

#endif
