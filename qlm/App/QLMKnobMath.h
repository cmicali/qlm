#ifndef QLMKNOBMATH_H
#define QLMKNOBMATH_H

#include <math.h>

#include "QLMCommands.h"

// The knob's angle math. Angles are in degrees, clockwise from straight up,
// in a view whose y grows down. The sweep is the pack's: -135 at the range's
// bottom to +135 at its top. Only the pointer turns.

#define QLM_KNOB_START_DEGREES (-135.0)
#define QLM_KNOB_SWEEP_DEGREES 270.0
#define QLM_KNOB_END_DEGREES (QLM_KNOB_START_DEGREES + QLM_KNOB_SWEEP_DEGREES)
#define QLM_KNOB_STEP_DECIBELS QLMVolumeDecibelsStep

static inline double QLMKnobRadians(double degrees) {
    return degrees * M_PI / 180.0;
}

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

// The nearest 0.5 dB step in the range. A range end off the steps gives
// the nearest step inside it.
static inline double QLMKnobSnap(double decibels, double minimum, double maximum) {
    double low = ceil(minimum / QLM_KNOB_STEP_DECIBELS) * QLM_KNOB_STEP_DECIBELS;
    double high = floor(maximum / QLM_KNOB_STEP_DECIBELS) * QLM_KNOB_STEP_DECIBELS;
    double stepped = QLMNearestStepDecibels(decibels);
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

// The mouse's angle for a drag, or NaN within `deadRadius` of the center,
// where a few points of jitter are tens of degrees.
static inline double QLMKnobDragAngle(double dx, double dy, double deadRadius) {
    return hypot(dx, dy) < deadRadius ? NAN : QLMKnobAngleOfOffset(dx, dy);
}

// The level a turn of `degrees` moves, at the sweep's rate.
static inline double QLMKnobDecibelsForTurn(double degrees, double minimum, double maximum) {
    return degrees / QLM_KNOB_SWEEP_DEGREES * (maximum - minimum);
}

// One step of a relative drag. A step in or out of the dead zone, past the
// cap, or from or to a NaN angle keeps the level. `level` is unsnapped, so a
// slow drag adds up.
static inline double QLMKnobDragStep(double level, double fromDegrees, double toDegrees, double minimum, double maximum) {
    double turned = toDegrees - fromDegrees;
    if (QLMKnobInDeadZone(fromDegrees) || QLMKnobInDeadZone(toDegrees) || !(maximum > minimum)
        || !(fabs(turned) <= QLM_KNOB_MAX_STEP_DEGREES)) {
        return level;
    }
    return QLMKnobClamp(level + QLMKnobDecibelsForTurn(turned, minimum, maximum), minimum, maximum);
}

// A vertical drag's travel over the whole range, in points. Shift's finer
// drag takes four times as far.
#define QLM_KNOB_DRAG_TRAVEL_POINTS 200.0
#define QLM_KNOB_FINE_DRAG_TRAVEL_POINTS 800.0

// One step of a vertical drag: up is louder, and `travel` points, `dy`
// counted down, turn the whole sweep. One event turns at most the angular
// drag's cap, so a leap of the mouse can't jump the level. `level` is
// unsnapped, so a slow drag adds up.
static inline double QLMKnobDragVertical(double level, double dy, double minimum, double maximum, double travel) {
    if (!(maximum > minimum) || !(travel > 0) || !isfinite(dy)) {
        return level;
    }
    double turned = QLMKnobClamp(-dy / travel * QLM_KNOB_SWEEP_DEGREES, -QLM_KNOB_MAX_STEP_DEGREES,
                                 QLM_KNOB_MAX_STEP_DEGREES);
    return QLMKnobClamp(level + QLMKnobDecibelsForTurn(turned, minimum, maximum), minimum, maximum);
}

// A point at `radius` from (cx, cy) along `degrees`, y down.
static inline void QLMKnobPointAt(double cx, double cy, double radius, double degrees, double *x, double *y) {
    double radians = QLMKnobRadians(degrees);
    *x = cx + radius * sin(radians);
    *y = cy - radius * cos(radians);
}

#endif
