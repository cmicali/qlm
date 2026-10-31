#import <XCTest/XCTest.h>

#import "QLMAlerts.h"
#import "QLMFakeBus.h"
#import "QLMFormat.h"
#import "QLMMonitorList.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"

// Records each alert in place of the notification center.
@interface QLMAlertRecorder : NSObject <QLMAlertPosting>
@property (nonatomic) NSMutableArray<NSString *> *titles;
@end

@implementation QLMAlertRecorder

- (instancetype)init {
    self = [super init];
    if (self) {
        _titles = [NSMutableArray array];
    }
    return self;
}

- (void)postIdentifier:(NSString *)identifier title:(NSString *)title body:(NSString *)body {
    [self.titles addObject:title];
}

@end

// The app's alerts, fed the fake bus's snapshots on the virtual clock, as
// the app feeds them System's. Each alert fires once until its cause
// clears, so a week of daily use doesn't repeat one every night.
@interface QLMMonitorAlertsTests : XCTestCase
@end

@implementation QLMMonitorAlertsTests {
    QLMVirtualClock *_time;
    QLMFakeBus *_bus;
    QLMSystem *_system;
    QLMMonitorList *_list;
    QLMAlertRecorder *_recorder;
    QLMMonitorAlerts *_alerts;
}

- (void)setUp {
    [super setUp];
    _time = [[QLMVirtualClock alloc] init];
    _bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = _time;
    _system = [[QLMSystem alloc] initWithAdapter:_bus settings:settings];
    _list = [[QLMMonitorList alloc] init];
    _recorder = [[QLMAlertRecorder alloc] init];
    _alerts = [[QLMMonitorAlerts alloc] initWithPoster:_recorder clock:_time];
    [_system start];
    [_system setVolumeDecibels:-45];
    [self updateWhen:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.anyOn;
    }];
}

- (void)tearDown {
    __block BOOL stopped = NO;
    [_system stopWithCompletion:^{
        stopped = YES;
    }];
    XCTAssertTrue([_time runUntil:^BOOL {
        return stopped;
    } within:60]);
    [super tearDown];
}

// Runs the clock until the condition holds on an idle snapshot, then hands
// that snapshot to the list and the alerts, as the app does.
- (void)updateWhen:(BOOL (^)(QLMSnapshot *snapshot))condition {
    QLMSystem *system = _system;
    XCTAssertTrue([_time runUntil:^BOOL {
        QLMSnapshot *snapshot = system.snapshot;
        return snapshot.idle && condition(snapshot);
    } within:60], @"the condition never held");
    [_list updateWithSnapshot:_system.snapshot];
    [_alerts updateWithMonitorList:_list];
}

- (QLMFakeMonitor *)left {
    return _bus.monitors.firstObject;
}

- (nullable QLMMonitorState *)stateOf:(QLMFakeMonitor *)fake in:(QLMSnapshot *)snapshot {
    for (QLMMonitorState *monitor in snapshot.monitors) {
        if ([monitor.hardwareID isEqualToData:fake.hardwareID]) {
            return monitor;
        }
    }
    return nil;
}

// Switched off and on again, so it holds no lease.
- (void)setLeftPresent:(BOOL)present on:(BOOL)on {
    QLMFakeMonitor *left = [self left];
    [_bus perform:^{
        left.present = present;
        left.on = on;
        left.session = 0;
    }];
}

- (void)dropLeft {
    [self setLeftPresent:NO on:YES];
    [self updateWhen:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 1;
    }];
}

- (void)bringBackLeftOn:(BOOL)on {
    [self setLeftPresent:YES on:on];
    QLMMonitorStatus status = on ? QLMMonitorStatusOn : QLMMonitorStatusStandby;
    [self updateWhen:^BOOL(QLMSnapshot *snapshot) {
        return [self stateOf:[self left] in:snapshot].status == status;
    }];
}

- (void)setLeftTemperature:(uint8_t)temperature {
    QLMFakeMonitor *left = [self left];
    [_bus perform:^{
        left.temperature = temperature;
    }];
    [self updateWhen:^BOOL(QLMSnapshot *snapshot) {
        return [self stateOf:[self left] in:snapshot].temperature == temperature;
    }];
}

// Past the 10 minutes between two alerts of a kind, so only the rule under
// test can hold one back.
- (void)passTheAlertInterval {
    [_time stallFor:11 * 60];
}

// A monitor in standby may drop and come back all night, so only one back
// and on alerts again.
- (void)testADropAlertsOnceUntilTheMonitorIsBackAndOn {
    [self dropLeft];
    XCTAssertEqualObjects(_recorder.titles, @[@"8330A dropped off the bus"]);

    [self passTheAlertInterval];
    [self bringBackLeftOn:NO];
    [self passTheAlertInterval];
    [self dropLeft];
    XCTAssertEqual(_recorder.titles.count, 1u, @"%@", _recorder.titles);

    [self bringBackLeftOn:YES];
    [self passTheAlertInterval];
    [self dropLeft];
    XCTAssertEqual(_recorder.titles.count, 2u, @"%@", _recorder.titles);
}

// Within 10 minutes of the last, a monitor back and on that drops again
// says nothing.
- (void)testADropWithinTheIntervalSaysNothing {
    [self dropLeft];
    [self bringBackLeftOn:YES];
    [self dropLeft];
    XCTAssertEqualObjects(_recorder.titles, @[@"8330A dropped off the bus"]);
}

// A hot monitor alerts once, and again only once it has cooled 5 °C.
- (void)testAHotMonitorAlertsOnceUntilItCools {
    [self setLeftTemperature:72];
    XCTAssertEqualObjects(_recorder.titles, @[@"8330A runs hot"]);
    [self passTheAlertInterval];
    [self setLeftTemperature:68];
    [self setLeftTemperature:71];
    XCTAssertEqual(_recorder.titles.count, 1u);

    [self setLeftTemperature:64];
    [self passTheAlertInterval];
    [self setLeftTemperature:70];
    XCTAssertEqual(_recorder.titles.count, 2u);
}

// While dimmed, the knob sits above qlm's level, so every sleep's take-over
// is louder. That alerts at most once a day. Undimmed, each sleep alerts.
- (void)testASleepWhileDimmedAlertsOnceADay {
    [_bus perform:^{
        self->_bus.knobTenths = @(-200);
    }];
    [_system setDimmed:YES];
    [self updateWhen:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.dimmed && snapshot.handBack.kind == QLMHandBackLouder;
    }];
    QLMSnapshot *dimmed = _system.snapshot;
    XCTAssertTrue(QLMStopMayRaiseLevel(dimmed));

    [_alerts alertSleepWithSnapshot:dimmed];
    XCTAssertEqualObjects(_recorder.titles, @[@"The level may have risen as the Mac slept"]);
    [_time stallFor:20 * 60 * 60];
    [_alerts alertSleepWithSnapshot:dimmed];
    XCTAssertEqual(_recorder.titles.count, 1u);
    [_time stallFor:4 * 60 * 60];
    [_alerts alertSleepWithSnapshot:dimmed];
    XCTAssertEqual(_recorder.titles.count, 2u);

    [_system setDimmed:NO];
    [self updateWhen:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.dimmed && snapshot.handBack.kind == QLMHandBackLouder;
    }];
    QLMSnapshot *undimmed = _system.snapshot;
    [_alerts alertSleepWithSnapshot:undimmed];
    [_alerts alertSleepWithSnapshot:undimmed];
    XCTAssertEqual(_recorder.titles.count, 4u);
}

@end
