#import <Foundation/Foundation.h>

#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QLMDSPBlockErrorDomain;

typedef NS_ERROR_ENUM(QLMDSPBlockErrorDomain, QLMDSPBlockError) {
    QLMDSPBlockErrorClass = 1,   // a node class with no known slot layout
    QLMDSPBlockErrorBands,       // not twenty bands, or a band in no slot
    QLMDSPBlockErrorUnstable,    // a designed filter with a pole outside the unit circle
    QLMDSPBlockErrorInput,       // an input the routing frame cannot say
};

// One monitor's DSP settings for one group, as the frames a group apply
// sends, in GLM's order: prepare, delay, level, the unknown level
// subcommand, twenty PEQ slots, crossover, input sync, routing. Each
// payload wants the monitor's session as its address.
@interface QLMDSPBlock : NSObject

+ (nullable instancetype)blockForNode:(QLMSetupNode *)node inGroup:(QLMSetupGroup *)group error:(NSError **)error;

// Blocks for every node that is on. Nil, with the error, if any node fails.
+ (nullable NSArray<QLMDSPBlock *> *)blocksForGroup:(QLMSetupGroup *)group error:(NSError **)error;

@property (nonatomic, readonly) QLMSetupNode *node;
@property (nonatomic, readonly) double designRate;
// The Safety rule: a group apply is refused for any model whose design rate
// is unverified. 48 kHz for a two-way and 12 kHz for a subwoofer are
// confirmed on the wire. Nothing else is, the 83x1 series included.
@property (nonatomic, readonly) BOOL rateVerified;
@property (nonatomic, readonly) NSArray<NSData *> *payloads;
@property (nonatomic, readonly) NSArray<NSString *> *warnings;

@end

NS_ASSUME_NONNULL_END
