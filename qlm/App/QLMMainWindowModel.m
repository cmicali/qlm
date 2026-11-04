#import "QLMMainWindowModel.h"

#include <math.h>

#import "QLMFormat.h"
#import "QLMSkinLayout.h"
#import "QLMSystem.h"

// A range's end, as the mockups draw it: whole when on a whole dB.
static NSString *QLMRangeEndText(double decibels) {
    return QLMDecibelsNumberText(decibels, decibels == floor(decibels) ? 0 : 1);
}

@implementation QLMMainWindowModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _groupCapacity = QLMSkinMaxGroups;
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
        online += !monitor.offline && monitor.status == QLMMonitorStatusOn ? 1 : 0;
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
    static NSArray<NSString *> *letters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        letters = @[@"A", @"B", @"C", @"D", @"E", @"F"];
    });
    NSArray<NSString *> *names = self.groupNames ?: @[];
    NSUInteger shown = MIN(MIN(self.groupCapacity, letters.count), names.count);
    _shownGroupNames = [names subarrayWithRange:NSMakeRange(0, shown)];
    _groupPrefixes = [letters subarrayWithRange:NSMakeRange(0, shown)];
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
    if (self.applyingGroupName != nil && !self.blinkOn) {
        return NSNotFound;
    }
    return self.chosenGroupIndex;
}

- (BOOL)groupsEnabled {
    return self.groupNames != nil && QLMSnapshotTracksMonitors(self.snapshot) && !self.applying;
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
    if (self.snapshot.allMuted) {
        return @"MUTED";
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
    return QLMSnapshotTracksMonitors(self.snapshot);
}

- (BOOL)dimOn {
    return self.snapshot.dimmed;
}

- (BOOL)dimEnabled {
    return self.snapshot.running;
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
    return self.snapshot.running;
}

#pragma mark - The footer

- (BOOL)powerWakes {
    return !self.snapshot.anyOn;
}

- (NSString *)powerTitle {
    return self.powerWakes ? @"Wake" : @"Standby";
}

- (BOOL)powerEnabled {
    return QLMSnapshotTracksMonitors(self.snapshot);
}

@end
