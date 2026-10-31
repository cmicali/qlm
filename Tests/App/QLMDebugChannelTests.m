#import <XCTest/XCTest.h>

#include <fcntl.h>
#include <unistd.h>

#import "DebugCommandDispatch.h"
#import "QLMApplySequence.h"
#import "QLMDebugChannel.h"
#import "QLMFakeBus.h"
#import "QLMPreferences.h"
#import "QLMSystem.h"
#import "QLMTestSupport.h"
#include "QLMCommands.h"
#include "QLMFrame.h"

// The app's debug verbs, over the fake bus on the virtual clock. A stand-in
// for the app delegate drives a real System and real preferences, kept in a
// suite of this test's own. So no verb reaches the app's settings or the
// real adapter. Sources: AGENTS.md's Safety rules, and the popover's and
// Settings' own actions, which each verb calls.
@interface QLMDebugChannelTests : XCTestCase
@end

// The app's side, as QLMAppDelegate gives it. It never makes a HID adapter.
@interface QLMTestDebugApp : NSObject <QLMDebugApp>
@property (nonatomic) QLMPreferences *debugPreferences;
@property (nonatomic, nullable) QLMSystem *debugSystem;
@property (nonatomic) NSPopover *debugPopover;
@property (nonatomic, copy, nullable) NSString *debugQuitGLMTitle;
@property (nonatomic) BOOL debugQuitAsksFirst;
// The app's own actions the verbs called, in order.
@property (nonatomic) NSMutableArray<NSString *> *actions;
@end

@implementation QLMTestDebugApp

- (instancetype)init {
    self = [super init];
    if (self) {
        _debugPopover = [[NSPopover alloc] init];
        _actions = [NSMutableArray array];
    }
    return self;
}

- (QLMSnapshot *)debugSnapshot {
    return self.debugSystem.snapshot;
}

- (void)debugShowPopover {
    [self.actions addObject:@"show popover"];
}

- (void)debugShowMonitors {
    [self.actions addObject:@"show monitors"];
}

- (void)debugShowSettings {
    [self.actions addObject:@"show settings"];
}

- (void)debugReadSetup {
    [self.actions addObject:@"read setup"];
}

// As the app delegate's settingsDidChangeVolumeRange: does.
- (void)debugVolumeRangeDidChange {
    [self.actions addObject:@"volume range"];
    [self.debugSystem setCeilingDecibels:self.debugPreferences.ceilingDecibels];
}

- (void)debugAdapterDidChange {
    [self.actions addObject:self.debugPreferences.usesAdapter ? @"adapter on" : @"adapter off"];
}

- (BOOL)debugQuitGLM {
    if (![self.debugQuitGLMTitle isEqualToString:@"Quit GLM"]) {
        return NO;
    }
    self.debugQuitGLMTitle = @"Asked GLM to Quit";
    [self.actions addObject:@"quit GLM"];
    return YES;
}

- (void)debugQuitAnswering:(BOOL)quitAnyway {
    [self.actions addObject:quitAnyway ? @"quit anyway" : @"quit, cancel"];
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
    preferences.fakeBus.volumeDecibels = -45;

    _time = [[QLMVirtualClock alloc] init];
    _bus = [QLMFakeBus demoBusWithSubwoofer:NO];
    _app = [[QLMTestDebugApp alloc] init];
    _app.debugPreferences = preferences;
    _app.debugSystem = [self systemOn:_bus];
    // As the app starts it: its own level, kept across launches.
    [_app.debugSystem start];
    [_app.debugSystem setVolumeDecibels:preferences.fakeBus.volumeDecibels];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.monitors.count == 2 && snapshot.allIdentified && snapshot.anyOn && snapshot.idle;
    }];
}

- (void)tearDown {
    [self stopSystem];
    [_defaults removePersistentDomainForName:_suiteName];
    [super tearDown];
}

- (QLMSystem *)systemOn:(QLMFakeBus *)bus {
    QLMSystemSettings *settings = [[QLMSystemSettings alloc] init];
    settings.clock = _time;
    settings.cycleInterval = 0.02;
    settings.adapterPollInterval = 0;
    settings.ceilingDecibels = _app.debugPreferences.ceilingDecibels;
    return [[QLMSystem alloc] initWithAdapter:bus settings:settings];
}

- (void)stopSystem {
    __block BOOL stopped = NO;
    [_app.debugSystem stopWithCompletion:^{
        stopped = YES;
    }];
    XCTAssertTrue([_time runUntil:^BOOL {
        return stopped;
    } within:60]);
}

- (void)waitUntil:(BOOL (^)(QLMSnapshot *snapshot))condition {
    QLMSystem *system = _app.debugSystem;
    XCTAssertTrue([_time runUntil:^BOOL {
        return condition(system.snapshot);
    } within:60], @"the condition never held");
}

- (void)turnRunLoopUntil:(BOOL (^)(void))condition {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTAssertTrue(condition());
}

- (NSString *)replyTo:(NSArray<NSString *> *)args {
    return QLMDebugRun(args, NSUUID.UUID.UUIDString, _app);
}

- (NSDictionary *)run:(NSArray<NSString *> *)args {
    NSString *reply = [self replyTo:args];
    id json = [NSJSONSerialization JSONObjectWithData:[reply dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]], @"%@", reply);
    return json;
}

- (NSDictionary *)runOK:(NSArray<NSString *> *)args {
    NSDictionary *reply = [self run:args];
    XCTAssertNil(reply[@"error"], @"%@", args);
    XCTAssertEqualObjects(reply[@"ok"], @YES, @"%@", args);
    return reply;
}

- (NSString *)errorOf:(NSArray<NSString *> *)args {
    NSString *error = [self run:args][@"error"];
    XCTAssertNotNil(error, @"%@", args);
    return error ?: @"";
}

- (QLMMonitorState *)monitorWithSerial:(NSString *)serial {
    for (QLMMonitorState *monitor in _app.debugSystem.snapshot.monitors) {
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
        QLMMessage message = QLMApplyMessage(record);
        XCTAssertTrue(QLMFrameAllows(message.payload, message.length), @"%@", record);
        if (message.address == QLMAddressBroadcast && message.length == 4 && message.payload[0] == 0x1F) {
            XCTAssertLessThanOrEqual(QLMVolumeWordOf(message), ceilingWord, @"%@", record);
            volumes += 1;
        }
    }
    XCTAssertGreaterThan(volumes, 0u);
}

// Nothing but the cycle's own frames went out since `mark`: its polls and
// probes, and the level already set.
- (void)assertNothingSentSince:(NSUInteger)mark {
    [_time advanceBy:1];
    QLMMessage standing = QLMCommandVolume(-45, -30);
    NSData *level = QLMAdapterRecord(&standing);
    NSArray<NSData *> *sent = _bus.sentMessages;
    for (NSUInteger i = mark; i < sent.count; i++) {
        NSData *record = sent[i];
        QLMMessage message = QLMApplyMessage(record);
        XCTAssertTrue(!QLMIsControl(message) || [record isEqualToData:level], @"%@", record);
    }
}

#pragma mark - The channel

// TRAP: a test process on the app's channel would answer, or send, a
// script's commands while a Debug build drives the real monitors. The
// channel is the main bundle's identifier, which here is the test runner's.
- (void)testTheChannelIsNeverTheApps {
    NSString *channel = NSBundle.mainBundle.bundleIdentifier;
    XCTAssertGreaterThan(channel.length, 0u);
    XCTAssertFalse([channel hasPrefix:@"com.commonwealthrecordings.qlm"], @"%@", channel);
}

- (void)testNoVerbIsInTwoTables {
    XCTAssertEqualObjects(VibeDebugDuplicateVerbs(QLMDebugTables()), @[]);
}

- (void)testAnUnknownVerbListsEveryCommand {
    NSString *error = [self errorOf:@[@"louder"]];
    XCTAssertTrue([error hasPrefix:@"unknown command 'louder'"], @"%@", error);
    for (NSArray<NSDictionary *> *table in QLMDebugTables()) {
        for (NSDictionary *spec in table) {
            XCTAssertTrue([error containsString:spec[@"usage"]], @"%@", spec[@"usage"]);
        }
    }
}

- (void)testNoAppYetIsRefused {
    NSString *reply = QLMDebugRun(@[@"dump_state"], @"id", nil);
    XCTAssertTrue([reply containsString:@"the app isn't running"], @"%@", reply);
}

// For a run's notes.md: the Mac's local time, to the millisecond, taken
// before the verb ran. An error carries it too.
- (void)testEachOwnReplyCarriesTheTimeItRan {
    NSISO8601DateFormatter *parser = [[NSISO8601DateFormatter alloc] init];
    parser.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSRegularExpression *shape = [NSRegularExpression regularExpressionWithPattern:@"^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\\.\\d{3}(Z|[+-]\\d\\d:\\d\\d)$"
                                                                           options:0
                                                                             error:NULL];
    NSString *(^zoneOf)(NSString *) = ^NSString *(NSString *text) {
        NSTextCheckingResult *match = [shape firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        return match != nil ? [text substringWithRange:[match rangeAtIndex:1]] : nil;
    };
    parser.timeZone = NSTimeZone.localTimeZone;
    NSString *offset = zoneOf([parser stringFromDate:NSDate.date]);
    for (NSArray<NSString *> *args in @[@[@"dump_state"], @[@"dim", @"on"], @[@"dim", @"sideways"], @[@"volume", @"-20"]]) {
        NSDate *before = NSDate.date;
        NSString *at = [self run:args][@"at"];
        NSDate *after = NSDate.date;
        XCTAssertNotNil(zoneOf(at), @"%@", at);
        NSDate *ran = [parser dateFromString:at];
        XCTAssertGreaterThanOrEqual(ran.timeIntervalSinceReferenceDate, before.timeIntervalSinceReferenceDate - 0.001, @"%@", at);
        XCTAssertLessThanOrEqual(ran.timeIntervalSinceReferenceDate, after.timeIntervalSinceReferenceDate + 0.001, @"%@", at);
        // The local zone's offset, not UTC's. TRAP: CI runs in UTC, so there
        // the zone is Z, not an offset.
        XCTAssertEqualObjects(zoneOf(at), offset, @"%@", at);
    }
}

- (void)testABadArgumentGetsTheUsageAndSendsNothing {
    NSUInteger mark = _bus.sentMessages.count;
    NSDictionary<NSString *, NSArray<NSArray<NSString *> *> *> *cases = @{
        @"dump_state": @[@[@"dump_state", @"now"]],
        @"show_monitors": @[@[@"show_monitors", @"all"]],
        @"read_setup": @[@[@"read_setup", @"Main.sam"]],
        @"popover <show|close>": @[@[@"popover"], @[@"popover", @"open"], @[@"popover", @"show", @"now"]],
        @"volume <dB>": @[@[@"volume"], @[@"volume", @"loud"], @[@"volume", @"nan"], @[@"volume", @"inf"], @[@"volume", @"-40", @"-41"]],
        @"ceiling <dB>": @[@[@"ceiling"], @[@"ceiling", @"-35dB"], @[@"ceiling", @"-inf"]],
        @"adapter <on|off>": @[@[@"adapter"], @[@"adapter", @"yes"]],
        @"adapter_off_answering <cancel|anyway>": @[@[@"adapter_off_answering"], @[@"adapter_off_answering", @"yes"]],
        @"mute <serial> <on|off>": @[@[@"mute", @"8330apm21001234"], @[@"mute", @"8330apm21001234", @"loud"], @[@"mute", @"on"]],
        @"mute_all <on|off>": @[@[@"mute_all"], @[@"mute_all", @"1"]],
        @"dim <on|off>": @[@[@"dim", @"sideways"], @[@"dim", @"on", @"off"]],
        @"standby": @[@[@"standby", @"now"]],
        @"wake": @[@[@"wake", @"up"]],
        @"quit_glm": @[@[@"quit_glm", @"now"]],
        @"quit_answering <cancel|anyway>": @[@[@"quit_answering"], @[@"quit_answering", @"yes"]],
    };
    for (NSString *usage in cases) {
        for (NSArray<NSString *> *args in cases[usage]) {
            XCTAssertEqualObjects([self errorOf:args], ([@"usage: " stringByAppendingString:usage]), @"%@", args);
        }
    }
    XCTAssertEqualObjects(_app.actions, @[]);
    XCTAssertEqual(_app.debugPreferences.ceilingDecibels, -30);
    QLMSnapshot *snapshot = _app.debugSystem.snapshot;
    XCTAssertEqualObjects(snapshot.volumeDecibels, @(-45));
    XCTAssertFalse(snapshot.dimmed || snapshot.mutingAll || snapshot.mutedHardwareIDs.count > 0);
    [self assertNothingSentSince:mark];
}

// The client runs in its own process. Here it runs on a background queue
// while main drains, under the test runner's channel.
- (void)testAClientReachesTheVerbsThroughTheWire {
    QLMDebugInstallChannel(_app);
    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSData.data writeToFile:outPath atomically:NO];
    fflush(stdout);
    int saved = dup(STDOUT_FILENO);
    int fd = open(outPath.fileSystemRepresentation, O_WRONLY | O_TRUNC);
    dup2(fd, STDOUT_FILENO);
    close(fd);
    __block int status = -1;
    dispatch_group_t client = dispatch_group_create();
    dispatch_group_async(client, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const char *argv[] = {"qlm", "--debug-cmd", "mute_all", "on"};
        status = QLMDebugClientMain(4, argv);
    });
    [self turnRunLoopUntil:^BOOL {
        return dispatch_group_wait(client, DISPATCH_TIME_NOW) == 0;
    }];
    fflush(stdout);
    dup2(saved, STDOUT_FILENO);
    close(saved);
    NSData *output = [NSData dataWithContentsOfFile:outPath];
    [NSFileManager.defaultManager removeItemAtPath:outPath error:NULL];

    XCTAssertEqual(status, 0);
    NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:output options:0 error:NULL];
    XCTAssertEqualObjects(reply[@"allMuted"], @YES);
    XCTAssertNotNil(reply[@"at"]);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allMuted && snapshot.idle;
    }];
    [self assertEveryFrameSafeUnder:-30];
}

#pragma mark - The state

- (void)testDumpStateReadsTheApp {
    NSDictionary *state = [self runOK:@[@"dump_state"]];
    XCTAssertEqualObjects(state[@"popoverShown"], @NO);
    XCTAssertEqualObjects(state[@"usesAdapter"], @NO);
    XCTAssertEqualObjects(state[@"sliderRange"], (@{@"lowestDecibels": @(-60), @"ceilingDecibels": @(-30)}));
    XCTAssertEqualObjects(state[@"quitGLMButton"], NSNull.null);
    XCTAssertEqualObjects(state[@"quitAsksFirst"], @NO);

    NSDictionary *snapshot = state[@"snapshot"];
    XCTAssertEqualObjects(snapshot[@"running"], @YES);
    XCTAssertEqualObjects(snapshot[@"busProblem"], @"none");
    XCTAssertEqualObjects(snapshot[@"volumeDecibels"], @(-45));
    XCTAssertEqualObjects(snapshot[@"ceilingDecibels"], @(-30));
    XCTAssertEqualObjects(snapshot[@"allMuted"], @NO);
    XCTAssertEqualObjects(snapshot[@"anyOn"], @YES);
    XCTAssertEqual([snapshot[@"monitors"] count], 2u);
    XCTAssertEqualObjects(snapshot[@"monitors"][0][@"serialNumber"], @"8330apm21001234");
    NSDictionary *handBack = snapshot[@"handBack"];
    XCTAssertEqualObjects(handBack[@"kind"], @"knobLevel");
    XCTAssertEqualObjects(handBack[@"volumeDecibels"], @(-45));
    XCTAssertNotEqualObjects(handBack[@"line"], NSNull.null);
    // The fake knob rests at its bottom stop, -1004 tenths: one decimal, not
    // a binary fraction.
    NSString *reply = [self replyTo:@[@"dump_state"]];
    XCTAssertTrue([reply containsString:@"\"knobDecibels\" : -100.4,"], @"%@", reply);
}

- (void)testDumpStateShowsTheBannersButton {
    _app.debugQuitGLMTitle = @"Quit GLM";
    XCTAssertEqualObjects([self runOK:@[@"dump_state"]][@"quitGLMButton"], @"Quit GLM");
}

- (void)testTheWindowVerbsCallTheApp {
    [self runOK:@[@"popover", @"show"]];
    [self runOK:@[@"show_monitors"]];
    [self runOK:@[@"show_settings"]];
    [self runOK:@[@"read_setup"]];
    XCTAssertEqualObjects(_app.actions, (@[@"show popover", @"show monitors", @"show settings", @"read setup"]));
}

#pragma mark - The controls

- (void)testVolumeGoesToSystemOnTheSlidersSteps {
    XCTAssertEqualObjects(([self runOK:@[@"volume", @"-40.3"]][@"volumeDecibels"]), @(-40.5));
    QLMMessage expected = QLMCommandVolume(-40.5, -30);
    NSData *record = QLMAdapterRecord(&expected);
    QLMFakeBus *bus = _bus;
    XCTAssertTrue([_time runUntil:^BOOL {
        return [bus.sentMessages containsObject:record];
    } within:1]);
    XCTAssertEqualObjects(_app.debugSystem.snapshot.volumeDecibels, @(-40.5));
    // The slider's top is the ceiling.
    XCTAssertEqualObjects(([self runOK:@[@"volume", @"-30.2"]][@"volumeDecibels"]), @(-30));
    [self assertEveryFrameSafeUnder:-30];
}

// The slider stops at the ceiling and at the range's bottom. A script that
// asks for more is told, not quietly moved.
- (void)testVolumeOutsideTheSlidersRangeIsRefused {
    NSUInteger mark = _bus.sentMessages.count;
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"-20"]]), @"-20.0 dB is outside the slider's range, -60.0 to -30.0 dB");
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"-29.8"]]), @"-29.8 dB is outside the slider's range, -60.0 to -30.0 dB");
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"0"]]), @"0.0 dB is outside the slider's range, -60.0 to -30.0 dB");
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"-61"]]), @"-61.0 dB is outside the slider's range, -60.0 to -30.0 dB");
    XCTAssertEqualObjects(_app.debugSystem.snapshot.volumeDecibels, @(-45));
    [self assertNothingSentSince:mark];
    [self assertEveryFrameSafeUnder:-30];
}

- (void)testCeilingGoesThroughSettings {
    // The preferences keep it on a step, at or below the value.
    XCTAssertEqualObjects(([self runOK:@[@"ceiling", @"-48.2"]][@"ceilingDecibels"]), @(-48.5));
    XCTAssertEqual([_defaults doubleForKey:@"QLMCeilingDecibels"], -48.5);
    XCTAssertEqualObjects(_app.actions, @[@"volume range"]);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.ceilingDecibels == -48.5 && snapshot.idle;
    }];
    // The level already set goes out again under the new ceiling.
    QLMMessage capped = QLMCommandVolume(-45, -48.5);
    XCTAssertTrue([_bus.sentMessages containsObject:QLMAdapterRecord(&capped)]);
    [self assertEveryFrameSafeUnder:-30];
    // The slider's range follows it.
    XCTAssertEqualObjects(([self errorOf:@[@"volume", @"-45"]]), @"-45.0 dB is outside the slider's range, -60.0 to -48.5 dB");
    // The preferences bound it: at most 0 dB, and 10 dB above the bottom.
    XCTAssertEqualObjects(([self runOK:@[@"ceiling", @"-100"]][@"ceilingDecibels"]), @(-50));
    XCTAssertEqualObjects(([self runOK:@[@"ceiling", @"6"]][@"ceilingDecibels"]), @0);
}

// The stand-in never makes a HID adapter: on the app, a change starts a
// new System on the setting.
- (void)testAdapterGoesThroughSettings {
    NSDictionary *reply = [self runOK:@[@"adapter", @"on"]];
    XCTAssertEqualObjects(reply[@"usesAdapter"], @YES);
    XCTAssertEqualObjects(reply[@"restarted"], @YES);
    XCTAssertTrue([_defaults boolForKey:@"QLMUsesAdapter"]);
    XCTAssertEqualObjects(([self runOK:@[@"adapter", @"on"]][@"restarted"]), @NO);
    XCTAssertEqualObjects(([self runOK:@[@"adapter", @"OFF"]][@"restarted"]), @YES);
    XCTAssertEqualObjects(_app.actions, (@[@"adapter on", @"adapter off"]));
    XCTAssertFalse([_defaults boolForKey:@"QLMUsesAdapter"]);
}

// Turning the adapter off stops the real monitors, as a quit does. Where
// the louder alert would show, only an explicit anyway turns it off.
- (void)testTurningTheAdapterOffAnswersTheLouderAlert {
    [self runOK:@[@"adapter", @"on"]];
    _app.debugQuitAsksFirst = YES;
    XCTAssertEqualObjects(([self errorOf:@[@"adapter", @"off"]]),
                          @"turning the adapter off may make the monitors louder. Answer with adapter_off_answering");
    NSDictionary *reply = [self runOK:@[@"adapter_off_answering", @"cancel"]];
    XCTAssertEqualObjects(reply[@"asksFirst"], @YES);
    XCTAssertEqualObjects(reply[@"restarted"], @NO);
    XCTAssertTrue([_defaults boolForKey:@"QLMUsesAdapter"]);
    XCTAssertEqualObjects(([self runOK:@[@"adapter_off_answering", @"anyway"]][@"restarted"]), @YES);
    XCTAssertFalse([_defaults boolForKey:@"QLMUsesAdapter"]);
    XCTAssertEqualObjects(_app.actions, (@[@"adapter on", @"adapter off"]));
}

- (void)testMuteNamesAMonitorBySerial {
    NSDictionary *reply = [self runOK:@[@"mute", @"8330APM21005678", @"on"]];
    XCTAssertEqualObjects(reply[@"serialNumber"], @"8330apm21005678");
    XCTAssertEqualObjects(reply[@"muted"], @YES);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return [self monitorWithSerial:@"8330apm21005678"].muted && snapshot.idle;
    }];
    XCTAssertFalse([self monitorWithSerial:@"8330apm21001234"].muted);
    XCTAssertFalse(_app.debugSystem.snapshot.mutingAll);

    [self runOK:@[@"mute", @"8330apm21005678", @"off"]];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return ![self monitorWithSerial:@"8330apm21005678"].muted && snapshot.idle;
    }];

    NSUInteger mark = _bus.sentMessages.count;
    XCTAssertEqualObjects(([self errorOf:@[@"mute", @"8351bpm00000000", @"on"]]),
                          @"System tracks no monitor 8351bpm00000000. It tracks: 8330apm21001234, 8330apm21005678");
    [self assertNothingSentSince:mark];
    [self assertEveryFrameSafeUnder:-30];
}

- (void)testMuteAllAndDim {
    XCTAssertEqualObjects(([self runOK:@[@"mute_all", @"on"]][@"allMuted"]), @YES);
    XCTAssertEqualObjects(([self runOK:@[@"dim", @"on"]][@"dimmed"]), @YES);
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.allMuted && snapshot.mutingAll && snapshot.dimmed && snapshot.idle;
    }];
    NSDictionary *snapshot = [self runOK:@[@"dump_state"]][@"snapshot"];
    XCTAssertEqualObjects(snapshot[@"handBack"][@"volumeDecibels"], @(-65));
    XCTAssertEqualObjects(snapshot[@"allMuted"], @YES);

    [self runOK:@[@"mute_all", @"off"]];
    [self runOK:@[@"dim", @"off"]];
    [self waitUntil:^BOOL(QLMSnapshot *state) {
        return !state.allMuted && !state.dimmed && state.idle;
    }];
    [self assertEveryFrameSafeUnder:-30];
}

// The power button reads Standby while a monitor is on, and Wake while none
// is. Each verb takes only its own reading.
- (void)testStandbyAndWakeFollowThePowerButton {
    XCTAssertEqualObjects([self errorOf:@[@"wake"]], @"a monitor is on, so the power button reads Standby");
    [self runOK:@[@"standby"]];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return !snapshot.anyOn && snapshot.monitors.count == 2 && snapshot.idle;
    }];
    XCTAssertEqualObjects([self errorOf:@[@"standby"]], @"no monitor is on, so the power button reads Wake");

    [self runOK:@[@"wake"]];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.anyOn && snapshot.idle;
    }];
    [self assertEveryFrameSafeUnder:-30];
}

// As the popover's controls go dim while System is stopped.
- (void)testControlsRefuseWhileSystemIsStopped {
    [self stopSystem];
    NSUInteger sent = _bus.sentMessages.count;
    for (NSArray<NSString *> *args in @[@[@"volume", @"-40"], @[@"mute_all", @"on"], @[@"dim", @"on"], @[@"standby"], @[@"wake"]]) {
        XCTAssertEqualObjects([self errorOf:args], @"System is not running", @"%@", args);
    }
    XCTAssertEqualObjects(([self errorOf:@[@"mute", @"8330apm21001234", @"on"]]), @"System tracks no monitor 8330apm21001234. It tracks: none");
    [_time advanceBy:1];
    XCTAssertEqual(_bus.sentMessages.count, sent);
    XCTAssertFalse(_app.debugSystem.snapshot.dimmed);
}

// Mute and the power button need a monitor. The slider and Dim do not.
- (void)testControlsThatNeedAMonitorRefuseWithNone {
    [self stopSystem];
    _bus = [[QLMFakeBus alloc] initWithMonitors:@[]];
    _app.debugSystem = [self systemOn:_bus];
    [_app.debugSystem start];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.running && snapshot.idle;
    }];
    NSUInteger mark = _bus.sentMessages.count;
    for (NSArray<NSString *> *args in @[@[@"mute_all", @"on"], @[@"standby"], @[@"wake"]]) {
        XCTAssertEqualObjects([self errorOf:args], @"System tracks no monitor yet", @"%@", args);
    }
    // No level is set yet, so nothing at all.
    [self assertNothingSentSince:mark];
    [self runOK:@[@"dim", @"on"]];
    [self runOK:@[@"volume", @"-50"]];
    [self waitUntil:^BOOL(QLMSnapshot *snapshot) {
        return snapshot.dimmed && snapshot.volumeDecibels != nil && snapshot.idle;
    }];
    [self assertEveryFrameSafeUnder:-30];
}

#pragma mark - GLM and quitting

- (void)testQuitGLMIsTheBannersButton {
    XCTAssertEqualObjects([self errorOf:@[@"quit_glm"]], @"the banner offers no Quit GLM");
    _app.debugQuitGLMTitle = @"Quit GLM";
    XCTAssertEqualObjects([self runOK:@[@"quit_glm"]][@"askedGLMToQuit"], @YES);
    XCTAssertEqualObjects([self errorOf:@[@"quit_glm"]], @"GLM was not asked to quit. The button reads Asked GLM to Quit");
    XCTAssertEqualObjects(_app.actions, @[@"quit GLM"]);
}

- (void)testQuitAnswersTheLouderHandBackAlert {
    _app.debugQuitAsksFirst = YES;
    NSDictionary *reply = [self runOK:@[@"quit_answering", @"cancel"]];
    XCTAssertEqualObjects(reply[@"quitting"], @NO);
    XCTAssertEqualObjects(reply[@"asksFirst"], @YES);
    XCTAssertEqualObjects(reply[@"handBack"][@"kind"], @"knobLevel");
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    XCTAssertEqualObjects(_app.actions, @[]);

    // The quit itself waits for the reply to go out.
    reply = [self runOK:@[@"quit_answering", @"anyway"]];
    XCTAssertEqualObjects(reply[@"quitting"], @YES);
    XCTAssertEqualObjects(_app.actions, @[]);
    [self turnRunLoopUntil:^BOOL {
        return self->_app.actions.count == 1;
    }];
    XCTAssertEqualObjects(_app.actions, @[@"quit anyway"]);
}

- (void)testQuitWithNoAlertQuitsWhateverTheAnswer {
    NSString *reply = [self replyTo:@[@"quit_answering", @"cancel"]];
    // JSON booleans, not numbers.
    XCTAssertTrue([reply containsString:@"\"quitting\" : true"], @"%@", reply);
    XCTAssertTrue([reply containsString:@"\"asksFirst\" : false"], @"%@", reply);
    XCTAssertEqualObjects(_app.actions, @[]);
    [self turnRunLoopUntil:^BOOL {
        return self->_app.actions.count == 1;
    }];
    XCTAssertEqualObjects(_app.actions, @[@"quit, cancel"]);
}

@end
