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

typedef struct {
    double decibels;
    uint32_t word;
    NSTimeInterval time;  // a broadcast of this level in volume-sweep
} QLMSweepLevel;

static const QLMSweepLevel QLMSweepLevels[] = {
    {0.0, 0x7FFFFF, 34.054182}, {-0.5, 0x78D6FB, 34.027956}, {-1.0, 0x721481, 34.013398},
    {-1.5, 0x6BB2D5, 33.977986}, {-2.0, 0x65AC8B, 33.964204}, {-2.5, 0x5FFC88, 33.943390},
    {-3.0, 0x5A9DF7, 33.915204}, {-3.5, 0x558C4A, 33.896436}, {-4.0, 0x50C335, 33.883035},
    {-4.5, 0x4C3EA7, 33.869596}, {-5.0, 0x47FACC, 33.848475}, {-5.5, 0x43F405, 33.816474},
    {-6.0, 0x4026E6, 33.793546}, {-6.5, 0x3C9038, 33.780320}, {-7.0, 0x392CED, 33.754421},
    {-7.5, 0x35FA26, 33.734477}, {-8.0, 0x32F52C, 33.711669}, {-8.5, 0x301B70, 33.686974},
    {-9.0, 0x2D6A86, 33.669089}, {-9.5, 0x2AE025, 33.645570}, {-10.0, 0x287A26, 33.622410},
    {-10.5, 0x263680, 33.587387}, {-11.0, 0x241346, 33.545570}, {-11.5, 0x220EA9, 33.513601},
    {-12.0, 0x2026F2, 33.454336}, {-12.5, 0x1E5A84, 33.415504}, {-13.0, 0x1CA7D7, 33.378159},
    {-13.5, 0x1B0D7A, 33.336653}, {-14.0, 0x198A13, 33.311962}, {-14.5, 0x181C57, 33.294441},
    {-15.0, 0x16C310, 33.269047}, {-15.5, 0x157D1A, 33.236041}, {-16.0, 0x144960, 33.211988},
    {-16.5, 0x1326DD, 33.180019}, {-17.0, 0x12149A, 33.148575}, {-17.5, 0x1111AE, 33.114463},
    {-18.0, 0x101D3F, 33.082284}, {-18.5, 0x0F367B, 33.057140}, {-19.0, 0x0E5CA1, 33.033294},
    {-19.5, 0x0D8EF6, 33.002360}, {-20.0, 0x0CCCCC, 32.959710}, {-20.5, 0x0C157F, 32.918183},
    {-21.0, 0x0B6873, 32.885754}, {-21.5, 0x0AC515, 32.862743}, {-22.0, 0x0A2ADA, 32.828146},
    {-22.5, 0x099940, 32.812014}, {-23.0, 0x090FCB, 32.795676}, {-23.5, 0x088E07, 32.784449},
    {-24.0, 0x081385, 32.726896}, {-24.5, 0x079FDD, 32.684196}, {-25.0, 0x0732AE, 32.651659},
    {-25.5, 0x06CB9A, 32.636169}, {-26.0, 0x066A4A, 32.610156}, {-26.5, 0x060E6B, 32.579660},
    {-27.0, 0x05B7B1, 32.548959}, {-27.5, 0x0565D0, 32.527991}, {-28.0, 0x051884, 32.498183},
    {-28.5, 0x04CF8B, 32.482366}, {-29.0, 0x048AA7, 32.475263}, {-29.5, 0x04499D, 32.456920},
    {-30.0, 0x040C37, 32.436709}, {-30.5, 0x03D240, 32.412904}, {-31.0, 0x039B87, 32.402002},
    {-31.5, 0x0367DD, 32.377996}, {-32.0, 0x033718, 32.370612}, {-32.5, 0x03090D, 32.346328},
    {-33.0, 0x02DD95, 32.342820}, {-33.5, 0x02B48C, 32.325670}, {-34.0, 0x028DCE, 32.298641},
    {-34.5, 0x02693B, 32.275992}, {-35.0, 0x0246B4, 32.261724}, {-35.5, 0x02261C, 32.228491},
    {-36.0, 0x020756, 32.211379}, {-36.5, 0x01EA49, 32.186363}, {-37.0, 0x01CEDC, 32.171893},
    {-37.5, 0x01B4F7, 32.136346}, {-38.0, 0x019C86, 32.110640}, {-38.5, 0x018572, 32.085060},
    {-39.0, 0x016FA9, 32.060602}, {-39.5, 0x015B18, 32.045266}, {-40.0, 0x0147AE, 32.027890},
    {-40.5, 0x013559, 32.012620}, {-41.0, 0x01240B, 31.985849}, {-41.5, 0x0113B5, 31.962208},
    {-42.0, 0x010449, 31.959665}, {-42.5, 0x00F5B9, 31.934639}, {-43.0, 0x00E7FA, 31.918129},
    {-43.5, 0x00DB00, 31.903127}, {-44.0, 0x00CEC0, 37.286113}, {-44.5, 0x00C32F, 31.869913},
    {-45.0, 0x00B844, 31.847993}, {-45.5, 0x00ADF5, 31.831844}, {-46.0, 0x00A43A, 31.819252},
    {-46.5, 0x009B0A, 31.795711}, {-47.0, 0x00925E, 31.771125}, {-47.5, 0x008A2E, 31.749390},
    {-48.0, 0x008273, 31.727895}, {-48.5, 0x007B27, 31.700195}, {-49.0, 0x007443, 31.677520},
    {-49.5, 0x006DC2, 31.661113}, {-50.0, 0x00679F, 31.636114}, {-50.5, 0x0061D3, 31.617365},
    {-51.0, 0x005C5A, 31.603043}, {-51.5, 0x00572F, 31.580472}, {-52.0, 0x00524F, 31.547973},
    {-52.5, 0x004DB4, 31.528139}, {-53.0, 0x00495B, 31.513057}, {-53.5, 0x004541, 31.477902},
    {-54.0, 0x004161, 31.434605}, {-54.5, 0x003DB9, 31.413366}, {-55.0, 0x003A45, 31.370117},
    {-55.5, 0x003702, 31.364044}, {-56.0, 0x0033EF, 31.331377}, {-56.5, 0x003107, 0.381081},
    {-57.0, 0x002E49, 31.277420}, {-57.5, 0x002BB2, 31.250739}, {-58.0, 0x002940, 31.217669},
    {-58.5, 0x0026F1, 31.184042}, {-59.0, 0x0024C4, 31.161546}, {-59.5, 0x0022B5, 31.146210},
    {-60.0, 0x0020C4, 31.127737}, {-60.5, 0x001EEF, 31.102668}, {-61.0, 0x001D34, 31.080589},
    {-61.5, 0x001B92, 31.070495}, {-62.0, 0x001A07, 31.044049}, {-62.5, 0x001892, 31.020053},
    {-63.0, 0x001732, 31.011971}, {-63.5, 0x0015E6, 30.981086}, {-64.0, 0x0014AC, 30.960630},
    {-64.5, 0x001384, 30.946739}, {-65.0, 0x00126D, 30.926613}, {-65.5, 0x001165, 30.899490},
    {-66.0, 0x00106C, 30.883657}, {-66.5, 0x000F81, 30.864593}, {-67.0, 0x000EA3, 30.835249},
    {-67.5, 0x000DD1, 30.811499}, {-68.0, 0x000D0B, 30.797242}, {-68.5, 0x000C50, 30.768265},
    {-69.0, 0x000BA0, 30.755493}, {-69.5, 0x000AF9, 30.714667}, {-70.0, 0x000A5C, 30.677974},
    {-70.5, 0x0009C8, 30.660765}, {-71.0, 0x00093C, 30.651745}, {-71.5, 0x0008B7, 30.624044},
    {-72.0, 0x00083B, 30.616403}, {-72.5, 0x0007C5, 30.592046}, {-73.0, 0x000755, 30.575634},
    {-73.5, 0x0006EC, 30.552000}, {-74.0, 0x000689, 30.536196}, {-74.5, 0x00062C, 30.528500},
    {-75.0, 0x0005D3, 30.511585}, {-75.5, 0x000580, 30.492626}, {-76.0, 0x000531, 30.482028},
    {-76.5, 0x0004E7, 30.462888}, {-77.0, 0x0004A0, 30.451126}, {-77.5, 0x00045E, 30.435584},
    {-78.0, 0x000420, 30.417445}, {-78.5, 0x0003E4, 30.403279}, {-79.0, 0x0003AD, 30.397138},
    {-79.5, 0x000378, 30.378001}, {-80.0, 0x000346, 30.350487}, {-80.5, 0x000317, 30.326005},
    {-81.0, 0x0002EB, 30.321726}, {-81.5, 0x0002C1, 30.271350}, {-82.0, 0x00029A, 30.238638},
    {-82.5, 0x000275, 30.210130}, {-83.0, 0x000251, 30.178460}, {-83.5, 0x000230, 30.142900},
    {-84.0, 0x000211, 30.118767}, {-84.5, 0x0001F3, 30.092652}, {-85.0, 0x0001D7, 30.069958},
    {-85.5, 0x0001BD, 30.061445}, {-86.0, 0x0001A4, 30.028124}, {-86.5, 0x00018C, 38.527862},
    {-87.0, 0x000176, 30.010181}, {-87.5, 0x000161, 29.993727}, {-88.0, 0x00014D, 29.976935},
    {-88.5, 0x00013B, 29.950496}, {-89.0, 0x000129, 29.943878}, {-89.5, 0x000118, 29.926948},
    {-90.0, 0x000109, 29.893043}, {-90.5, 0x0000FA, 29.876503}, {-91.0, 0x0000EC, 29.851979},
    {-91.5, 0x0000DF, 29.835942}, {-92.0, 0x0000D2, 29.809882}, {-92.5, 0x0000C6, 29.785828},
    {-93.0, 0x0000BB, 29.754036}, {-93.5, 0x0000B1, 29.729839}, {-94.0, 0x0000A7, 29.698129},
    {-94.5, 0x00009E, 29.677138}, {-95.0, 0x000095, 29.652885}, {-95.5, 0x00008C, 29.634428},
    {-96.0, 0x000084, 29.618269}, {-96.5, 0x00007D, 29.613449}, {-97.0, 0x000076, 28.230183},
    {-97.5, 0x00006F, 25.338461}, {-98.0, 0x000069, 28.309291}, {-98.5, 0x000063, 28.320170},
    {-99.0, 0x00005E, 25.228303}, {-99.5, 0x000058, 28.352018},
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

static uint32_t QLMVolumeWordOf(QLMMessage message) {
    return (uint32_t)message.payload[1] << 16 | (uint32_t)message.payload[2] << 8 | message.payload[3];
}

// Each step's word, and the frame GLM sent at the time given, byte for byte.
- (void)testEveryStepIsTheLevelGLMSent {
    QLMCapture *capture = QLMReadCapture(@"volume-sweep", NULL);
    XCTAssertNotNil(capture);
    size_t count = sizeof QLMSweepLevels / sizeof QLMSweepLevels[0];
    XCTAssertEqual(count, 200u);
    for (size_t i = 0; i < count; i++) {
        QLMSweepLevel level = QLMSweepLevels[i];
        XCTAssertEqual(level.decibels, -QLMVolumeDecibelsStep * (double)i);
        XCTAssertEqual(round(QLMVolumeDecibelsForWord(level.word) / QLMVolumeDecibelsStep) * QLMVolumeDecibelsStep, level.decibels);
        if (i > 0) {
            XCTAssertLessThan(level.word, QLMSweepLevels[i - 1].word);
        }
        XCTAssertEqual(QLMVolumeWordForDecibels(level.decibels), level.word, @"%.1f dB", level.decibels);
        QLMCaptureExchange *exchange = QLMExchangeAt(capture, level.time);
        XCTAssertEqualObjects(exchange.outputReport, QLMPacked(QLMCommandVolume(level.decibels, 0)), @"%.1f dB at %.6f s",
                              level.decibels, level.time);
    }
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
