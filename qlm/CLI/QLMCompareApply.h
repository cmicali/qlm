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
// From the session's reply to 39, where the capture holds one.
@property (nonatomic, readonly, nullable) NSString *model;
// From the last lease of the session in the capture, where it holds one.
@property (nonatomic, readonly, nullable) NSData *hardwareID;
@end

// Each pass whose 17 01 is from `from` to before `to`, in seconds into the
// capture.
NSArray<QLMCapturedPass *> *QLMPassesInCapture(QLMCapture *capture, NSTimeInterval from, NSTimeInterval to);

// How a captured pass differs from a block. Payloads are compared by the
// setting each names: a PEQ slot, a level subcommand, a routing input, or
// the opcode alone.
@interface QLMBlockComparison : NSObject

+ (instancetype)comparisonOfBlock:(QLMDSPBlock *)block withPass:(QLMCapturedPass *)pass;

// Each setting both send with other bytes, as GLM's payload, then qlm's.
@property (nonatomic, readonly) NSArray<NSArray<NSData *> *> *changed;
// What GLM sent and qlm's block lacks, past what qlm knowingly leaves out.
@property (nonatomic, readonly) NSArray<NSData *> *glmOnly;
// What qlm knowingly leaves out, as GLM sent it: the generator stop, and
// the block's leftOutPayloads.
@property (nonatomic, readonly) NSArray<NSData *> *leftOut;
// The block's leftOutPayloads this pass lacks.
@property (nonatomic, readonly) NSArray<NSData *> *missingLeftOut;
@property (nonatomic, readonly) NSArray<NSData *> *qlmOnly;
// GLM's payloads, less what qlm leaves out, are the block's in order.
@property (nonatomic, readonly) BOOL inOrder;
// changed, glmOnly, missingLeftOut, and qlmOnly, counted.
@property (nonatomic, readonly) NSUInteger differenceCount;
// No difference, and in order.
@property (nonatomic, readonly) BOOL matches;

@end

// A pass, the node whose block is closest to it, and how they compare.
@interface QLMPassMatch : NSObject
@property (nonatomic, readonly) QLMCapturedPass *pass;
// Nil when no node could be a match.
@property (nonatomic, readonly, nullable) QLMSetupGroup *group;
@property (nonatomic, readonly, nullable) QLMSetupNode *node;
@property (nonatomic, readonly, nullable) QLMDSPBlock *block;
@property (nonatomic, readonly, nullable) QLMBlockComparison *comparison;
// Other nodes as close, whose blocks differ from this one's.
@property (nonatomic, readonly) NSUInteger ties;
@end

// Matches each pass to a node of `groups`, all of `setup`'s when nil. The
// node is the one whose block differs from the pass in the fewest settings,
// then in order. Only nodes of the model the pass's 39 reply names count.
// When the setup holds the hardware ID the pass's lease names, as a raw
// copy does and a redacted one doesn't, only that node counts. A node qlm
// builds no block for is skipped, and `refusals` gets why, once per node.
NSArray<QLMPassMatch *> *QLMMatchPasses(NSArray<QLMCapturedPass *> *passes, QLMSetup *setup,
                                        NSArray<QLMSetupGroup *> *_Nullable groups,
                                        NSArray<NSString *> *_Nullable *_Nullable refusals);

// compare-apply, given what follows the command's name. It reads a setup
// file and a capture's reports.txt, and opens no bus. It prints to `out`,
// and why it can't compare to `err`. It returns 0 when every pass matches,
// QLMCompareApplyDiffers when one doesn't, EX_USAGE for an argument it
// doesn't know, and EX_DATAERR for a file it can't read, a group the setup
// lacks, or no pass to compare.
int QLMCompareApply(NSArray<NSString *> *arguments, FILE *out, FILE *err);

NS_ASSUME_NONNULL_END
