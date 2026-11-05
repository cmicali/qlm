#import "QLMMainMenu.h"

// The window's undo actions, which AppKit's headers do not declare.
@protocol QLMUndoActions
- (void)undo:(nullable id)sender;
- (void)redo:(nullable id)sender;
@end

static const NSInteger QLMGroupItemTag = 1000;

static NSMenuItem *QLMItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSEventModifierFlags modifiers,
                           id _Nullable target) {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = modifiers;
    item.target = target;
    return item;
}

static NSString *QLMArrowKey(unichar arrow) {
    return [NSString stringWithCharacters:&arrow length:1];
}

NSMenu *QLMMainMenu(id<QLMMainMenuActions> app, id<QLMMainMenuControls> controls) {
    NSEventModifierFlags command = NSEventModifierFlagCommand;
    NSEventModifierFlags shift = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSMenu *qlm = [[NSMenu alloc] initWithTitle:@"qlm"];
    QLMItem(qlm, @"About qlm", @selector(orderFrontStandardAboutPanel:), @"", 0, nil);
    [qlm addItem:NSMenuItem.separatorItem];
    QLMItem(qlm, @"Settings…", @selector(showSettings:), @",", command, app);
    [qlm addItem:NSMenuItem.separatorItem];
    QLMItem(qlm, @"Hide qlm", @selector(hide:), @"h", command, nil);
    QLMItem(qlm, @"Hide Others", @selector(hideOtherApplications:), @"h", command | NSEventModifierFlagOption, nil);
    QLMItem(qlm, @"Show All", @selector(unhideAllApplications:), @"", 0, nil);
    [qlm addItem:NSMenuItem.separatorItem];
    // Through applicationShouldTerminate:, so the louder hand-back still asks.
    QLMItem(qlm, @"Quit qlm", @selector(terminate:), @"q", command, nil);

    NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
    QLMItem(file, @"Close", @selector(performClose:), @"w", command, nil);

    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    QLMItem(edit, @"Undo", @selector(undo:), @"z", command, nil);
    QLMItem(edit, @"Redo", @selector(redo:), @"z", shift, nil);
    [edit addItem:NSMenuItem.separatorItem];
    QLMItem(edit, @"Cut", @selector(cut:), @"x", command, nil);
    QLMItem(edit, @"Copy", @selector(copy:), @"c", command, nil);
    QLMItem(edit, @"Paste", @selector(paste:), @"v", command, nil);
    QLMItem(edit, @"Delete", @selector(delete:), @"", 0, nil);
    QLMItem(edit, @"Select All", @selector(selectAll:), @"a", command, nil);

    // Cmd-M is Minimize's, so Mute and Dim take Shift too.
    NSMenu *controlsMenu = [[NSMenu alloc] initWithTitle:@"Controls"];
    QLMItem(controlsMenu, @"Mute", @selector(toggleMute:), @"m", shift, controls);
    QLMItem(controlsMenu, @"Dim", @selector(toggleDim:), @"d", shift, controls);
    QLMItem(controlsMenu, @"Standby", @selector(togglePower:), @"", 0, controls);
    [controlsMenu addItem:NSMenuItem.separatorItem];
    QLMItem(controlsMenu, @"Volume Up", @selector(volumeUp:), QLMArrowKey(NSUpArrowFunctionKey), command, controls);
    QLMItem(controlsMenu, @"Volume Down", @selector(volumeDown:), QLMArrowKey(NSDownArrowFunctionKey), command, controls);

    NSMenu *window = [[NSMenu alloc] initWithTitle:@"Window"];
    QLMItem(window, @"Minimize", @selector(performMiniaturize:), @"m", command, nil);
    QLMItem(window, @"Zoom", @selector(performZoom:), @"", 0, nil);
    [window addItem:NSMenuItem.separatorItem];
    QLMItem(window, @"qlm", @selector(showMainWindow:), @"0", command, app);
    QLMItem(window, @"Monitors", @selector(showMonitors:), @"", 0, app);
    [window addItem:NSMenuItem.separatorItem];
    QLMItem(window, @"Bring All to Front", @selector(arrangeInFront:), @"", 0, nil);

    // AppKit puts its search field in the Help menu.
    NSMenu *help = [[NSMenu alloc] initWithTitle:@"Help"];

    NSMenu *bar = [[NSMenu alloc] init];
    for (NSMenu *menu in @[qlm, file, edit, controlsMenu, window, help]) {
        [bar addItemWithTitle:menu.title action:NULL keyEquivalent:@""].submenu = menu;
    }
    controls.controlsMenu = controlsMenu;
    return bar;
}

void QLMMainMenuSetGroups(NSMenu *controls, NSArray<NSString *> *names, id<QLMMainMenuControls> target) {
    for (NSMenuItem *item in [controls.itemArray copy]) {
        if (item.tag >= QLMGroupItemTag || (item.isSeparatorItem && item.tag == QLMGroupItemTag - 1)) {
            [controls removeItem:item];
        }
    }
    if (names.count == 0) {
        return;
    }
    NSMenuItem *separator = NSMenuItem.separatorItem;
    separator.tag = QLMGroupItemTag - 1;
    [controls addItem:separator];
    for (NSUInteger i = 0; i < names.count; i++) {
        NSString *key = i < 9 ? [NSString stringWithFormat:@"%lu", (unsigned long)i + 1] : @"";
        NSMenuItem *item = QLMItem(controls, names[i], @selector(chooseGroup:), key, NSEventModifierFlagCommand, target);
        item.tag = QLMGroupItemTag + (NSInteger)i;
        item.representedObject = @(i);
    }
}
