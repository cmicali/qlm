#import "QLMBannerView.h"

#import "QLMFormat.h"
#import "QLMViews.h"

@implementation QLMBannerView {
    NSTextField *_title;
    NSTextField *_detail;
}

- (instancetype)initWithTextWidth:(CGFloat)textWidth {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        self.hidden = YES;

        NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill"
                                                                      accessibilityDescription:@"Error"]];
        icon.contentTintColor = NSColor.systemOrangeColor;
        [icon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        _title = [NSTextField wrappingLabelWithString:@""];
        _title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];
        _title.preferredMaxLayoutWidth = textWidth;
        _detail = QLMNoteLabel(@"", textWidth);
        _detail.selectable = YES;

        NSStackView *text = [NSStackView stackViewWithViews:@[_title, _detail]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 2;
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
    self.layer.backgroundColor = [NSColor.systemOrangeColor colorWithAlphaComponent:0.12].CGColor;
    self.layer.borderColor = [NSColor.systemOrangeColor colorWithAlphaComponent:0.45].CGColor;
}

- (void)showError:(NSError *)error {
    self.hidden = error == nil;
    if (error != nil) {
        _title.stringValue = QLMAdapterErrorTitle(error);
        _detail.stringValue = QLMAdapterErrorDetail(error);
    }
}

@end
