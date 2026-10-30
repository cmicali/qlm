#import <XCTest/XCTest.h>

#import "QLMDebugChannel.h"
#import "QLMFakeBus.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMFrame.h"

// The app's debug verbs, over the fake bus on a virtual clock. A stand-in
// for the app delegate drives a real System and real preferences, kept in a
// suite of this test's own, so no verb reaches the app's settings or the
// real adapter.
@interface QLMDebugChannelTests : XCTestCase
@end

// The app's side, as QLMAppDelegate gives it. It never makes a HID adapter.
@interface QLMTestDebugApp : NSObject <QLMDebugApp>
@property (nonatomic) QLMPreferences *preferences;
@property (nonatomic, nullable) QLMSystem *system;
@property (nonatomic, copy, nullable) NSString *quitGLMTitle;
@property (nonatomic) BOOL quitAsksFirst;
@property (nonatomic) NSMutableArray<NSNumber *> *adapterChanges;
@property (nonatomic) NSMutableArray<NSNumber *> *quitAnswers;
@end

@implementation QLMTestDebugApp

- (instancetype)init {
    self = [super init];
    if (self) {
        _adapterChanges = [NSMutableArray array];
        _quitAnswers = [NSMutableArray array];
    }
    return self;
}

- (QLMSnapshot *)shownSnapshot {
    return self.system.snapshot;
}

- (void)changeCeilingDecibels:(double)decibels {
    self.preferences.ceilingDecibels = decibels;
    [self.system setCeilingDecibels:self.preferences.ceilingDecibels];
}

- (void)changeUsesAdapter:(BOOL)usesAdapter {
    self.preferences.usesAdapter = usesAdapter;
    [self.adapterChanges addObject:@(usesAdapter)];
}

- (BOOL)quitGLM {
    if (![self.quitGLMTitle isEqualToString:@"Quit GLM"]) {
        return NO;
    }
    self.quitGLMTitle = @"Asked GLM to Quit";
    return YES;
}

- (void)quitAnswering:(BOOL)quitAnyway {
    [self.quitAnswers addObject:@(quitAnyway)];
}

@end

@implementation QLMDebugChannelTests {
    NSString *_suiteName;
    NSUserDefaults *_defaults;
    QLMVirtualClock *_time;
    QLMFakeBus *_bus;
    QLMTestDebugApp *_app;
}

- (void)setUp {
    [super setUp];
    _suiteName = [@"QLMDebugChannelTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
    QLMPreferences *preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
    preferences.ceilingDecibels = -30;
    preferences.volumeDecibels = -45;

    _time = [[QLMVirtualClock alloc] init];
    _bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = _time;
    settings.cycleInterval = 0.02;
    settings.adapterPollInterval = 0;
    settings.ceilingDecibels = preferences.ceilingDecibels;
    _app = [[QLMTestDebugApp alloc] init];
    _app.preferences = preferences;
    _app.system = [[QLMSystem alloc] initWithAdapter:_bus settings:settings];
    // As the app starts it: its own level, kept across launches.
    [_app.system start];
    [_app.system setVolumeDecibels:preferences.volumeDecibels];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.anyOn && snapshot.idle;
    }];
}

- (void)tearDown {
    QLMSystem *system = _app.system;
    __block BOOL stopped = NO;
    [system stopWithCompletion:^{
        stopped = YES;
    }];
    XCTAssertTrue([_time runUntil:^BOOL {
        return stopped;
    } within:60]);
    [_defaults removePersistentDomainForName:_suiteName];
    [super tearDown];
}

- (void)waitUntil:(BOOL (^)(QLMSnapshot *snapshot))condition {
    QLMSystem *system = _app.system;
    XCTAssertTrue([_time runUntil:^BOOL {
        return condition(system.snapshot);
    } within:60], @"the condition never held");
}

- (NSDictionary *)run:(NSArray<NSString *> *)args {
    NSString *reply = QLMDebugRun(args, NSUUID.UUID.UUIDString, _app);
    id json = [NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]], @"%@", reply);
    return json;
}

- (NSDictionary *)runOK:(NSArray<NSString *> *)args {
    NSDictionary *reply = [self run:args];
    XCTAssertNil(reply[@"error"], @"%@", args);
    return reply;
}

- (NSString *)errorOf:(NSArray<NSString *> *)args {
    NSString *error = [self run:args][@"error"];
    XCTAssertNotNil(error, @"%@", args);
    return error ?: @"";
}

- (QLMMonitorState *)monitorWithSerial:(NSString *)serial {
    for (QLMMonitorState *monitor in _app.system.snapshot.monitors) {
        if ([monitor.serialNumber isEqualToString:serial]) {
            return monitor;
        }
    }
    return nil;
}

// AGENTS.md's Safety rules: every frame on the allowlist, every volume frame
// at or under the ceiling.
- (void)assertEveryFrameSafeUnder:(double)ceilingDecibels {
    uint32_t ceilingWord = QLMVolumeWordForDecibels(ceilingDecibels);
    NSUInteger volumes = 0;
    for (NSData *record in _bus.sentMessages) {
        const uint8_t *bytes = record.bytes;
        XCTAssertTrue(QLMFrameAllows(bytes + 1, record.length - 1), @"%@", record);
        if (record.length == 5 && bytes[0] == QLMAddressBroadcast && bytes[1] == 0x1F) {
            uint32_t word = (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 8 | bytes[4];
            XCTAssertLessThanOrEqual(word, ceilingWord, @"%@", record);
            volumes += 1;
        }
    }
    XCTAssertGreaterThan(volumes, 0u);
}

#pragma mark - The channel

// TRAP: a test process on the app's channel would answer, or send, a
// script's commands while a Debug build drives the real monitors.
- (void)testTheChannelIsNeverTheApps {
    XCTAssertGreaterThan(QLMDebugChannelName().length, 0u);
    XCTAssertNotEqualObjects(QLMDebugChannelName(), @"com.commonwealthrecordings.qlm");
}

- (void)testAClientReachesTheChannelThroughTheWire {
    QLMInstallDebugChannel(_app);
    NSString *reply = QLMDebugSend(@[@"state"]);
    XCTAssertNotNil(reply);
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    XCTAssertEqual([state[@"monitors"] count], 2u);

    reply = QLMDebugSend(@[@"mute-all", @"on"]);
    XCTAssertTrue([reply containsString:@"\"allMuted\" : true"], @"%@", reply);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allMuted;
    }];
}

- (void)testAnUnknownVerbListsEveryCommand {
    NSString *error = [self errorOf:@[@"louder"]];
    XCTAssertTrue([error hasPrefix:@"unknown command 'louder'"], @"%@", error);
    for (NSDictionary *spec in QLMDebugCommands()) {
        XCTAssertTrue([error containsString:spec[@"usage"]], @"%@", spec[@"usage"]);
    }
    XCTAssertTrue([error containsString:@"help"]);
}

- (void)testNoAppYetIsRefused {
    NSString *reply = QLMDebugRun(@[@"state"], @"id", nil);
    XCTAssertTrue([reply containsString:@"has not finished launching"], @"%@", reply);
}

- (void)testEachReplyCarriesTheTimeItRan {
    NSDate *before = [NSDate dateWithTimeIntervalSinceNow:-0.001];
    NSISO8601DateFormatter *parser = [[NSISO8601DateFormatter alloc] init];
    parser.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    for (NSArray<NSString *> *args in @[@[@"state"], @[@"dim", @"on"], @[@"dim", @"sideways"]]) {
        NSString *at = [self run:args][@"at"];
        NSDate *ran = [parser dateFromString:at];
        XCTAssertNotNil(ran, @"%@", at);
        // A local time with milliseconds, for a capture's notes.
        XCTAssertTrue([at containsString:@"."], @"%@", at);
        XCTAssertGreaterThanOrEqual(ran.timeIntervalSinceReferenceDate, before.timeIntervalSinceReferenceDate);
        XCTAssertLessThan(ran.timeIntervalSinceNow, 1);
    }
}

- (void)testABadArgumentGetsTheUsage {
    XCTAssertEqualObjects(([self errorOf:@[@"dim", @"sideways"]]), @"usage: dim <on|off>");
    XCTAssertEqualObjects(([self errorOf:@[@"volume"]]), @"usage: volume <dB>");
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"loud"]]), @"usage: volume <dB>");
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"nan"]]), @"usage: volume <dB>");
    XCTAssertEqualObjects(([self errorOf:@[@"mute", @"8330apm21001234"]]), @"usage: mute <serial> <on|off>");
    XCTAssertEqualObjects(([self errorOf:@[@"quit"]]), @"usage: quit <cancel|anyway>");
}

#pragma mark - The snapshot

- (void)testStateReadsTheSnapshot {
    NSDictionary *state = [self runOK:@[@"state"]];
    XCTAssertEqualObjects(state[@"running"], @YES);
    XCTAssertEqualObjects(state[@"usesAdapter"], @NO);
    XCTAssertEqualObjects(state[@"busProblem"], @"none");
    XCTAssertEqualObjects(state[@"banner"], NSNull.null);
    XCTAssertEqualObjects(state[@"adapter"][@"device"], @"a fake bus of 2 monitors");
    // The fake knob rests at its bottom stop, -1004 tenths: one decimal, not
    // a binary fraction.
    XCTAssertEqualObjects(state[@"knob"][@"present"], @YES);
    NSString *reply = QLMDebugRun(@[@"state"], @"id", _app);
    XCTAssertTrue([reply containsString:@"\"decibels\" : -100.4,"], @"%@", reply);
    XCTAssertEqualObjects(state[@"level"][@"volume"], @(-45));
    XCTAssertEqualObjects(state[@"level"][@"sent"], @(-45));
    XCTAssertEqualObjects(state[@"level"][@"ceiling"], @(-30));
    XCTAssertEqualObjects(state[@"level"][@"lowest"], @(-60));
    XCTAssertEqualObjects(state[@"level"][@"dimmed"], @NO);
    XCTAssertEqualObjects(state[@"power"], (@{@"anyOn": @YES, @"button": @"Standby", @"enabled": @YES}));
    XCTAssertEqualObjects(state[@"handBack"][@"kind"], @"knob-level");
    XCTAssertEqualObjects(state[@"handBack"][@"quitAsksFirst"], @NO);

    NSArray<NSDictionary *> *monitors = state[@"monitors"];
    XCTAssertEqual(monitors.count, 2u);
    NSDictionary *left = monitors[0];
    XCTAssertEqualObjects(left[@"serial"], @"8330apm21001234");
    XCTAssertEqualObjects(left[@"model"], @"8330A");
    XCTAssertEqualObjects(left[@"firmware"], @"1.14.7");
    XCTAssertEqualObjects(left[@"hardwareID"], @"11 22 33");
    XCTAssertEqualObjects(left[@"status"], @"on");
    XCTAssertEqualObjects(left[@"muted"], @NO);
    XCTAssertEqualObjects(left[@"temperature"], @38);
}

- (void)testStateShowsTheBannerAndItsButton {
    _bus.busyReason = @"GLM holds the adapter";
    _app.quitGLMTitle = @"Quit GLM";
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.busProblem != QLMBusProblemNone;
    }];
    NSDictionary *state = [self runOK:@[@"state"]];
    XCTAssertNotEqualObjects(state[@"busProblem"], @"none");
    XCTAssertNotNil(state[@"banner"][@"title"]);
    XCTAssertNotNil(state[@"banner"][@"detail"]);
    XCTAssertEqualObjects(state[@"banner"][@"button"], @"Quit GLM");
}

#pragma mark - The controls

- (void)testVolumeGoesToSystemOnTheSlidersSteps {
    XCTAssertEqualObjects(([self runOK:@[@"volume", @"-40.3"]][@"volume"]), @(-40.5));
    // System coalesces volume, so the frame may wait out volumeInterval.
    QLMMessage expected = QLMCommandVolume(-40.5, -30);
    NSData *record = QLMAdapterRecord(&expected);
    QLMFakeBus *bus = _bus;
    XCTAssertTrue([_time runUntil:^BOOL {
        return [bus.sentMessages containsObject:record];
    } within:1]);
    XCTAssertEqualObjects(_app.system.snapshot.volumeDecibels, @(-40.5));
    [self assertEveryFrameSafeUnder:-30];
}

// The slider stops at the ceiling and at the range's bottom. A script that
// asks for more is told, not quietly moved.
- (void)testVolumeOutsideTheSlidersRangeIsRefused {
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"-20"]]), @"-20.0 dB is outside the slider's range, -60.0 to -30.0 dB");
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"-61"]]), @"-61.0 dB is outside the slider's range, -60.0 to -30.0 dB");
    [_time advanceBy:0.2];
    XCTAssertEqualObjects(_app.system.snapshot.volumeDecibels, @(-45));
    [self assertEveryFrameSafeUnder:-30];
}

- (void)testCeilingGoesThroughSettings {
    // The preferences keep it on a step, at or below what was asked.
    XCTAssertEqualObjects(([self runOK:@[@"ceiling", @"-48.2"]][@"ceiling"]), @(-48.5));
    XCTAssertEqual(_app.preferences.ceilingDecibels, -48.5);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.ceilingDecibels == -48.5 && snapshot.idle;
    }];
    // The level already set goes out again under the new ceiling.
    QLMMessage capped = QLMCommandVolume(-45, -48.5);
    XCTAssertTrue([_bus.sentMessages containsObject:QLMAdapterRecord(&capped)]);
    [self assertEveryFrameSafeUnder:-30];
    // The preferences bound it: never above 0 dB.
    XCTAssertEqualObjects(([self runOK:@[@"ceiling", @"6"]][@"ceiling"]), @0);
}

- (void)testAdapterGoesThroughSettings {
    NSDictionary *reply = [self runOK:@[@"adapter", @"on"]];
    XCTAssertEqualObjects(reply[@"usesAdapter"], @YES);
    XCTAssertEqualObjects(reply[@"restarted"], @YES);
    XCTAssertEqualObjects(([self runOK:@[@"adapter", @"on"]][@"restarted"]), @NO);
    XCTAssertEqualObjects(([self runOK:@[@"adapter", @"off"]][@"restarted"]), @YES);
    XCTAssertEqualObjects(_app.adapterChanges, (@[@YES, @NO]));
    XCTAssertFalse([_defaults boolForKey:@"QLMUsesAdapter"]);
}

- (void)testMuteNamesAMonitorBySerial {
    NSDictionary *reply = [self runOK:@[@"mute", @"8330APM21005678", @"on"]];
    XCTAssertEqualObjects(reply[@"serial"], @"8330apm21005678");
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return [self monitorWithSerial:@"8330apm21005678"].muted && snapshot.idle;
    }];
    XCTAssertFalse([self monitorWithSerial:@"8330apm21001234"].muted);
    XCTAssertFalse(_app.system.snapshot.mutingAll);

    [self runOK:@[@"mute", @"8330apm21005678", @"off"]];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return ![self monitorWithSerial:@"8330apm21005678"].muted;
    }];

    NSString *error = [self errorOf:@[@"mute", @"8351bpm00000000", @"on"]];
    XCTAssertEqualObjects(error, @"System tracks no monitor 8351bpm00000000. It tracks: 8330apm21001234, 8330apm21005678");
}

- (void)testMuteAllAndDim {
    XCTAssertEqualObjects(([self runOK:@[@"mute-all", @"on"]][@"allMuted"]), @YES);
    XCTAssertEqualObjects(([self runOK:@[@"dim", @"on"]][@"dimmed"]), @YES);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allMuted && snapshot.mutingAll && snapshot.dimmed && snapshot.idle;
    }];
    NSDictionary *level = [self runOK:@[@"state"]][@"level"];
    XCTAssertEqualObjects(level[@"sent"], @(-65));
    XCTAssertEqualObjects(level[@"allMuted"], @YES);

    [self runOK:@[@"mute-all", @"off"]];
    [self runOK:@[@"dim", @"off"]];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.allMuted && !snapshot.dimmed && snapshot.idle;
    }];
    [self assertEveryFrameSafeUnder:-30];
}

// The power button reads Standby while a monitor is on, and Wake while none
// is. Each verb takes only its own reading.
- (void)testStandbyAndWakeFollowThePowerButton {
    XCTAssertEqualObjects(([self errorOf:@[@"wake"]]), @"a monitor is on, so the power button reads Standby");
    XCTAssertEqualObjects(([self runOK:@[@"standby"]][@"power"]), @"standby");
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.anyOn && snapshot.monitors.count == 2 && snapshot.idle;
    }];
    XCTAssertEqualObjects(([self runOK:@[@"state"]][@"power"][@"button"]), @"Wake");
    XCTAssertEqualObjects(([self errorOf:@[@"standby"]]), @"no monitor is on, so the power button reads Wake");

    XCTAssertEqualObjects(([self runOK:@[@"wake"]][@"power"]), @"wake");
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.anyOn && snapshot.idle;
    }];
    [self assertEveryFrameSafeUnder:-30];
}

// As the popover's controls go dim while System is stopped.
- (void)testControlsRefuseWhileSystemIsStopped {
    __block BOOL stopped = NO;
    [_app.system stopWithCompletion:^{
        stopped = YES;
    }];
    XCTAssertTrue([_time runUntil:^BOOL {
        return stopped;
    } within:60]);
    NSUInteger sent = _bus.sentMessages.count;
    for (NSArray<NSString *> *args in @[@[@"volume", @"-40"], @[@"mute-all", @"on"], @[@"dim", @"on"], @[@"standby"], @[@"wake"]]) {
        XCTAssertEqualObjects(([self errorOf:args]), @"System is not running", @"%@", args);
    }
    [_time advanceBy:1];
    XCTAssertEqual(_bus.sentMessages.count, sent);
}

#pragma mark - GLM and quitting

- (void)testQuitGLMIsTheBannersButton {
    XCTAssertEqualObjects(([self errorOf:@[@"quit-glm"]]), @"the banner offers no Quit GLM");
    _app.quitGLMTitle = @"Quit GLM";
    XCTAssertEqualObjects(([self runOK:@[@"quit-glm"]][@"askedGLMToQuit"]), @YES);
    XCTAssertEqualObjects(([self errorOf:@[@"quit-glm"]]), @"GLM was not asked to quit. The button reads Asked GLM to Quit");
}

- (void)testQuitAnswersTheHandBackAlert {
    _app.quitAsksFirst = YES;
    NSDictionary *reply = [self runOK:@[@"quit", @"cancel"]];
    XCTAssertEqualObjects(reply[@"quitting"], @NO);
    XCTAssertEqualObjects(reply[@"asksFirst"], @YES);
    XCTAssertEqualObjects(reply[@"handBack"][@"kind"], @"knob-level");
    XCTAssertEqualObjects(_app.quitAnswers, @[@NO]);

    // The quit itself waits for the reply to go out.
    reply = [self runOK:@[@"quit", @"anyway"]];
    XCTAssertEqualObjects(reply[@"quitting"], @YES);
    XCTAssertEqualObjects(_app.quitAnswers, @[@NO]);
    [self turnRunLoopUntil:^BOOL {
        return self->_app.quitAnswers.count == 2;
    }];
    XCTAssertEqualObjects(_app.quitAnswers, (@[@NO, @YES]));
}

- (void)testQuitWithNoAlertQuitsWhateverTheAnswer {
    NSDictionary *reply = [self runOK:@[@"quit", @"cancel"]];
    XCTAssertEqualObjects(reply[@"quitting"], @YES);
    XCTAssertEqualObjects(reply[@"asksFirst"], @NO);
    [self turnRunLoopUntil:^BOOL {
        return self->_app.quitAnswers.count == 1;
    }];
    XCTAssertEqualObjects(_app.quitAnswers, @[@NO]);
}

- (void)turnRunLoopUntil:(BOOL (^)(void))condition {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertTrue(condition());
}

@end
