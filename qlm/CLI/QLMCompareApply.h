#import <Foundation/Foundation.h>

#include <stdio.h>

#import "QLMCapture.h"
#import "QLMDSPBlock.h"
#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

// compare-apply's exit code when a pass differs from qlm's block, or matches
// no node qlm can build one for.
extern const int QLMCompareApplyDiffers;

// What GLM sent one session from its 17 01 through the 40 frames after its
// 3D. Only DSP opcodes are kept, so the polls between are dropped.
@interface QLMCapturedPass : NSObject
@property (nonatomic, readonly) uint8_t session;
@property (nonatomic, readonly) NSTimeInterval time;  // the 17 01's
@property (nonatomic, readonly) NSArray<NSData *> *payloads;
// Each 05 frame, the generator stop, GLM sent the session since its last
// pass, or the capture's start. At launch and wake it comes right before
// 17 01, and in a group switch in the routing pass.
@property (nonatomic, readonly) NSArray<NSData *> *generatorStops;
// From the session's last lease at or before the pass, and the reply to 39
// that follows it. Nil where the capture holds neither.
@property (nonatomic, readonly, nullable) NSString *model;
@property (nonatomic, readonly, nullable) NSData *hardwareID;
// GLM sent no 3D: a frame to the session that isn't a DSP frame, its next
// 17 01, or the capture's end, came first. GLM cuts a pass short when it
// leases the monitor again mid-pass.
@property (nonatomic, readonly) BOOL cutShort;
@end

// A frame GLM sent a session.
@interface QLMSessionFrame : NSObject
@property (nonatomic) uint8_t session;
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) NSData *payload;
// For a DSP frame outside a pass: the session's pass before it and after
// it, each when it is in the window.
@property (nonatomic, nullable) QLMCapturedPass *follows;
@property (nonatomic, nullable) QLMCapturedPass *precedes;
// From the session's lease, as a pass's.
@property (nonatomic, readonly, nullable) NSString *model;
@end

// Every generator stop, a 05 frame to a session, from `from` to before `to`,
// pass or no pass. A switch sends one to each monitor of the setup, the ones
// off in the new group included.
NSArray<QLMSessionFrame *> *QLMGeneratorStopsInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to);

// The generator stop's 14 bytes in every capture so far.
BOOL QLMIsKnownGeneratorStop(NSData *payload);

// Each pass whose 17 01 is from `from` to before `to`, in seconds into the
// capture. `outside` gets each DSP frame in the window that no pass holds:
// one GLM sent a session before a pass, or after one closed. A switch's
// routing frames and a band GLM sends as it's edited are such frames.
NSArray<QLMCapturedPass *> *QLMPassesInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to,
                                               NSArray<QLMSessionFrame *> *_Nullable *_Nullable outside);

// How a captured pass differs from a block. Payloads are compared by the
// setting each names: a PEQ slot, a level subcommand, a routing input, or
// the opcode alone. A pass cut short is compared with the block's start, as
// far as GLM got.
@interface QLMBlockComparison : NSObject

+ (instancetype)comparisonOfBlock:(QLMDSPBlock *)block withPass:(QLMCapturedPass *)pass;

// Each setting both send with other bytes, as GLM's payload, then qlm's.
@property (nonatomic, readonly) NSArray<NSArray<NSData *> *> *changed;
// What GLM sent and qlm's block lacks.
@property (nonatomic, readonly) NSArray<NSData *> *glmOnly;
@property (nonatomic, readonly) NSArray<NSData *> *qlmOnly;
// GLM's payloads are the block's in order.
@property (nonatomic, readonly) BOOL inOrder;
// changed, glmOnly, and qlmOnly, counted.
@property (nonatomic, readonly) NSUInteger differenceCount;
// No difference, and in order.
@property (nonatomic, readonly) BOOL matches;

@end

// A pass, the node whose block is closest to it, and how they compare.
@interface QLMPassMatch : NSObject
@property (nonatomic, readonly) QLMCapturedPass *pass;
@property (nonatomic, readonly) QLMSetupGroup *group;
// Nil when no node could be a match.
@property (nonatomic, readonly, nullable) QLMSetupNode *node;
@property (nonatomic, readonly, nullable) QLMDSPBlock *block;
@property (nonatomic, readonly, nullable) QLMBlockComparison *comparison;
// Other nodes as close, whose blocks differ from this one's.
@property (nonatomic, readonly) NSUInteger ties;
// An earlier pass, to another monitor, that matched the same node. A node
// is one monitor, so this pass can't match. Two leases in the capture with
// other hardware IDs are two monitors. So are two sessions neither leased
// in the capture, since a monitor leased again gets a lease there.
@property (nonatomic, readonly, nullable) QLMCapturedPass *earlierPass;
// The comparison matches, and no earlier pass took the node.
@property (nonatomic, readonly) BOOL matches;
@end

// Matches each pass to a node of `group`, the one whose block differs from
// the pass in the fewest settings, then in order. One group only: another
// group may hold a near copy of a node, which would hide a difference. Only nodes of the model the pass's 39 reply names count.
// When the setup holds the hardware ID the pass's lease names, as a raw
// copy does and a redacted one doesn't, only that node counts. A node qlm
// builds no block for is skipped, and `refusals` gets why, once per node.
NSArray<QLMPassMatch *> *QLMMatchPasses(NSArray<QLMCapturedPass *> *passes, QLMSetup *setup, QLMSetupGroup *group,
                                        NSArray<NSString *> *_Nullable *_Nullable refusals);

// The block's frame for the setting `payload` names, the last when it sends
// the setting twice. Nil for a setting it lacks.
NSData *_Nullable QLMBlockSetting(QLMDSPBlock *block, NSData *payload);

// compare-apply, given what follows the command's name. It reads a setup
// file and a capture's reports.txt, and opens no bus. It prints to `out`,
// and why it can't compare to `err`. It returns 0 when every pass matches
// and every generator stop in the window is the known one, and with
// --check-outside, every DSP frame outside a pass is explained. It returns
// QLMCompareApplyDiffers when not, EX_USAGE for an argument it doesn't
// know, and EX_DATAERR for a file it can't read, a group the setup lacks,
// or no pass to compare, unless --check-outside has frames outside a pass.
int QLMCompareApply(NSArray<NSString *> *arguments, FILE *out, FILE *err);

NS_ASSUME_NONNULL_END
