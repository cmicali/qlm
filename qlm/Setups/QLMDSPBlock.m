#import "QLMDSPBlock.h"

#include "QLMBiquad.h"
#include "QLMCommands.h"

NSErrorDomain const QLMDSPBlockErrorDomain = @"QLMDSPBlockErrorDomain";

enum { QLMPEQSlots = 20 };
static const double QLMDelayRate = 48000;  // delay is in 48 kHz samples on every device class

@interface QLMDSPBlock ()
@property (nonatomic, readwrite) QLMSetupNode *node;
@property (nonatomic, readwrite) double designRate;
@property (nonatomic, readwrite) NSArray<NSData *> *payloads;
@property (nonatomic, readwrite) NSArray<NSString *> *warnings;
@end

static NSError *QLMDSPBlockFail(QLMDSPBlockError code, NSString *message) {
    return [NSError errorWithDomain:QLMDSPBlockErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSData *QLMPayload(QLMMessage message) {
    return [NSData dataWithBytes:message.payload length:message.length];
}

static BOOL QLMRateVerified(QLMSetupNodeClass nodeClass, double designRate) {
    return (nodeClass == QLMSetupNodeClassTwoWay && designRate == 48000) ||
           (nodeClass == QLMSetupNodeClassSubwoofer && designRate == 12000);
}

@implementation QLMDSPBlock

// The slot a band takes. Two-way monitors: low shelves in 0 and 1, high
// shelves in 2 and 3, peaks in 4 to 19. Subwoofers: twenty peaks. A
// three-way is laid out like a two-way, as the 8351B's captured passes show.
static NSInteger QLMSlotForBand(QLMSetupBand *band, QLMSetupNodeClass nodeClass) {
    if (nodeClass == QLMSetupNodeClassSubwoofer) {
        return band.type == QLMSetupBandPeak ? band.index - 1 : -1;
    }
    switch (band.type) {
    case QLMSetupBandLowShelf: return band.index - 1;
    case QLMSetupBandHighShelf: return 2 + band.index - 1;
    case QLMSetupBandPeak: return 4 + band.index - 1;
    }
    return -1;
}

static QLMBiquad QLMDesign(QLMSetupBand *band, QLMSetupNodeClass nodeClass) {
    double highShelfQ = nodeClass == QLMSetupNodeClassThreeWay ? QLMBiquadThreeWayHighShelfQ : QLMBiquadHighShelfQ;
    switch (band.type) {
    case QLMSetupBandLowShelf: return QLMBiquadLowShelf(band.frequency, band.gain, QLMBiquadLowShelfQ, band.sampleRate);
    case QLMSetupBandHighShelf: return QLMBiquadHighShelf(band.frequency, band.gain, highShelfQ, band.sampleRate);
    case QLMSetupBandPeak: return QLMBiquadPeak(band.frequency, band.gain, band.q, band.sampleRate);
    }
    return QLMBiquadBypass();
}

+ (instancetype)blockForNode:(QLMSetupNode *)node inGroup:(QLMSetupGroup *)group error:(NSError **)error {
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    if (node.nodeClass == QLMSetupNodeClassUnknown) {
        if (error != NULL) *error = QLMDSPBlockFail(QLMDSPBlockErrorClass, [NSString stringWithFormat:@"no slot layout for %@", node.className]);
        return nil;
    }
    if (node.bands.count != QLMPEQSlots) {
        if (error != NULL) *error = QLMDSPBlockFail(QLMDSPBlockErrorBands, [NSString stringWithFormat:@"%lu bands, not 20", (unsigned long)node.bands.count]);
        return nil;
    }

    // Design every band into its slot, and refuse an unstable one.
    uint8_t packed[QLMPEQSlots][QLMBiquadPackedSize];
    BOOL filled[QLMPEQSlots] = {NO};
    double designRate = 0;
    for (QLMSetupBand *band in node.bands) {
        NSInteger slot = QLMSlotForBand(band, node.nodeClass);
        if (slot < 0 || slot >= (NSInteger)QLMPEQSlots || filled[slot]) {
            if (error != NULL) *error = QLMDSPBlockFail(QLMDSPBlockErrorBands, [NSString stringWithFormat:@"band %ld fits no slot", (long)band.index]);
            return nil;
        }
        QLMBiquad biquad = QLMDesign(band, node.nodeClass);
        if (!QLMBiquadIsStable(&biquad)) {
            if (error != NULL) *error = QLMDSPBlockFail(QLMDSPBlockErrorUnstable, [NSString stringWithFormat:@"band %ld at %.2f Hz is unstable", (long)band.index, band.frequency]);
            return nil;
        }
        QLMBiquadPack(&biquad, packed[slot]);
        filled[slot] = YES;
        if (designRate == 0) {
            designRate = band.sampleRate;
        } else if (band.sampleRate != designRate) {
            [warnings addObject:[NSString stringWithFormat:@"band %ld is designed at %.0f Hz, the others at %.0f Hz", (long)band.index, band.sampleRate, designRate]];
        }
    }

    if (!QLMRateVerified(node.nodeClass, designRate)) {
        [warnings addObject:[NSString stringWithFormat:@"%.0f Hz is unverified on the wire for %@", designRate, node.className]];
    }

    // Delay. A subwoofer's is its AutoPhase angle as a delay at the crossover.
    // A monitor's is Time-of-flight_Compensation, in milliseconds.
    uint32_t delay;
    if (node.nodeClass == QLMSetupNodeClassSubwoofer) {
        double phase = fmod(fmod(node.phaseDegrees.doubleValue, 360) + 360, 360);
        double crossover = node.crossoverFrequency > 0 ? node.crossoverFrequency : group.crossover;
        delay = crossover > 0 ? (uint32_t)round(phase / 360 / crossover * QLMDelayRate) : 0;
    } else {
        delay = (uint32_t)round(node.timeOfFlightCompensation / 1000 * QLMDelayRate);
    }

    // Routing. The setup's Input: 1 AES3 A, 2 AES3 B, 3 AES3 A+B, 4 analog.
    uint8_t source, pair, aesChannel;
    if (node.input >= 1 && node.input <= 3) {
        source = 0x02;
        pair = 0x00;
        aesChannel = (uint8_t)node.input;
    } else if (node.input == 4) {
        source = 0x01;
        pair = 0x02;
        aesChannel = 0x00;
        [warnings addObject:@"the analog routing frame is from one observed variant, unverified"];
    } else {
        if (error != NULL) *error = QLMDSPBlockFail(QLMDSPBlockErrorInput, [NSString stringWithFormat:@"input %ld has no routing", (long)node.input]);
        return nil;
    }

    uint32_t level = QLMLevelWordForDecibels(node.levelSensitivity + node.groupSensitivity);
    uint16_t crossover = (uint16_t)round(node.crossoverFrequency);

    NSMutableArray<NSData *> *payloads = [NSMutableArray arrayWithCapacity:QLMPEQSlots + 8];
    [payloads addObject:QLMPayload(QLMCommandPrepare(0))];
    [payloads addObject:QLMPayload(QLMCommandDelay(0, delay))];
    [payloads addObject:QLMPayload(QLMCommandLevel(0, level))];
    [payloads addObject:QLMPayload(QLMCommandLevelUnknown(0))];
    for (NSUInteger slot = 0; slot < QLMPEQSlots; slot++) {
        [payloads addObject:QLMPayload(QLMCommandPEQ(0, (uint8_t)slot, packed[slot]))];
    }
    [payloads addObject:QLMPayload(QLMCommandCrossover(0, crossover))];
    [payloads addObject:QLMPayload(QLMCommandInputSync(0))];
    [payloads addObject:QLMPayload(QLMCommandRouting(0, 0x00, source, pair, aesChannel))];

    QLMDSPBlock *block = [[QLMDSPBlock alloc] init];
    block.node = node;
    block.designRate = designRate;
    block.payloads = payloads;
    block.warnings = warnings;
    return block;
}

- (BOOL)rateVerified {
    return QLMRateVerified(_node.nodeClass, _designRate);
}

+ (NSArray<QLMDSPBlock *> *)blocksForGroup:(QLMSetupGroup *)group error:(NSError **)error {
    NSMutableArray<QLMDSPBlock *> *blocks = [NSMutableArray array];
    for (QLMSetupNode *node in group.nodes) {
        if (!node.on) {
            continue;
        }
        QLMDSPBlock *block = [self blockForNode:node inGroup:group error:error];
        if (block == nil) {
            return nil;
        }
        [blocks addObject:block];
    }
    return blocks;
}

@end
