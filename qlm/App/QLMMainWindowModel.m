#import "QLMMainWindowModel.h"

#include <math.h>

#import "QLMFormat.h"
#import "QLMSystem.h"

NSString *const QLMWindowClosedRefusal = @"the window is closed";

// A range's end, as the mockups draw it: whole when on a whole dB.
static NSString *QLMRangeEndText(double decibels) {
    return QLMDecibelsNumberText(decibels, decibels == floor(decibels) ? 0 : 1);
}

static NSArray<NSString *> *QLMGroupLetters(void) {
    return @[@"A", @"B", @"C", @"D", @"E", @"F"];
}

NSUInteger QLMShownGroupButtons(NSUInteger cells) {
    return MIN(cells, QLMGroupLetters().count);
}

@implementation QLMMainWindowModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _groupCapacity = NSUIntegerMax;
        _shownGroupNames = @[];
        _groupTitles = @[];
        _groupPrefixes = @[];
        self.lowestDecibels = 0;
        self.ceilingDecibels = 0;
    }
    return self;
}

#pragma mark - The status

- (NSString *)busProblem {
    return QLMBusProblemTitle(self.snapshot);
}

- (NSUInteger)onlineCount {
    NSUInteger online = 0;
    for (QLMMonitorState *monitor in self.snapshot.monitors) {
        online += QLMMonitorIsOnline(monitor) ? 1 : 0;
    }
    return online;
}

- (NSString *)statusText {
    NSString *problem = self.busProblem;
    if (problem != nil) {
        return problem.localizedUppercaseString;
    }
    return [NSString stringWithFormat:@"%lu ONLINE", (unsigned long)[self onlineCount]];
}

- (BOOL)statusLit {
    return [self onlineCount] > 0;
}

- (BOOL)statusEnabled {
    return self.snapshot.running;
}

#pragma mark - The groups

- (void)setGroupNames:(NSArray<NSString *> *)groupNames {
    _groupNames = [groupNames copy];
    [self showGroups];
}

- (void)setGroupCapacity:(NSUInteger)groupCapacity {
    _groupCapacity = groupCapacity;
    [self showGroups];
}

- (void)showGroups {
    NSArray<NSString *> *names = self.groupNames ?: @[];
    NSUInteger shown = MIN(QLMShownGroupButtons(self.groupCapacity), names.count);
    _shownGroupNames = [names subarrayWithRange:NSMakeRange(0, shown)];
    _groupPrefixes = [QLMGroupLetters() subarrayWithRange:NSMakeRange(0, shown)];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:shown];
    for (NSString *name in _shownGroupNames) {
        [titles addObject:name.localizedUppercaseString];
    }
    _groupTitles = titles;
}

- (BOOL)applying {
    return self.applyPending || self.snapshot.applying;
}

- (NSString *)applyingGroupName {
    return self.snapshot.applyingGroupName ?: (self.applyPending ? self.clickedGroupName : nil);
}

- (NSUInteger)chosenGroupIndex {
    NSString *chosen = self.applyingGroupName ?: self.snapshot.activeGroupName;
    return chosen != nil ? [self.shownGroupNames indexOfObject:chosen] : NSNotFound;
}

- (NSUInteger)selectedGroupIndex {
    if (self.applying && !self.blinkOn) {
        return NSNotFound;
    }
    return self.chosenGroupIndex;
}

- (BOOL)groupsEnabled {
    return self.hasSystem && self.groupNames != nil && QLMSnapshotTracksMonitors(self.snapshot) && !self.applying;
}

- (NSString *)groupsMessage {
    if (self.shownGroupNames.count > 0) {
        return nil;
    }
    if (self.setupError != nil) {
        return self.setupError;
    }
    if (self.setupFileName == nil) {
        return @"No setup file in GLM's folder";
    }
    if (self.groupNames == nil) {
        return [NSString stringWithFormat:@"Reading %@…", self.setupFileName];
    }
    return [NSString stringWithFormat:@"%@ has no groups", self.setupFileName];
}

- (NSString *)refusalToClickGroupNamed:(NSString *)name {
    NSArray<NSString *> *names = self.shownGroupNames;
    if (names.count == 0) {
        return [NSString stringWithFormat:@"no group buttons show: %@", self.groupsMessage];
    }
    if (![names containsObject:name]) {
        return [NSString stringWithFormat:@"no group button reads %@. They read: %@", name, [names componentsJoinedByString:@", "]];
    }
    if (!self.groupsEnabled) {
        return self.applying     ? @"the group buttons are disabled while an apply runs"
               : !self.hasSystem ? @"System is not running"
                                 : @"the group buttons are disabled until System tracks a monitor";
    }
    return nil;
}

#pragma mark - The display

- (NSString *)caption {
    return self.snapshot.activeGroupName.localizedUppercaseString ?: @"";
}

- (nullable NSNumber *)shownLevel {
    QLMSnapshot *snapshot = self.snapshot;
    return snapshot.levelAwaitsKnob ? nil : snapshot.volumeDecibels;
}

- (NSString *)levelText {
    NSNumber *level = [self shownLevel];
    return level == nil ? QLMEmDash : QLMDecibelsNumberText(level.doubleValue, 1);
}

- (NSString *)outputText {
    if (self.applyError != nil) {
        return [NSString stringWithFormat:@"%@ %@", self.clickedGroupName.localizedUppercaseString ?: @"",
                                          QLMSystemErrorRefused(self.applyError) ? @"REFUSED" : @"FAILED"];
    }
    // Dimmed, it shows the dimmed level instead.
    NSString *state = QLMOutputStateText(self.snapshot);
    if (self.snapshot.allMuted && state != nil) {
        return state;
    }
    NSNumber *output = [self shownLevel] == nil ? nil : self.snapshot.handBack.volumeDecibels;
    return [@"OUTPUT " stringByAppendingString:output == nil ? QLMEmDash : QLMDecibelsNumberText(output.doubleValue, 1)];
}

- (NSString *)maxText {
    return [@"MAX " stringByAppendingString:QLMRangeEndText(QLMShownCeiling(self.snapshot, self.ceilingDecibels))];
}

- (BOOL)displayDisabled {
    return !self.snapshot.running;
}

#pragma mark - Mute and dim

- (BOOL)muteOn {
    return self.snapshot.allMuted;
}

- (BOOL)muteEnabled {
    return self.hasSystem && QLMSnapshotTracksMonitors(self.snapshot);
}

- (BOOL)dimOn {
    return self.snapshot.dimmed;
}

- (BOOL)dimEnabled {
    return self.hasSystem && self.snapshot.running;
}

#pragma mark - The knob

- (void)setLowestDecibels:(double)lowestDecibels {
    _lowestDecibels = lowestDecibels;
    _knobMinText = QLMRangeEndText(lowestDecibels);
}

- (void)setCeilingDecibels:(double)ceilingDecibels {
    _ceilingDecibels = ceilingDecibels;
    _knobMaxText = QLMRangeEndText(ceilingDecibels);
}

- (NSNumber *)knobDecibels {
    return [self shownLevel];
}

- (BOOL)knobEnabled {
    return self.hasSystem && self.snapshot.running;
}

#pragma mark - The footer

- (BOOL)powerWakes {
    return !self.snapshot.anyOn;
}

- (NSString *)powerTitle {
    return self.powerWakes ? @"Wake" : @"Standby";
}

- (BOOL)powerEnabled {
    return self.hasSystem && QLMSnapshotTracksMonitors(self.snapshot);
}

@end
