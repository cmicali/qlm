#import "QLMSkinLayout.h"

static void QLMSkinSpringAxis(CGFloat *origin, CGFloat *length, BOOL low, BOOL high, CGFloat extra) {
    if (low && high) {
        *length += extra;
    }
    else if (high) {
        *origin += extra;
    }
    else if (!low) {
        *origin += extra / 2;
    }
}

CGRect QLMSkinSpring(CGRect frame, QLMSkinAnchors anchors, CGSize extra) {
    QLMSkinSpringAxis(&frame.origin.x, &frame.size.width, (anchors & QLMSkinAnchorLeft) != 0,
                      (anchors & QLMSkinAnchorRight) != 0, extra.width);
    QLMSkinSpringAxis(&frame.origin.y, &frame.size.height, (anchors & QLMSkinAnchorTop) != 0,
                      (anchors & QLMSkinAnchorBottom) != 0, extra.height);
    return frame;
}

NSArray<NSValue *> *QLMSkinGridCells(CGRect frame, NSInteger columns, NSInteger rows, CGSize gap) {
    NSMutableArray<NSValue *> *cells = [NSMutableArray array];
    if (columns < 1 || rows < 1) {
        return cells;
    }
    CGFloat width = (frame.size.width - gap.width * (columns - 1)) / columns;
    CGFloat height = (frame.size.height - gap.height * (rows - 1)) / rows;
    for (NSInteger row = 0; row < rows; row++) {
        for (NSInteger column = 0; column < columns; column++) {
            [cells addObject:[NSValue valueWithRect:CGRectMake(frame.origin.x + column * (width + gap.width),
                                                               frame.origin.y + row * (height + gap.height), width, height)]];
        }
    }
    return cells;
}

CGFloat QLMSkinSlotScale(QLMSkinElement *element, QLMSkinTextSlot *slot, CGSize size) {
    if (!slot.scales) {
        return 1;
    }
    // The smaller ratio, so a scaled slot never outgrows its element.
    return MIN(size.height / element.frame.size.height, size.width / element.frame.size.width);
}

CGRect QLMSkinSlotFrame(QLMSkinElement *element, QLMSkinTextSlot *slot, CGSize size) {
    CGRect frame = slot.frame;
    if (slot.scales) {
        CGFloat scale = QLMSkinSlotScale(element, slot, size);
        return CGRectMake(frame.origin.x * scale, frame.origin.y * scale, frame.size.width * scale, frame.size.height * scale);
    }
    CGSize extra = CGSizeMake(size.width - element.frame.size.width, size.height - element.frame.size.height);
    return QLMSkinSpring(frame, slot.anchors, extra);
}

@implementation QLMSkinLayout

- (instancetype)initWithSkin:(QLMSkin *)skin size:(CGSize)size {
    self = [super init];
    if (self) {
        _skin = skin;
        _size = CGSizeMake(MAX(size.width, skin.windowSize.width), MAX(size.height, skin.windowSize.height));
    }
    return self;
}

- (CGRect)frameOfElement:(NSString *)name {
    QLMSkinElement *element = [self.skin element:name];
    CGSize extra = CGSizeMake(self.size.width - self.skin.windowSize.width, self.size.height - self.skin.windowSize.height);
    return QLMSkinSpring(element.frame, element.anchors, extra);
}

- (CGFloat)scaleOfSlot:(NSString *)slot inElement:(NSString *)name {
    QLMSkinElement *element = [self.skin element:name];
    return QLMSkinSlotScale(element, element.text[slot], [self frameOfElement:name].size);
}

- (CGRect)frameOfSlot:(NSString *)slot inElement:(NSString *)name {
    QLMSkinElement *element = [self.skin element:name];
    NSAssert(element.text[slot] != nil, @"no slot %@ in %@", slot, name);
    return QLMSkinSlotFrame(element, element.text[slot], [self frameOfElement:name].size);
}

- (NSArray<NSValue *> *)cellsOfElement:(NSString *)name {
    QLMSkinElement *element = [self.skin element:name];
    return QLMSkinGridCells([self frameOfElement:name], element.columns, element.rows, element.gap);
}

@end
