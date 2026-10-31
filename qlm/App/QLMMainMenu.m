#import "QLMMainMenu.h"

// The window's undo actions, which AppKit's headers do not declare.
@protocol QLMUndoActions
- (void)undo:(nullable id)sender;
- (void)redo:(nullable id)sender;
@end

NSMenu *QLMMainMenu(void) {
    NSMenu *app = [[NSMenu alloc] initWithTitle:@"qlm"];
    [app addItemWithTitle:@"Quit qlm" action:@selector(terminate:) keyEquivalent:@"q"];

    NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
    [file addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];

    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    NSMenu *bar = [[NSMenu alloc] init];
    for (NSMenu *menu in @[app, file, edit]) {
        [bar addItemWithTitle:menu.title action:NULL keyEquivalent:@""].submenu = menu;
    }
    return bar;
}
