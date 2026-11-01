#import <XCTest/XCTest.h>

#include <math.h>

#import "QLMSystemInternal.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMReplies.h"

// Sources: every capture, and qlm-control-all's notes.md. System's rule for
// a monitor switched on, run over the captures: in a run, a lease after a
// probe no monitor answered reads the wake count from the first frame
// after the lease's first that carries 8A.
@interface QLMPowerOnGoldenTests : XCTestCase
@end

// A lease the rule watches, as a capture shows it.
@interface QLMWatchedLease : NSObject
@property (nonatomic, copy) NSString *scenario;
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) NSTimeInterval sinceWake;  // since the last broadcast wake, or INFINITY
@property (nonatomic) NSTimeInterval probe;      // the quiet probe before it
@property (nonatomic) BOOL heardFirst;           // its first frame came
// The wake the count puts, less the probe: above 0 after it.
@property (nonatomic) NSTimeInterval sinceProbe;
@end

@implementation QLMWatchedLease
@end

@implementation QLMPowerOnGoldenTests

// Every watched lease whose count was read. With `forgets`, a host's run
// ends when it goes quiet for 2.6 s, as the adapter then takes over, and
// its probe is forgotten, as System forgets it at a start and a gap.
static NSArray<QLMWatchedLease *> *QLMWatchedLeases(BOOL forgets) {
    NSData *probe = QLMReportFor(QLMCommandProbe());
    NSSet<NSData *> *wakes = [NSSet setWithObjects:QLMReportFor(QLMCommandPower(QLMPowerStepWakeFirst)),
                                                   QLMReportFor(QLMCommandPower(QLMPowerStepWakeSecond)), nil];
    NSMutableArray<QLMWatchedLease *> *leases = [NSMutableArray array];
    for (NSString *scenario in QLMCaptureScenarios()) {
        NSTimeInterval lastSent = -INFINITY, quietProbe = NAN, lastWake = -INFINITY;
        NSMutableDictionary<NSNumber *, QLMWatchedLease *> *watched = [NSMutableDictionary dictionary];  // by session
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            QLMMessage message = exchange.message;
            if (forgets && exchange.time - lastSent > 2.6) {
                quietProbe = NAN;
                [watched removeAllObjects];
            }
            lastSent = exchange.time;
            if ([wakes containsObject:exchange.outputReport]) {
                lastWake = exchange.time;
            } else if ([exchange.outputReport isEqualToData:probe]) {
                if (!exchange.answered) {
                    quietProbe = exchange.time;
                }
            } else if (QLMIsLease(message) && exchange.answered) {
                NSNumber *session = @(message.payload[4]);
                [watched removeObjectForKey:session];
                if (!isnan(quietProbe)) {
                    QLMWatchedLease *lease = [QLMWatchedLease new];
                    lease.scenario = scenario;
                    lease.time = exchange.time;
                    lease.sinceWake = exchange.time - lastWake;
                    lease.probe = quietProbe;
                    watched[session] = lease;
                }
            } else if (QLMIsMonitorPoll(message) && exchange.answered) {
                NSNumber *session = @(message.address);
                QLMWatchedLease *lease = watched[session];
                QLMMessage reply = exchange.reply;
                QLMTelemetry t;
                QLMTelemetryStatus status = QLMReplyTelemetry(&reply, &t);
                if (lease == nil || (status != QLMTelemetryOK && status != QLMTelemetryErrorUnknownTag)) {
                    continue;
                }
                if (!lease.heardFirst) {
                    lease.heardFirst = YES;
                    continue;
                }
                int32_t count = QLMTelemetryWakeCount(&t);
                if (count != QLMTelemetryAbsent) {
                    lease.sinceProbe = exchange.time - count - lease.probe;
                    [leases addObject:lease];
                    [watched removeObjectForKey:session];
                }
            }
        }
    }
    return leases;
}

// The lease in qlm-control-all at `time`, to the millisecond.
static BOOL QLMIsControlAllLease(QLMWatchedLease *lease, NSTimeInterval time) {
    return [lease.scenario isEqualToString:@"qlm-control-all"] && fabs(lease.time - time) < 0.001;
}

// Checks that the leases split in two around QLMPowerOnMargin, and returns
// the split: the earliest and latest wake after the probe among those woken
// since it, and the latest among the rest. Each one woken came within 1.5 s
// of a broadcast wake, or is a lease in qlm-control-all at one of
// `switchedOn`.
- (NSArray<NSNumber *> *)splitOf:(NSArray<QLMWatchedLease *> *)leases
                           woken:(NSUInteger)wokenCount
                       runningOn:(NSUInteger)runningOnCount
                      switchedOn:(NSArray<NSNumber *> *)switchedOn {
    NSUInteger woken = 0, runningOn = 0;
    double earliestWoken = INFINITY, latestWoken = -INFINITY, latestRunningOn = -INFINITY;
    for (QLMWatchedLease *lease in leases) {
        if (lease.sinceProbe < 0) {
            runningOn += 1;
            latestRunningOn = MAX(latestRunningOn, lease.sinceProbe);
            continue;
        }
        woken += 1;
        earliestWoken = MIN(earliestWoken, lease.sinceProbe);
        latestWoken = MAX(latestWoken, lease.sinceProbe);
        NSUInteger known = [switchedOn indexOfObjectPassingTest:^BOOL(NSNumber *time, NSUInteger index, BOOL *stop) {
            return QLMIsControlAllLease(lease, time.doubleValue);
        }];
        XCTAssertTrue(known != NSNotFound || lease.sinceWake < 1.5, @"%@, leased at %.3f s", lease.scenario, lease.time);
    }
    XCTAssertEqual(woken, wokenCount);
    XCTAssertEqual(runningOn, runningOnCount);
    XCTAssertLessThan(latestRunningOn, -QLMPowerOnMargin);
    XCTAssertGreaterThan(earliestWoken, -QLMPowerOnMargin);
    return @[@(earliestWoken), @(latestWoken), @(latestRunningOn)];
}

// With each host run's probe forgotten, 43 leases put the wake 0.18 to
// 1.99 s after the probe. Each came within 1.5 s of a broadcast wake, but
// for the Rear Right 8330A switched on in qlm-control-all, leased at
// 214.774 s 0.84 s after its wake. The other 12 put it 327 s or more
// before. With no probe ever forgotten, the nearest of the rest is the Rear
// Right again, leased by GLM at 379.660 s, 67 s before a qlmctl run's last
// probe. The one more woken is the Rear Left at 191.986 s, whose count
// restarted at 175 s, between two runs. Only one capture has a power-on at
// the switch, and how long a slower model counts before it answers a probe
// is unmeasured, so the margin, 10 s, sits well clear of both sides.
- (void)testThePowerOnMarginSplitsEveryLease {
    NSArray<QLMWatchedLease *> *forgetting = QLMWatchedLeases(YES);
    NSArray<NSNumber *> *split = [self splitOf:forgetting woken:43 runningOn:12 switchedOn:@[@214.774]];
    XCTAssertEqualWithAccuracy(split[0].doubleValue, 0.18, 0.01);
    XCTAssertEqualWithAccuracy(split[1].doubleValue, 1.99, 0.01);
    XCTAssertEqualWithAccuracy(split[2].doubleValue, -327.28, 0.01);
    NSUInteger rearRight = [forgetting indexOfObjectPassingTest:^BOOL(QLMWatchedLease *lease, NSUInteger index, BOOL *stop) {
        return QLMIsControlAllLease(lease, 214.774);
    }];
    XCTAssertNotEqual(rearRight, NSNotFound);
    if (rearRight != NSNotFound) {
        XCTAssertEqualWithAccuracy(forgetting[rearRight].sinceProbe, 0.84, 0.01);
    }

    split = [self splitOf:QLMWatchedLeases(NO) woken:44 runningOn:69 switchedOn:@[@214.774, @191.986]];
    XCTAssertEqualWithAccuracy(split[0].doubleValue, 0.18, 0.01);
    XCTAssertEqualWithAccuracy(split[2].doubleValue, -67.29, 0.01);
}

@end
