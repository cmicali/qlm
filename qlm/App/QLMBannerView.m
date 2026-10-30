#import "QLMBannerView.h"

#import "QLMFormat.h"
#import "QLMViews.h"

@implementation QLMBannerView {
    QLMBannerStyle _style;
    NSTextField *_title;
    NSTextField *_detail;
}

- (instancetype)initWithTextWidth:(CGFloat)textWidth style:(QLMBannerStyle)style {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _style = style;
        self.wantsLayer = YES;
        self.hidden = YES;

        BOOL warning = style == QLMBannerStyleWarning;
        NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:warning ? @"exclamationmark.triangle.fill" : @"info.circle.fill"
                                                                      accessibilityDescription:warning ? @"Error" : @"Notice"]];
        icon.contentTintColor = self.tint;
        [icon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        _title = [NSTextField wrappingLabelWithString:@""];
        _title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
        _title.preferredMaxLayoutWidth = textWidth;
        _detail = QLMNoteLabel(@"", textWidth);
        _detail.selectable = YES;
        _actionButton = [NSButton buttonWithTitle:@"" target:nil action:nil];
        _actionButton.controlSize = NSControlSizeSmall;
        _actionButton.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
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

- (NSColor *)tint {
    return _style == QLMBannerStyleWarning ? NSColor.systemOrangeColor : NSColor.controlAccentColor;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    self.layer.cornerRadius = 6;
    self.layer.borderWidth = 1;
    self.layer.backgroundColor = [self.tint colorWithAlphaComponent:0.12].CGColor;
    self.layer.borderColor = [self.tint colorWithAlphaComponent:0.45].CGColor;
}

- (void)showTitle:(NSString *)title detail:(NSString *)detail {
    self.hidden = title == nil;
    _title.stringValue = title ?: @"";
    _detail.stringValue = detail ?: @"";
    _detail.hidden = detail == nil;
}

- (void)showError:(NSError *)error {
    [self showTitle:error == nil ? nil : QLMAdapterErrorTitle(error) detail:error == nil ? nil : QLMAdapterErrorDetail(error)];
}

@end
