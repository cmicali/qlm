#import <Foundation/Foundation.h>

#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QLMDSPBlockErrorDomain;

typedef NS_ERROR_ENUM(QLMDSPBlockErrorDomain, QLMDSPBlockError) {
    QLMDSPBlockErrorClass = 1,   // a node class with no known slot layout
    QLMDSPBlockErrorBands,       // not twenty bands, or a band in no slot
    QLMDSPBlockErrorUnstable,    // a designed filter with a pole outside the unit circle
    QLMDSPBlockErrorInput,       // an input the routing frame cannot say
    QLMDSPBlockErrorLFE,         // a subwoofer's LFE fields differ from every capture's
    QLMDSPBlockErrorThreeWay,    // an 8351B's GroupDelayCompensation or BassExtensionXO(Hz) differs from every capture's
};

// One monitor's DSP settings for one group, as the frames a group apply
// sends, in GLM's order. Each payload wants the monitor's session as its
// address. A two-way gets prepare, delay, level, the unknown level
// subcommand, twenty PEQ slots, crossover, input sync, and routing. A
// three-way gets 43 after the level pair, and 4B after the crossover. A
// subwoofer gets GLM's longer block: slot 0 four times, the delay three
// times, the routing pair five times, and 3C, 3E, and 42.
@interface QLMDSPBlock : NSObject

+ (nullable instancetype)blockForNode:(QLMSetupNode *)node inGroup:(QLMSetupGroup *)group error:(NSError **)error;

// Every node's block, on or off, keyed by its hardware ID. A node with no
// hardware ID gets none, since no monitor can match it. Nil, with the
// error, if any node's block fails.
+ (nullable NSDictionary<NSData *, QLMDSPBlock *> *)blocksByHardwareIDForGroup:(QLMSetupGroup *)group error:(NSError **)error;

@property (nonatomic, readonly) QLMSetupNode *node;
@property (nonatomic, readonly) double designRate;
// The Safety rule: a group apply is refused for any model whose design rate
// is unverified. 48 kHz for a two-way and 12 kHz for a subwoofer are
// confirmed on the wire. Nothing else is, the 83x1 series included.
@property (nonatomic, readonly) BOOL rateVerified;
@property (nonatomic, readonly) NSArray<NSData *> *payloads;  // from prepare on
// What a group switch's routing pass sends: the routing frame, and for a
// subwoofer the second one, 40 01 02 00 00.
@property (nonatomic, readonly) NSArray<NSData *> *routingPayloads;
@property (nonatomic, readonly) NSData *crossoverPayload;
@property (nonatomic, readonly) NSArray<NSString *> *warnings;

@end

NS_ASSUME_NONNULL_END
