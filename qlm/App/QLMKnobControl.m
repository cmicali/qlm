#import "QLMKnobControl.h"

#import "PlatformColor.h"
#import "QLMFormat.h"
#import "QLMKnobMath.h"
#import "QLMSkinDrawing.h"

// A trackpad's scroll moves a step per this many points.
static const CGFloat QLMKnobScrollPointsPerStep = 12;
// A drag within this part of the body's diameter from the center points
// nowhere.
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
        self.accessibilityRole = NSAccessibilitySliderRole;
    }
    return self;
}

- (id)accessibilityValue {
    return @(_value);
}

- (NSString *)accessibilityValueDescription {
    return QLMDecibelsText(_value);
}

- (double)levelSteppedBy:(int)steps {
    return QLMKnobStep(_value, steps, self.minValue, self.maxValue);
}

- (BOOL)canStepBy:(int)steps {
    return self.enabled && !self.waitsForLevel && [self levelSteppedBy:steps] != QLMKnobSnap(_value, self.minValue, self.maxValue);
}

- (BOOL)stepBy:(int)steps {
    if (![self canStepBy:steps]) {
        return NO;
    }
    [self moveTo:[self levelSteppedBy:steps]];
    return YES;
}

- (BOOL)accessibilityPerformIncrement {
    return [self stepBy:1];
}

- (BOOL)accessibilityPerformDecrement {
    return [self stepBy:-1];
}

// Not QLMSkinControl's, which sends the action with the level as it stands,
// off the steps the action promises. A knob has no press.
- (BOOL)accessibilityPerformPress {
    return NO;
}

- (double)doubleValue {
    return _value;
}

- (void)setDoubleValue:(double)value {
    value = isfinite(value) ? QLMKnobClamp(value, self.minValue, MAX(self.minValue, self.maxValue)) : self.minValue;
    if (value == _value) {
        return;
    }
    _value = value;
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

- (NSPoint)pointOfEvent:(NSEvent *)event {
    return [self convertPoint:event.locationInWindow fromView:nil];
}

- (double)angleAt:(NSPoint)point {
    NSPoint center = [self center];
    return QLMKnobDragAngle(point.x - center.x, point.y - center.y, self.skin.knob.bodySize * QLMKnobDeadFraction);
}

// A relative drag: the press moves nothing. A press on the body drags up and
// down. A press outside it, on the ring, turns the knob about its center.
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) {
        return;
    }
    [self.window makeFirstResponder:self];
    self.pressed = YES;
    NSPoint from = [self pointOfEvent:event];
    NSPoint center = [self center];
    BOOL vertical = hypot(from.x - center.x, from.y - center.y) <= self.skin.knob.bodySize / 2;
    double fromAngle = [self angleAt:from];
    double level = QLMKnobSnap(_value, self.minValue, self.maxValue);
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (next.type == NSEventTypeLeftMouseUp) {
            self.pressed = NO;
            return;
        }
        NSPoint to = [self pointOfEvent:next];
        if (vertical) {
            BOOL fine = (next.modifierFlags & NSEventModifierFlagShift) != 0;
            level = QLMKnobDragVertical(level, to.y - from.y, self.minValue, self.maxValue,
                                        fine ? QLM_KNOB_FINE_DRAG_TRAVEL_POINTS : QLM_KNOB_DRAG_TRAVEL_POINTS);
        }
        else {
            double toAngle = [self angleAt:to];
            level = QLMKnobDragStep(level, fromAngle, toAngle, self.minValue, self.maxValue);
            fromAngle = toAngle;
        }
        [self moveTo:level];
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
        [self stepBy:steps];
    }
}

- (void)keyDown:(NSEvent *)event {
    unichar key = event.charactersIgnoringModifiers.length > 0 ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    int steps = key == NSUpArrowFunctionKey || key == NSRightArrowFunctionKey ? 1
                : key == NSDownArrowFunctionKey || key == NSLeftArrowFunctionKey ? -1 : 0;
    // Not QLMSkinControl's, whose Space and Return send the action with no
    // change. An arrow at an end of the range is still the knob's.
    if (steps == 0 || !self.enabled) {
        [self.nextResponder keyDown:event];
        return;
    }
    [self stepBy:steps];
}

static void QLMKnobAppendRadial(NSBezierPath *path, NSPoint center, CGFloat inner, CGFloat outer, double degrees) {
    double x0, y0, x1, y1;
    QLMKnobPointAt(center.x, center.y, inner, degrees, &x0, &y0);
    QLMKnobPointAt(center.x, center.y, outer, degrees, &x1, &y1);
    [path moveToPoint:NSMakePoint(x0, y0)];
    [path lineToPoint:NSMakePoint(x1, y1)];
}

static void QLMKnobStroke(NSBezierPath *path, CGFloat width, NSColor *color) {
    path.lineWidth = width;
    path.lineCapStyle = NSLineCapStyleRound;
    [color setStroke];
    [path stroke];
}

// From `from` to `to`, in the knob's degrees. The path's angles run from
// +x toward +y, which in a flipped view is clockwise, so up is -90.
static NSBezierPath *QLMKnobArc(NSPoint center, CGFloat radius, double from, double to) {
    NSBezierPath *arc = [NSBezierPath bezierPath];
    [arc appendBezierPathWithArcWithCenter:center radius:radius startAngle:from - 90 endAngle:to - 90 clockwise:NO];
    return arc;
}

// A square on the center.
- (NSRect)rectAround:(CGFloat)radius {
    NSPoint center = [self center];
    return NSMakeRect(center.x - radius, center.y - radius, radius * 2, radius * 2);
}

// What no turn changes: the body's cast shadow, the ticks, and the arc's
// track, centered in `rect`.
- (void)drawStillIn:(NSRect)rect {
    QLMSkinKnob *knob = self.skin.knob;
    NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
    if (knob.shadow != nil) {
        CGFloat radius = knob.bodySize / 2 - 1;
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - radius, center.y - radius,
                                                                               radius * 2, radius * 2)];
        // Only the cast shadow stays, so a body that isn't opaque, as a
        // disabled image body, shows no disc through it. TRAP: the erase
        // must stay inside its own transparency layer, or it would punch a
        // hole in whatever is under the knob.
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        CGContextBeginTransparencyLayer(context, NULL);
        QLMSkinDrawShadow(knob.shadow, path, NSColor.blackColor);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
        [NSColor.blackColor setFill];
        [path fill];
        [NSGraphicsContext restoreGraphicsState];
        CGContextEndTransparencyLayer(context);
    }
    if (knob.tickCount > 0) {
        NSBezierPath *ticks = [NSBezierPath bezierPath];
        for (int i = 0; i < knob.tickCount; i++) {
            QLMKnobAppendRadial(ticks, center, knob.tickInner, knob.tickOuter, QLMKnobTickAngle(i, (int)knob.tickCount));
        }
        QLMKnobStroke(ticks, knob.tickWidth, QLMSkinNSColor(knob.tickColor));
    }
    if (knob.hasArc) {
        QLMKnobStroke(QLMKnobArc(center, knob.arcRadius, QLM_KNOB_START_DEGREES, QLM_KNOB_END_DEGREES), knob.arcWidth,
                      QLMSkinNSColor(knob.arcTrack));
    }
}

- (NSArray<QLMSkinMaterial *> *)skinMaterials:(QLMSkinLayers *)layers {
    NSMutableArray<QLMSkinMaterial *> *materials = [NSMutableArray array];
    __weak QLMKnobControl *weakSelf = self;
    QLMSkinMaterial *still = [QLMSkinMaterial materialPainting:^(NSRect rect) {
        [weakSelf drawStillIn:rect];
    }
                                                          frame:self.bounds
                                                         margin:0
                                                         family:@"knob-still"
                                                           skin:self.skin
                                                         layers:layers];
    if (still != nil) {
        [materials addObject:still];
    }
    QLMSkinKnob *knob = self.skin.knob;
    QLMSkinMaterial *body = [QLMSkinMaterial materialOfStyle:knob.body skin:self.skin
                                                       state:QLMSkinButtonState(NO, self.enabled, self.pressed, self.hovered)
                                                       frame:[self rectAround:knob.bodySize / 2] circle:YES
                                                     overlay:QLMSkinColorClear layers:layers];
    if (body != nil) {
        [materials addObject:body];
    }
    return materials;
}

// The arc rings the body, so drawn over the body's material it shows as it
// did beneath it.
- (void)drawSkinContent:(NSRect)dirtyRect {
    QLMSkinKnob *knob = self.skin.knob;
    NSPoint center = [self center];
    NSRect body = [self rectAround:knob.bodySize / 2];
    double angle = QLMKnobAngleForDecibels(_value, self.minValue, self.maxValue);

    if (knob.hasArc && angle > QLM_KNOB_START_DEGREES) {
        NSColor *fill = QLMSkinNSColor(knob.arcFill);
        QLMKnobStroke(QLMKnobArc(center, knob.arcRadius, QLM_KNOB_START_DEGREES, angle), knob.arcWidth,
                      self.enabled ? fill : VibeColorWithScaledAlpha(fill, QLMSkinDisabledAlpha));
    }

    NSBezierPath *pointer = [NSBezierPath bezierPath];
    QLMKnobAppendRadial(pointer, center, knob.pointerInner, knob.pointerOuter, angle);
    QLMKnobStroke(pointer, knob.pointerWidth, QLMSkinNSColor(self.enabled ? knob.pointerColor : knob.pointerDisabledColor));

    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(knob.focus, body, YES);
    }
}

@end
