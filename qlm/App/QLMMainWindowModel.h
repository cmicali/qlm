#import <Foundation/Foundation.h>

#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The main window's changing texts and states, from the latest snapshot, the
// setup's groups, the volume range, and the window's own click. It mirrors
// the popover's rules for what is enabled when. Set the inputs, then read.
// Foundation only, so the hostless tests cover every rule. On the main
// queue.
@interface QLMMainWindowModel : NSObject

#pragma mark Inputs

@property (nonatomic, nullable) QLMSnapshot *snapshot;
// The loaded setup's groups, in the file's order. Nil with no setup.
@property (nonatomic, copy, nullable) NSArray<NSString *> *groupNames;
// The skin's group buttons. QLMSkinMaxGroups until set.
@property (nonatomic) NSUInteger groupCapacity;
// The setup file's name, or nil with none found.
@property (nonatomic, copy, nullable) NSString *setupFileName;
// Why the setup file did not read, or nil.
@property (nonatomic, copy, nullable) NSString *setupError;
// The group the window's last click chose.
@property (nonatomic, copy, nullable) NSString *clickedGroupName;
// From the click until its completion, before the snapshot may say so.
@property (nonatomic) BOOL applyPending;
// The last apply's error, from System, until the next click.
@property (nonatomic, nullable) NSError *applyError;
// The blink's phase while an apply runs.
@property (nonatomic) BOOL blinkOn;
// The preferences' range. Before a volume is set, the ceiling shown is
// this one, as the popover's is.
@property (nonatomic) double lowestDecibels;
@property (nonatomic) double ceilingDecibels;

#pragma mark Outputs

// "6 ONLINE", or the bus problem's title. The LED is lit while any monitor
// is online.
@property (nonatomic, readonly) NSString *statusText;
@property (nonatomic, readonly) BOOL statusLit;
// The bus problem's title as written, or nil.
@property (nonatomic, readonly, nullable) NSString *busProblem;

// As many as the skin has buttons for, in the file's order, and each one's
// title and letter.
@property (nonatomic, readonly) NSArray<NSString *> *shownGroupNames;
@property (nonatomic, readonly) NSArray<NSString *> *groupTitles;
@property (nonatomic, readonly) NSArray<NSString *> *groupPrefixes;
// The group an apply sends, by the snapshot or the window's pending click,
// else nil.
@property (nonatomic, readonly, nullable) NSString *applyingGroupName;
// The button that shows selected: while an apply runs, the applying group's
// in the blink's on phase only, else the active group's. NSNotFound for
// none.
@property (nonatomic, readonly) NSUInteger selectedGroupIndex;
// The applying group's, else the active group's, with no blink, for
// VoiceOver. NSNotFound for none.
@property (nonatomic, readonly) NSUInteger chosenGroupIndex;
// The popover picker's rule: a setup, System tracks a monitor, and no apply
// runs.
@property (nonatomic, readonly) BOOL groupsEnabled;
@property (nonatomic, readonly) BOOL applying;
// In the grid's place while no group shows: the file's name, its error, or
// that there is none. Nil while groups show.
@property (nonatomic, readonly, nullable) NSString *groupsMessage;

@property (nonatomic, readonly) NSString *caption;
// The undimmed level, or an em dash while none is set or it waits for the
// knob.
@property (nonatomic, readonly) NSString *levelText;
// What goes out now: the dimmed level, or MUTED under mute all. After an
// apply's error, that the clicked group was refused, which sent nothing, or
// failed, which may have sent some. The reason is longer than the line, so
// the display's tooltip gives it.
@property (nonatomic, readonly) NSString *outputText;
@property (nonatomic, readonly) NSString *maxText;
// The display dims while System is stopped.
@property (nonatomic, readonly) BOOL displayDisabled;

@property (nonatomic, readonly) BOOL muteOn;
@property (nonatomic, readonly) BOOL muteEnabled;
@property (nonatomic, readonly) BOOL dimOn;
@property (nonatomic, readonly) BOOL dimEnabled;

// The range's ends, whole when they are.
@property (nonatomic, readonly) NSString *knobMinText;
@property (nonatomic, readonly) NSString *knobMaxText;
// The level the knob points at, or nil with none set, or while it waits for
// the knob's reading.
@property (nonatomic, readonly, nullable) NSNumber *knobDecibels;
@property (nonatomic, readonly) BOOL knobEnabled;

// Standby while a monitor is on, Wake while none is.
@property (nonatomic, readonly) NSString *powerTitle;
@property (nonatomic, readonly) BOOL powerWakes;
@property (nonatomic, readonly) BOOL powerEnabled;

@end

NS_ASSUME_NONNULL_END
