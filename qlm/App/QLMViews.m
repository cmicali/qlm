#import "QLMViews.h"

NSTextField *QLMNoteLabel(NSString *text, CGFloat width) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    label.preferredMaxLayoutWidth = width;
    return label;
}

NSButton *QLMSmallButton(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    return button;
}

NSImageView *QLMDotView(void) {
    NSImageView *dot = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"circle.fill" accessibilityDescription:nil]];
    dot.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:8 weight:NSFontWeightRegular];
    return dot;
}

void QLMPinToEdges(NSView *view, NSView *container) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
}
