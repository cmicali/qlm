#import "QLMTestSupport.h"

#include <math.h>

#include "QLMCommands.h"
#include "QLMReport.h"

// Sources: captures/volume-sweep, where GLM's volume was dragged from 0 dB
// to the bottom and back, and captures/knob-sweep, where the adapter's knob
// was turned. volume-sweep holds GLM's level for every 0.5 dB step from 0
// to -99.5 dB. The step a level belongs to is 20 log10(level / 7FFFFF), to
// the nearest step. The knob's readings name the same steps.
@interface QLMVolumeScaleTests : XCTestCase
@end

@implementation QLMVolumeScaleTests

// For each step from 0 dB down, a broadcast of its level in volume-sweep.
static const NSTimeInterval QLMSweepTimes[] = {
    34.054182, 34.027956, 34.013398, 33.977986, 33.964204, 33.943390, 33.915204, 33.896436,
    33.883035, 33.869596, 33.848475, 33.816474, 33.793546, 33.780320, 33.754421, 33.734477,
    33.711669, 33.686974, 33.669089, 33.645570, 33.622410, 33.587387, 33.545570, 33.513601,
    33.454336, 33.415504, 33.378159, 33.336653, 33.311962, 33.294441, 33.269047, 33.236041,
    33.211988, 33.180019, 33.148575, 33.114463, 33.082284, 33.057140, 33.033294, 33.002360,
    32.959710, 32.918183, 32.885754, 32.862743, 32.828146, 32.812014, 32.795676, 32.784449,
    32.726896, 32.684196, 32.651659, 32.636169, 32.610156, 32.579660, 32.548959, 32.527991,
    32.498183, 32.482366, 32.475263, 32.456920, 32.436709, 32.412904, 32.402002, 32.377996,
    32.370612, 32.346328, 32.342820, 32.325670, 32.298641, 32.275992, 32.261724, 32.228491,
    32.211379, 32.186363, 32.171893, 32.136346, 32.110640, 32.085060, 32.060602, 32.045266,
    32.027890, 32.012620, 31.985849, 31.962208, 31.959665, 31.934639, 31.918129, 31.903127,
    37.286113, 31.869913, 31.847993, 31.831844, 31.819252, 31.795711, 31.771125, 31.749390,
    31.727895, 31.700195, 31.677520, 31.661113, 31.636114, 31.617365, 31.603043, 31.580472,
    31.547973, 31.528139, 31.513057, 31.477902, 31.434605, 31.413366, 31.370117, 31.364044,
    31.331377, 0.381081, 31.277420, 31.250739, 31.217669, 31.184042, 31.161546, 31.146210,
    31.127737, 31.102668, 31.080589, 31.070495, 31.044049, 31.020053, 31.011971, 30.981086,
    30.960630, 30.946739, 30.926613, 30.899490, 30.883657, 30.864593, 30.835249, 30.811499,
    30.797242, 30.768265, 30.755493, 30.714667, 30.677974, 30.660765, 30.651745, 30.624044,
    30.616403, 30.592046, 30.575634, 30.552000, 30.536196, 30.528500, 30.511585, 30.492626,
    30.482028, 30.462888, 30.451126, 30.435584, 30.417445, 30.403279, 30.397138, 30.378001,
    30.350487, 30.326005, 30.321726, 30.271350, 30.238638, 30.210130, 30.178460, 30.142900,
    30.118767, 30.092652, 30.069958, 30.061445, 30.028124, 38.527862, 30.010181, 29.993727,
    29.976935, 29.950496, 29.943878, 29.926948, 29.893043, 29.876503, 29.851979, 29.835942,
    29.809882, 29.785828, 29.754036, 29.729839, 29.698129, 29.677138, 29.652885, 29.634428,
    29.618269, 29.613449, 28.230183, 25.338461, 28.309291, 28.320170, 25.228303, 28.352018,
};

static QLMCaptureExchange *_Nullable QLMExchangeAt(QLMCapture *capture, NSTimeInterval time) {
    for (QLMCaptureExchange *exchange in capture.exchanges) {
        if (fabs(exchange.time - time) < 0.0005) {
            return exchange;
        }
    }
    return nil;
}

static NSData *_Nullable QLMPacked(QLMMessage message) {
    uint8_t report[QLMReportLength];
    if (QLMReportPackOutput(&message, report) != QLMReportOK) {
        return nil;
    }
    return QLMBytes(report, sizeof report);
}

// Each step's word, and the frame GLM sent at the time given, byte for byte.
- (void)testEveryStepIsTheLevelGLMSent {
    QLMCapture *capture = QLMReadCapture(@"volume-sweep", NULL);
    XCTAssertNotNil(capture);
    size_t count = sizeof QLMSweepTimes / sizeof QLMSweepTimes[0];
    XCTAssertEqual(count, 200u);
    for (size_t i = 0; i < count; i++) {
        double decibels = -QLMVolumeDecibelsStep * (double)i;
        QLMCaptureExchange *exchange = QLMExchangeAt(capture, QLMSweepTimes[i]);
        uint32_t word = QLMVolumeWordOf(exchange.message);
        XCTAssertEqual(round(QLMVolumeDecibelsForWord(word) / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep, decibels);
        XCTAssertEqual(QLMVolumeWordForDecibels(decibels), word, @"%.1f dB", decibels);
        XCTAssertEqualObjects(exchange.outputReport, QLMPacked(QLMCommandVolume(decibels, 0)), @"%.1f dB at %.6f s", decibels,
                              QLMSweepTimes[i]);
    }
}

// The top stop, QLMVolumeDecibelsMax, is 0 dB and sends 7F FF FF, as
// section 4 of hlm's spec gives: GLM's level at 0 dB (volume-sweep, 34.05 s).
- (void)testTheTopStopIsGLMs {
    XCTAssertEqual(QLMVolumeDecibelsMax, 0.0);
    XCTAssertEqual(QLMVolumeWordForDecibels(QLMVolumeDecibelsMax), 0x7FFFFFu);
    QLMCaptureExchange *exchange = QLMExchangeAt(QLMReadCapture(@"volume-sweep", NULL), QLMSweepTimes[0]);
    XCTAssertEqual(QLMVolumeWordOf(exchange.message), 0x7FFFFFu);
    XCTAssertEqualObjects(exchange.outputReport, QLMPacked(QLMCommandVolume(QLMVolumeDecibelsMax, QLMVolumeDecibelsMax)));
}

// The bottom stop sends 00 00 08: the volume dragged to the bottom
// (volume-sweep, 28.36 s).
- (void)testTheBottomStopIsGLMs {
    XCTAssertEqual(QLMVolumeWordForDecibels(QLMVolumeDecibelsMin), (uint32_t)QLMVolumeWordMin);
    QLMCaptureExchange *exchange = QLMExchangeAt(QLMReadCapture(@"volume-sweep", NULL), 28.361751);
    XCTAssertEqualObjects(exchange.outputReport, QLMPacked(QLMCommandVolume(QLMVolumeDecibelsMin, 0)));
}

// The knob reads tenths of a dB, and GLM sends the nearest step. Each level
// here follows the knob's reading in the poll just before it.
- (void)testTheKnobNamesTheSteps {
    const struct {
        NSTimeInterval time;
        int32_t tenths;
    } turns[] = {
        {19.241470, -417}, {19.584757, -287}, {19.736508, -137}, {19.844379, -36},
        {20.066483, -11},  {20.180628, 0},    {24.738609, -123}, {32.994992, -1000},
    };
    QLMCapture *capture = QLMReadCapture(@"knob-sweep", NULL);
    QLMMessage adapterPoll = QLMCommandPoll(QLMAddressReply);
    NSData *adapterPollRecord = QLMAdapterRecord(&adapterPoll);
    for (size_t i = 0; i < sizeof turns / sizeof turns[0]; i++) {
        NSTimeInterval time = turns[i].time;
        QLMCaptureExchange *level = QLMExchangeAt(capture, time);
        XCTAssertNotNil(level, @"%.6f s", time);
        if (level == nil) {
            continue;
        }
        QLMCaptureExchange *poll = nil;
        for (NSUInteger j = [capture.exchanges indexOfObjectIdenticalTo:level]; j-- > 0;) {
            QLMMessage message = capture.exchanges[j].message;
            if ([QLMAdapterRecord(&message) isEqualToData:adapterPollRecord]) {
                poll = capture.exchanges[j];
                break;
            }
        }
        // The knob's field is last: DF, then four bytes, big-endian.
        QLMMessage reply = poll.reply;
        XCTAssertGreaterThanOrEqual(reply.length, 5u, @"%.6f s", time);
        if (reply.length < 5) {
            continue;
        }
        const uint8_t *field = reply.payload + reply.length - 5;
        XCTAssertEqual(field[0], 0xDF);
        int32_t tenths = (int32_t)((uint32_t)field[1] << 24 | (uint32_t)field[2] << 16 | (uint32_t)field[3] << 8 | field[4]);
        XCTAssertEqual(tenths, turns[i].tenths);
        XCTAssertEqualObjects(level.outputReport, QLMPacked(QLMCommandVolume(tenths / 10.0, 0)), @"%.6f s", time);
    }
}

// Every volume frame in every capture is a step, the bottom stop, or the
// duck under a group switch.
- (void)testEveryVolumeFrameGLMSentIsAStep {
    NSMutableSet<NSNumber *> *steps = [NSMutableSet set];
    for (int i = 0; i <= 200; i++) {
        [steps addObject:@(QLMVolumeWordForDecibels(-QLMVolumeDecibelsStep * i))];
    }
    XCTAssertEqual(steps.count, 201u);
    NSUInteger frames = 0;
    for (NSString *scenario in QLMCaptureScenarios()) {
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            QLMMessage message = exchange.message;
            if (message.payload[0] != 0x1F) {
                continue;
            }
            XCTAssertEqual(message.address, QLMAddressBroadcast);
            XCTAssertEqual(message.length, 4u);
            uint32_t word = QLMVolumeWordOf(message);
            frames += 1;
            if (word != QLMVolumeWordDuck) {
                XCTAssertTrue([steps containsObject:@(word)], @"%@ at %.6f s: %06X", scenario, exchange.time, word);
            }
        }
    }
    XCTAssertGreaterThan(frames, 1000u);
}

@end
