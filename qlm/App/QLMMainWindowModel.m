#import "QLMMainWindowModel.h"

#include <math.h>

#include "QLMCommands.h"
#import "QLMFormat.h"
#import "QLMSkinLayout.h"
#import "QLMSystem.h"

const NSTimeInterval QLMKnobHoldInterval = 0.5;

BOOL QLMKnobHolds(NSTimeInterval turnedAt, NSTimeInterval now) {
    return turnedAt > 0 && now - turnedAt < QLMKnobHoldInterval;
}

// A range's end, as the mockups draw it: whole when on a whole dB.
static NSString *QLMRangeEndText(double decibels) {
    return QLMDecibelsNumberText(decibels, decibels == floor(decibels) ? 0 : 1);
}

// System refused it and sent nothing. Any other error, as a failed send or
// a stop mid-apply, may come after frames went out.
static BOOL QLMApplyRefused(NSError *error) {
    if (![error.domain isEqualToString:QLMSystemErrorDomain]) {
        return NO;
    }
    switch ((QLMSystemError)error.code) {
    case QLMSystemErrorUnverifiedRate:
    case QLMSystemErrorUnknownMonitor:
    case QLMSystemErrorBlocksFailed:
    case QLMSystemErrorAlreadyApplying:
    case QLMSystemErrorNoVolume:
    case QLMSystemErrorKnobUnread:
        return YES;
    case QLMSystemErrorNotRunning:
    case QLMSystemErrorSendFailed:
        return NO;
    }
    return NO;
}

@implementation QLMMainWindowModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = @[];
        _groupCapacity = QLMSkinMaxGroups;
    }
    return self;
}

#pragma mark - The status

- (NSString *)busProblem {
    return QLMBusProblemTitle(self.snapshot);
}

- (NSUInteger)onlineCount {
    NSUInteger online = 0;
    for (QLMMonitorEntry *entry in self.entries) {
        online += entry.presence == QLMMonitorPresenceOnline ? 1 : 0;
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

- (NSArray<NSString *> *)shownGroupNames {
    NSArray<NSString *> *names = self.groupNames ?: @[];
    NSUInteger shown = MIN(MIN(self.groupCapacity, QLMSkinMaxGroups), names.count);
    return [names subarrayWithRange:NSMakeRange(0, shown)];
}

- (NSArray<NSString *> *)groupTitles {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *name in self.shownGroupNames) {
        [titles addObject:name.localizedUppercaseString];
    }
    return titles;
}

- (NSArray<NSString *> *)groupPrefixes {
    NSMutableArray<NSString *> *prefixes = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.shownGroupNames.count; i++) {
        [prefixes addObject:[NSString stringWithFormat:@"%c", (char)('A' + i)]];
    }
    return prefixes;
}

- (BOOL)applying {
    return self.applyingGroupName != nil || self.snapshot.applying;
}

- (BOOL)groupSelectedAtIndex:(NSUInteger)index {
    NSArray<NSString *> *names = self.shownGroupNames;
    if (index >= names.count) {
        return NO;
    }
    if (self.applyingGroupName != nil) {
        return self.blinkOn && [names[index] isEqualToString:self.applyingGroupName];
    }
    return [names[index] isEqualToString:self.snapshot.activeGroupName];
}

- (BOOL)groupChosenAtIndex:(NSUInteger)index {
    NSArray<NSString *> *names = self.shownGroupNames;
    NSString *chosen = self.applyingGroupName ?: self.snapshot.activeGroupName;
    return index < names.count && [names[index] isEqualToString:chosen];
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

- (NSString *)unitText {
    return @"dB";
}

- (nullable NSNumber *)outputDecibels {
    return [self shownLevel] == nil ? nil : self.snapshot.handBack.volumeDecibels;
}

- (NSString *)outputText {
    if (self.applyError != nil) {
        return [NSString stringWithFormat:@"%@ %@", self.refusedGroupName.localizedUppercaseString ?: @"GROUP",
                                          QLMApplyRefused(self.applyError) ? @"REFUSED" : @"FAILED"];
    }
    if (self.snapshot.allMuted) {
        return @"MUTED";
    }
    NSNumber *output = [self outputDecibels];
    return [@"OUTPUT " stringByAppendingString:output == nil ? QLMEmDash : QLMDecibelsNumberText(output.doubleValue, 1)];
}

// With a volume set, the snapshot is a published one, so its ceiling is the
// one System caps at. Before that, the preferences say it.
- (double)shownCeiling {
    QLMSnapshot *snapshot = self.snapshot;
    return snapshot.volumeDecibels != nil ? snapshot.ceilingDecibels : self.ceilingDecibels;
}

- (NSString *)maxText {
    return [@"MAX " stringByAppendingString:QLMRangeEndText([self shownCeiling])];
}

- (BOOL)displayDisabled {
    return !self.snapshot.running;
}

- (NSString *)displaySummary {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *group = self.snapshot.activeGroupName;
    if (group != nil) {
        [parts addObject:group];
    }
    NSNumber *level = [self shownLevel];
    [parts addObject:[@"Level " stringByAppendingString:level == nil ? @"not set" : QLMDecibelsText(level.doubleValue)]];
    if (self.applyError != nil) {
        [parts addObject:self.applyError.localizedDescription];
    } else if (self.snapshot.allMuted) {
        [parts addObject:@"Muted"];
    } else if ([self outputDecibels] != nil) {
        [parts addObject:[@"Output " stringByAppendingString:QLMDecibelsText([self outputDecibels].doubleValue)]];
    }
    [parts addObject:[@"Ceiling " stringByAppendingString:QLMDecibelsText([self shownCeiling])]];
    return [parts componentsJoinedByString:@". "];
}

#pragma mark - Mute and dim

- (NSString *)muteTitle {
    return @"MUTE";
}

- (BOOL)muteOn {
    return self.snapshot.allMuted;
}

- (BOOL)muteEnabled {
    return QLMSnapshotTracksMonitors(self.snapshot);
}

- (NSString *)dimTitle {
    return [@"DIM " stringByAppendingString:QLMDecibelsNumberText(-QLMDimDecibels, 0)];
}

- (BOOL)dimOn {
    return self.snapshot.dimmed;
}

- (BOOL)dimEnabled {
    return self.snapshot.running;
}

#pragma mark - The knob

- (double)knobMinimum {
    return self.lowestDecibels;
}

- (double)knobMaximum {
    return self.ceilingDecibels;
}

- (NSString *)knobMinText {
    return QLMRangeEndText(self.knobMinimum);
}

- (NSString *)knobMaxText {
    return QLMRangeEndText(self.knobMaximum);
}

- (NSString *)knobCaption {
    return @"VOLUME";
}

- (NSNumber *)knobDecibels {
    return [self shownLevel];
}

- (BOOL)knobEnabled {
    return self.snapshot.running;
}

#pragma mark - The footer

- (NSString *)monitorsTitle {
    return @"Monitors";
}

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
