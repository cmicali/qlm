#import <Foundation/Foundation.h>

#import "QLMMonitorList.h"
#import "QLMSetup.h"
#import "QLMTraffic.h"

NS_ASSUME_NONNULL_BEGIN

// One frame of traffic as the traffic window shows it, with its words made
// once, as it arrives. Immutable.
@interface QLMTrafficRow : NSObject

@property (nonatomic, readonly) QLMTrafficEntry *entry;
@property (nonatomic, readonly) NSString *timeText;       // "14:06:11.123", the Mac's local time
@property (nonatomic, readonly) NSString *directionText;  // "→", "←", "→ sync", "← stray", "timeout"
// The address, and the monitor's name and serial where known. A reply
// shows its request's.
@property (nonatomic, readonly) NSString *targetText;
@property (nonatomic, readonly) NSString *bytesText;  // "FF 1F 0C CC CC"
@property (nonatomic, readonly) NSString *descriptionText;
// The frame's opcode, or its request's, or -1.
@property (nonatomic, readonly) NSInteger opcode;
// What the monitor filter matches: a hardware ID's hex, "FF", "01", or
// "session 0B". Empty for a stray.
@property (nonatomic, readonly) NSString *targetKey;
// One line for notes.md: the fields, two spaces apart.
@property (nonatomic, readonly) NSString *line;
// For the debug channel.
@property (nonatomic, readonly) NSDictionary<NSString *, id> *JSON;

@end

typedef NS_ENUM(NSInteger, QLMTrafficDirection) {
    QLMTrafficDirectionBoth = 0,
    QLMTrafficDirectionOut,  // requests and syncs
    QLMTrafficDirectionIn,   // replies, no-answers, strays, and timeouts
};

// "both", "sent", and "received", by QLMTrafficDirection.
NSArray<NSString *> *QLMTrafficDirectionNames(void);

// What an add did to the rows shown.
typedef NS_ENUM(NSInteger, QLMTrafficChange) {
    QLMTrafficChangeNone = 0,
    QLMTrafficChangeAppended,  // rows shown were added at the end
    QLMTrafficChangeReset,     // the oldest rows were dropped too
};

// The rows the traffic window shows, and its filters. It only reads: it
// never sends. On the main queue.
@interface QLMTrafficLog : NSObject

// Keeps at most `limit` rows, dropping the oldest.
- (instancetype)initWithLimit:(NSUInteger)limit NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

// Names the monitors, and gives each its PEQ design rate.
@property (nonatomic, nullable) QLMSetup *setup;
// Gives each monitor its serial.
@property (nonatomic, nullable) QLMMonitorList *monitorList;

// Appends the entries one System handed over. Entries it already holds
// from that System are skipped, so a new handler's backlog adds only what's
// new. A new System's entries number from 1 again.
- (QLMTrafficChange)addEntries:(NSArray<QLMTrafficEntry *> *)entries fromSystem:(id)system;
// Drops every row, and the opcode and target filters with them.
- (void)clear;

@property (nonatomic, readonly) NSArray<QLMTrafficRow *> *rows;
// The rows the filters pass, in order.
@property (nonatomic, readonly) NSArray<QLMTrafficRow *> *shownRows;
@property (nonatomic, readonly) NSUInteger rowCount;
@property (nonatomic, readonly) NSUInteger shownCount;

@property (nonatomic) QLMTrafficDirection direction;
@property (nonatomic, nullable) NSNumber *opcode;      // nil passes every one
@property (nonatomic, copy, nullable) NSString *targetKey;  // nil passes every one
// What each filter could pick, from the rows held: the opcodes, sorted, and
// each target's key and title, in the order first seen.
@property (nonatomic, readonly) NSArray<NSNumber *> *opcodes;
@property (nonatomic, readonly) NSArray<NSArray<NSString *> *> *targets;
// Counts each change to the opcodes or targets offered.
@property (nonatomic, readonly) NSUInteger choicesChanges;

// The rows' lines, one per line, with a header naming the columns.
+ (NSString *)textOfRows:(NSArray<QLMTrafficRow *> *)rows;

@end

NS_ASSUME_NONNULL_END
