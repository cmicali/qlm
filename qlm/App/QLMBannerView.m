#import "QLMBannerView.h"

#import "QLMFormat.h"
#import "QLMViews.h"

@implementation QLMBannerView {
    NSColor *_tint;
    NSTextField *_title;
    NSTextField *_detail;
}

- (instancetype)initWithTextWidth:(CGFloat)textWidth style:(QLMBannerStyle)style {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        BOOL warning = style == QLMBannerStyleWarning;
        _tint = warning ? NSColor.systemOrangeColor : NSColor.controlAccentColor;
        self.wantsLayer = YES;
        self.hidden = YES;

        NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:warning ? @"exclamationmark.triangle.fill" : @"info.circle.fill"
                                                                      accessibilityDescription:warning ? @"Error" : @"Notice"]];
        icon.contentTintColor = _tint;
        [icon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        _title = [NSTextField wrappingLabelWithString:@""];
        _title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
        _title.preferredMaxLayoutWidth = textWidth;
        _detail = QLMNoteLabel(@"", textWidth);
        _detail.selectable = YES;
        _actionButton = QLMSmallButton(@"", nil, nil);
        _actionButton.hidden = YES;

        NSStackView *text = [NSStackView stackViewWithViews:@[_title, _detail, _actionButton]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 2;
        [text setCustomSpacing:6 afterView:_detail];
        NSStackView *row = [NSStackView stackViewWithViews:@[icon, text]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeTop;
        row.edgeInsets = NSEdgeInsetsMake(8, 10, 8, 10);
        [self addSubview:row];
        QLMPinToEdges(row, self);
    }
    return self;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    self.layer.cornerRadius = 6;
    self.layer.borderWidth = 1;
    self.layer.backgroundColor = [_tint colorWithAlphaComponent:0.12].CGColor;
    self.layer.borderColor = [_tint colorWithAlphaComponent:0.45].CGColor;
}

// Sets only what changed: a popover redraws often while the adapter is
// refused.
- (void)showTitle:(NSString *)title detail:(NSString *)detail {
    self.hidden = title == nil;
    if (![_title.stringValue isEqualToString:title ?: @""]) {
        _title.stringValue = title ?: @"";
    }
    if (![_detail.stringValue isEqualToString:detail ?: @""]) {
        _detail.stringValue = detail ?: @"";
    }
}

- (void)showBusProblemOf:(QLMSnapshot *)snapshot {
    NSString *title = QLMBusProblemTitle(snapshot);
    [self showTitle:title detail:title == nil ? nil : QLMBusProblemDetail(snapshot)];
}

@end
