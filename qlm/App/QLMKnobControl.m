#import "QLMKnobControl.h"

#import "QLMKnobMath.h"
#import "QLMSkinDrawing.h"

// A trackpad's scroll moves a step per this many points.
static const CGFloat QLMKnobScrollPointsPerStep = 12;
// A drag within this part of the body's diameter from the center points
// nowhere: there a few points of jitter are tens of degrees.
static const CGFloat QLMKnobDeadFraction = 0.25;

@implementation QLMKnobControl {
    double _value;
    CGFloat _scrolled;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithSkin:skin];
    if (self) {
        _minValue = -80;
        _maxValue = 0;
        _value = -80;
    }
    return self;
}

- (double)doubleValue {
    return _value;
}

- (void)setDoubleValue:(double)value {
    _value = isfinite(value) ? QLMKnobClamp(value, self.minValue, MAX(self.minValue, self.maxValue)) : self.minValue;
    self.needsDisplay = YES;
}

- (void)setMinValue:(double)minValue {
    _minValue = minValue;
    self.doubleValue = _value;
}

- (void)setMaxValue:(double)maxValue {
    _maxValue = maxValue;
    self.doubleValue = _value;
}

// A move by the user: snapped, and sent when it changes the level's step.
// A level set in code off a step, as -40.2, counts as its nearest step, so a
// tiny turn never sends -40.0.
- (void)moveTo:(double)decibels {
    double snapped = QLMKnobSnap(decibels, self.minValue, self.maxValue);
    if (snapped == QLMKnobSnap(_value, self.minValue, self.maxValue)) {
        return;
    }
    _value = snapped;
    self.needsDisplay = YES;
    [self sendAction:self.action to:self.target];
}

- (NSPoint)center {
    return NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
}

// The mouse's angle about the center, or NAN this near the center, where
// it points nowhere.
- (double)angleOfEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint center = [self center];
    double dx = point.x - center.x;
    double dy = point.y - center.y;
    return hypot(dx, dy) < self.skin.knob.bodySize * QLMKnobDeadFraction ? NAN : QLMKnobAngleOfOffset(dx, dy);
}

// A relative drag: the press moves nothing, and each drag after it turns
// the level by the angle the mouse turned.
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) {
        return;
    }
    [self.window makeFirstResponder:self];
    self.pressed = YES;
    double from = [self angleOfEvent:event];
    double level = QLMKnobSnap(_value, self.minValue, self.maxValue);
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (next.type == NSEventTypeLeftMouseUp) {
            self.pressed = NO;
            return;
        }
        double to = [self angleOfEvent:next];
        if (isfinite(from) && isfinite(to)) {
            level = QLMKnobDragStep(level, from, to, self.minValue, self.maxValue);
            [self moveTo:level];
        }
        from = to;
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.enabled) {
        return;
    }
    // Up is louder whichever way the user's scrolling goes.
    CGFloat delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1);
    int steps = 0;
    if (event.hasPreciseScrollingDeltas) {
        _scrolled += delta;
        steps = (int)trunc(_scrolled / QLMKnobScrollPointsPerStep);
        _scrolled -= steps * QLMKnobScrollPointsPerStep;
    }
    else if (delta != 0) {
        steps = delta > 0 ? 1 : -1;
    }
    if (steps != 0) {
        [self moveTo:QLMKnobStep(_value, steps, self.minValue, self.maxValue)];
    }
}

- (void)keyDown:(NSEvent *)event {
    unichar key = event.charactersIgnoringModifiers.length > 0 ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    int steps = key == NSUpArrowFunctionKey || key == NSRightArrowFunctionKey ? 1
                : key == NSDownArrowFunctionKey || key == NSLeftArrowFunctionKey ? -1 : 0;
    // Not QLMSkinControl's, whose Space and Return send the action with no
    // change.
    if (steps == 0 || !self.enabled) {
        [self.nextResponder keyDown:event];
        return;
    }
    [self moveTo:QLMKnobStep(_value, steps, self.minValue, self.maxValue)];
}

static void QLMKnobStrokeRadial(NSPoint center, CGFloat inner, CGFloat outer, double degrees, CGFloat width, NSColor *color) {
    double x0, y0, x1, y1;
    QLMKnobPointAt(center.x, center.y, inner, degrees, &x0, &y0);
    QLMKnobPointAt(center.x, center.y, outer, degrees, &x1, &y1);
    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(x0, y0)];
    [line lineToPoint:NSMakePoint(x1, y1)];
    line.lineWidth = width;
    line.lineCapStyle = NSLineCapStyleRound;
    [color setStroke];
    [line stroke];
}

// From `from` to `to`, in the knob's degrees. The path's angles run from
// +x toward +y, which in a flipped view is clockwise, so up is -90.
static void QLMKnobStrokeArc(NSPoint center, CGFloat radius, double from, double to, CGFloat width, NSColor *color) {
    if (to <= from) {
        return;
    }
    NSBezierPath *arc = [NSBezierPath bezierPath];
    [arc appendBezierPathWithArcWithCenter:center radius:radius startAngle:from - 90 endAngle:to - 90 clockwise:NO];
    arc.lineWidth = width;
    arc.lineCapStyle = NSLineCapStyleRound;
    [color setStroke];
    [arc stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    QLMSkinKnob *knob = self.skin.knob;
    NSPoint center = [self center];
    CGFloat side = knob.bodySize;
    NSRect body = NSMakeRect(center.x - side / 2, center.y - side / 2, side, side);
    double angle = QLMKnobAngleForDecibels(_value, self.minValue, self.maxValue);

    if (knob.shadow != nil) {
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = QLMSkinNSColor(knob.shadow.color);
        shadow.shadowBlurRadius = knob.shadow.blur;
        shadow.shadowOffset = NSMakeSize(knob.shadow.offset.width, -knob.shadow.offset.height);  // y up
        [shadow set];
        [QLMSkinNSColor(knob.shadow.color) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(body, 1, 1)] fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    for (int i = 0; i < knob.tickCount; i++) {
        QLMKnobStrokeRadial(center, knob.tickInner, knob.tickOuter, QLMKnobTickAngle(i, (int)knob.tickCount), knob.tickWidth,
                            QLMSkinNSColor(knob.tickColor));
    }

    if (knob.hasArc) {
        QLMKnobStrokeArc(center, knob.arcRadius, QLM_KNOB_START_DEGREES, QLM_KNOB_END_DEGREES, knob.arcWidth,
                         QLMSkinNSColor(knob.arcTrack));
        QLMSkinColor fill = knob.arcFill;
        if (!self.enabled) {
            fill.alpha *= 0.4;
        }
        QLMKnobStrokeArc(center, knob.arcRadius, QLM_KNOB_START_DEGREES, angle, knob.arcWidth, QLMSkinNSColor(fill));
    }

    QLMSkinDrawStyle(self.skin, knob.body, QLMSkinKnobState(self.enabled, self.pressed, self.hovered), body, YES);

    QLMSkinColor pointer = self.enabled ? knob.pointerColor : knob.pointerDisabledColor;
    QLMKnobStrokeRadial(center, knob.pointerInner, knob.pointerOuter, angle, knob.pointerWidth, QLMSkinNSColor(pointer));

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(knob.focus, body, YES);
    }
}

@end
