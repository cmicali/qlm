#import <Foundation/Foundation.h>

#import "QLMMonitorList.h"
#import "QLMSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// The groups the main window shows at most, in the file's order.
extern const NSUInteger QLMMainWindowMaxGroups;

// After the user turns the knob, snapshots leave it alone this long, so a
// snapshot from before the turn cannot pull it back mid-drag. The popover's
// slider holds as long.
extern const NSTimeInterval QLMKnobHoldInterval;

// Whether the knob still holds at `now`, after a turn at `turnedAt`, both in
// seconds of system uptime. 0 is never turned.
BOOL QLMKnobHolds(NSTimeInterval turnedAt, NSTimeInterval now);

// What the main window shows: its texts and its controls' states, from the
// latest snapshot, the monitor list's entries, the setup's groups, the
// volume range, and the window's own apply. It mirrors the popover's rules
// for what is enabled when. Set the inputs, then read. Foundation only, so
// the hostless tests cover every rule. On the main queue.
@interface QLMMainWindowModel : NSObject

#pragma mark Inputs

@property (nonatomic, nullable) QLMSnapshot *snapshot;
@property (nonatomic, copy) NSArray<QLMMonitorEntry *> *entries;
// The loaded setup's groups, in the file's order. Nil with no setup.
@property (nonatomic, copy, nullable) NSArray<NSString *> *groupNames;
// The setup file's name, or nil with none found.
@property (nonatomic, copy, nullable) NSString *setupFileName;
// Why the setup file did not read, or nil.
@property (nonatomic, copy, nullable) NSString *setupError;
// The group the window's click is applying, until its completion.
@property (nonatomic, copy, nullable) NSString *applyingGroupName;
// The last apply's refusal, and its group, until the next click.
@property (nonatomic, copy, nullable) NSString *applyError;
@property (nonatomic, copy, nullable) NSString *refusedGroupName;
// The blink's phase while the window's apply runs.
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

// Up to QLMMainWindowMaxGroups, and each one's letter.
@property (nonatomic, readonly) NSArray<NSString *> *groupTitles;
@property (nonatomic, readonly) NSArray<NSString *> *groupPrefixes;
// The groups as the setup names them, as many as show.
@property (nonatomic, readonly) NSArray<NSString *> *shownGroupNames;
// Each shown group's button is selected, by index. While the window's apply
// runs, only the chosen one, and only in the blink's on phase.
- (BOOL)groupSelectedAtIndex:(NSUInteger)index;
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
@property (nonatomic, readonly) NSString *unitText;
// What goes out now: the dimmed level, or MUTED under mute all. After a
// refusal, that the group was refused: the reason is longer than the line,
// so it goes in the tooltip and displaySummary.
@property (nonatomic, readonly) NSString *outputText;
@property (nonatomic, readonly) NSString *maxText;
// The display dims while System is stopped.
@property (nonatomic, readonly) BOOL displayDisabled;
// The display's line for VoiceOver.
@property (nonatomic, readonly) NSString *displaySummary;

@property (nonatomic, readonly) NSString *muteTitle;
@property (nonatomic, readonly) BOOL muteOn;
@property (nonatomic, readonly) BOOL muteEnabled;
@property (nonatomic, readonly) NSString *dimTitle;
@property (nonatomic, readonly) BOOL dimOn;
@property (nonatomic, readonly) BOOL dimEnabled;

@property (nonatomic, readonly) double knobMinimum;
@property (nonatomic, readonly) double knobMaximum;
@property (nonatomic, readonly) NSString *knobMinText;
@property (nonatomic, readonly) NSString *knobMaxText;
@property (nonatomic, readonly) NSString *knobCaption;
// The level the knob points at, or nil with none set.
@property (nonatomic, readonly, nullable) NSNumber *knobDecibels;
@property (nonatomic, readonly) BOOL knobEnabled;

@property (nonatomic, readonly) NSString *monitorsTitle;
// Standby while a monitor is on, Wake while none is.
@property (nonatomic, readonly) NSString *powerTitle;
@property (nonatomic, readonly) BOOL powerWakes;
@property (nonatomic, readonly) BOOL powerEnabled;

@end

NS_ASSUME_NONNULL_END
