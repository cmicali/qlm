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
static NSString *const QLMKnobTurnKey = @"transform.rotation.z";

@implementation QLMKnobControl {
    double _value;
    CGFloat _scrolled;
    BOOL _dragging;
    CAShapeLayer *_arc;  // nil for a skin with no arc
    CAShapeLayer *_pointer;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super initWithSkin:skin];
    if (self) {
        _minValue = -80;
        _maxValue = 0;
        _value = -80;
        self.accessibilityRole = NSAccessibilitySliderRole;
        _pointer = [self.layers makeLayerOfClass:[CAShapeLayer class]];
        if (skin.knob.hasArc) {
            _arc = [self.layers makeLayerOfClass:[CAShapeLayer class]];
        }
        self.layers.movingLayers = _arc != nil ? @[_arc, _pointer] : @[_pointer];
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

- (double)clamped:(double)value {
    return isfinite(value) ? QLMKnobClamp(value, self.minValue, MAX(self.minValue, self.maxValue)) : self.minValue;
}

- (void)setDoubleValue:(double)value {
    value = [self clamped:value];
    if (value == _value) {
        return;
    }
    _value = value;
    [self showLevelEased:[self easesLevel]];
}

// A change of the range moves the pointer at once.
- (void)setMinValue:(double)minValue {
    _minValue = minValue;
    _value = [self clamped:_value];
    [self showLevelEased:NO];
}

- (void)setMaxValue:(double)maxValue {
    _maxValue = maxValue;
    _value = [self clamped:_value];
    [self showLevelEased:NO];
}

// A drag tracks the pointer exactly.
- (BOOL)easesLevel {
    return !_dragging && QLMSkinEases(self);
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
    [self showLevelEased:[self easesLevel]];
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
    _dragging = YES;
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (next.type == NSEventTypeLeftMouseUp) {
            _dragging = NO;
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

static double QLMKnobRadians(double degrees) {
    return degrees * M_PI / 180.0;
}

// The arc's whole sweep, around `center`, in a space whose y grows down,
// mapped by `transform`. Its angles run from +x toward +y, so up is -90.
// TRAP: one arc of a few curves puts strokeEnd up to half a degree off its
// share of the sweep. A curve per degree puts it on.
static CGPathRef QLMKnobArcPath(NSPoint center, CGFloat radius, CGAffineTransform transform) {
    CGMutablePathRef path = CGPathCreateMutable();
    int count = (int)ceil(QLM_KNOB_SWEEP_DEGREES);
    for (int i = 0; i < count; i++) {
        double from = QLM_KNOB_START_DEGREES + i * QLM_KNOB_SWEEP_DEGREES / count;
        double to = QLM_KNOB_START_DEGREES + (i + 1) * QLM_KNOB_SWEEP_DEGREES / count;
        CGPathAddArc(path, &transform, center.x, center.y, radius, QLMKnobRadians(from - 90), QLMKnobRadians(to - 90), false);
    }
    return path;
}

// The pointer pointing up, from `center`, in a space whose y grows down,
// mapped by `transform`.
static CGPathRef QLMKnobPointerPath(NSPoint center, CGFloat inner, CGFloat outer, CGAffineTransform transform) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, &transform, center.x, center.y - inner);
    CGPathAddLineToPoint(path, &transform, center.x, center.y - outer);
    return path;
}

// From `from` to `to`, in the knob's degrees, in the flipped view.
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

- (NSColor *)arcFillColor {
    NSColor *fill = QLMSkinNSColor(self.skin.knob.arcFill);
    return self.enabled ? fill : VibeColorWithScaledAlpha(fill, QLMSkinDisabledAlpha);
}

- (NSColor *)pointerColor {
    QLMSkinKnob *knob = self.skin.knob;
    return QLMSkinNSColor(self.enabled ? knob.pointerColor : knob.pointerDisabledColor);
}

// Each moving layer spans the view, so its path is in the view's points.
// TRAP: a layer's y grows up unless contentsAreFlipped, and its rotation
// turns from +x toward +y, so both flip with it.
- (void)layoutSkinMovingLayers:(QLMSkinLayers *)layers {
    QLMSkinKnob *knob = self.skin.knob;
    NSRect bounds = self.bounds;
    NSRect frame = [self convertRectToLayer:bounds];
    NSPoint center = [self center];
    for (CAShapeLayer *layer in layers.movingLayers) {
        layer.bounds = (CGRect){CGPointZero, frame.size};
        layer.position = CGPointMake(NSMidX(frame), NSMidY(frame));
        layer.contentsScale = layers.scale;
        layer.fillColor = nil;
        layer.lineCap = kCALineCapRound;
    }
    CGAffineTransform toLayer = _pointer.contentsAreFlipped ? CGAffineTransformIdentity
                                                            : CGAffineTransformMake(1, 0, 0, -1, 0, bounds.size.height);
    CGPathRef pointer = QLMKnobPointerPath(center, knob.pointerInner, knob.pointerOuter, toLayer);
    _pointer.path = pointer;
    CGPathRelease(pointer);
    _pointer.lineWidth = knob.pointerWidth;
    _pointer.strokeColor = [self pointerColor].CGColor;
    if (_arc != nil) {
        CGPathRef arc = QLMKnobArcPath(center, knob.arcRadius, toLayer);
        _arc.path = arc;
        CGPathRelease(arc);
        _arc.lineWidth = knob.arcWidth;
        _arc.strokeColor = [self arcFillColor].CGColor;
        _arc.strokeEnd = [self arcEnd];
    }
    // An ease under way goes on.
    [_pointer setValue:@([self pointerTurn]) forKeyPath:QLMKnobTurnKey];
}

- (double)pointerTurn {
    double angle = QLMKnobRadians(QLMKnobAngleForDecibels(_value, self.minValue, self.maxValue));
    return _pointer.contentsAreFlipped ? angle : -angle;
}

- (double)arcEnd {
    return QLMKnobFraction(_value, self.minValue, self.maxValue);
}

// The pointer turns, and the arc's fill runs to it.
- (void)showLevelEased:(BOOL)eases {
    QLMSkinSetLayerValue(_pointer, QLMKnobTurnKey, @([self pointerTurn]), eases);
    if (_arc != nil) {
        QLMSkinSetLayerValue(_arc, @"strokeEnd", @([self arcEnd]), eases);
    }
}

// As the layers show it at rest. The arc rings the body, so drawn over the
// body's material it shows as it did beneath it.
- (void)drawSkinMovingReference {
    QLMSkinKnob *knob = self.skin.knob;
    NSPoint center = [self center];
    double angle = QLMKnobAngleForDecibels(_value, self.minValue, self.maxValue);
    if (knob.hasArc && angle > QLM_KNOB_START_DEGREES) {
        QLMKnobStroke(QLMKnobArc(center, knob.arcRadius, QLM_KNOB_START_DEGREES, angle), knob.arcWidth, [self arcFillColor]);
    }
    NSBezierPath *pointer = [NSBezierPath bezierPath];
    QLMKnobAppendRadial(pointer, center, knob.pointerInner, knob.pointerOuter, angle);
    QLMKnobStroke(pointer, knob.pointerWidth, [self pointerColor]);
}

- (void)drawSkinContent:(NSRect)dirtyRect {
    if (self.focused && self.enabled) {
        QLMSkinDrawFocus(self.skin.knob.focus, [self rectAround:self.skin.knob.bodySize / 2], YES);
    }
}

@end
