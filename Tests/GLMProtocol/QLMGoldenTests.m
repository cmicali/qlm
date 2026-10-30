#import "QLMTestSupport.h"

#include "QLMCRC.h"
#include "QLMCommands.h"
#include "QLMReplies.h"
#include "QLMReport.h"

// Sources: every capture in captures/, GLM 5 talking to the adapter through
// the Pi proxy, with each scenario's notes.md. Every report in them passes
// through the report layer and the frame codec here, and every builder is
// checked against a frame GLM sent.
@interface QLMGoldenTests : XCTestCase
@end

@implementation QLMGoldenTests

- (NSArray<QLMCapture *> *)captures {
    NSMutableArray<QLMCapture *> *captures = [NSMutableArray array];
    for (NSString *scenario in QLMCaptureScenarios()) {
        NSError *error = nil;
        QLMCapture *capture = QLMReadCapture(scenario, &error);
        XCTAssertNotNil(capture, @"%@: %@", scenario, error.localizedDescription);
        if (capture != nil) {
            [captures addObject:capture];
        }
    }
    return captures;
}

static NSString *QLMDescribeExchange(QLMCaptureExchange *exchange) {
    QLMMessage message = exchange.message;
    NSMutableString *text = [NSMutableString stringWithFormat:@"%.6f %02X", exchange.time, message.address];
    for (size_t i = 0; i < message.length; i++) {
        [text appendFormat:@" %02X", message.payload[i]];
    }
    return text;
}

// The scenarios captures/README.md lists, each one read with every report in
// it: each output report unpacked and decoded, and each input report starting
// with 3F and read into a reply.
- (void)testEveryScenarioReads {
    NSArray<NSString *> *scenarios = QLMCaptureScenarios();
    for (NSString *required in @[@"startup-idle", @"startup-idle-mic", @"volume-sweep", @"knob-sweep", @"mute-dim",
                                 @"standby-wake", @"quit-glm", @"unplug", @"sleep-wake-darkwake"]) {
        XCTAssertTrue([scenarios containsObject:required], @"%@", required);
    }
    NSPredicate *switches = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'group-switch-'"];
    XCTAssertEqual([scenarios filteredArrayUsingPredicate:switches].count, 6u);

    NSUInteger exchanges = 0;
    for (QLMCapture *capture in [self captures]) {
        XCTAssertGreaterThan(capture.exchanges.count, 0u);
        exchanges += capture.exchanges.count;
    }
    XCTAssertGreaterThan(exchanges, 60000u);
}

// Every output report GLM sent unpacks and decodes. qlm packs every one the
// allowlist accepts to the same 64 bytes, and refuses the rest. The refused
// set is exactly the opcodes GLM sends that qlm never does.
- (void)testEveryOutputReportRepacksByteForByte {
    NSMutableSet<NSString *> *refused = [NSMutableSet set];
    NSUInteger repacked = 0;
    NSUInteger mismatches = 0;
    for (QLMCapture *capture in [self captures]) {
        for (QLMCaptureExchange *exchange in capture.exchanges) {
            QLMMessage message = exchange.message;
            uint8_t report[QLMReportLength];
            QLMReportStatus status = QLMReportPackOutput(&message, report);
            if (!QLMFrameAllows(message.payload, message.length)) {
                XCTAssertEqual(status, QLMReportErrorForbidden);
                NSString *target = message.address == QLMAddressReply ? @"adapter " : (message.address == QLMAddressBroadcast ? @"FF " : @"");
                [refused addObject:[NSString stringWithFormat:@"%@%02X", target, message.payload[0]]];
                continue;
            }
            if (status != QLMReportOK || ![QLMBytes(report, sizeof report) isEqualToData:exchange.outputReport]) {
                if (mismatches++ < 5) {
                    XCTFail(@"%@ does not repack", QLMDescribeExchange(exchange));
                }
                continue;
            }
            repacked += 1;
        }
    }
    XCTAssertEqual(mismatches, 0u);
    XCTAssertGreaterThan(repacked, 50000u);
    NSSet<NSString *> *glmOnly = [NSSet setWithArray:@[@"05", @"3C", @"3E", @"42", @"43", @"4B", @"adapter 22", @"adapter 51"]];
    XCTAssertEqualObjects(refused, glmOnly);
}

// The escaped form of a decoded message, as section 1 of hlm's spec gives it,
// for frames qlm never encodes: the replies, and GLM's refused frames.
static size_t QLMEscapeFrame(const QLMMessage *message, uint8_t *out) {
    uint8_t raw[1 + QLMPayloadMax + 2];
    raw[0] = message->address;
    memcpy(raw + 1, message->payload, message->length);
    uint16_t crc = QLMCRC16GSM(raw, 1 + message->length);
    raw[1 + message->length] = (uint8_t)(crc >> 8);
    raw[2 + message->length] = (uint8_t)crc;
    size_t count = 0;
    out[count++] = raw[0];
    for (size_t i = 1; i < 3 + message->length; i++) {
        if (raw[i] == QLMFrameFlag || raw[i] == QLMFrameEscape) {
            out[count++] = QLMFrameEscape;
            out[count++] = raw[i] ^ QLMFrameEscapeXor;
        } else {
            out[count++] = raw[i];
        }
    }
    out[count++] = QLMFrameFlag;
    return count;
}

// Each reply comes from 01 and re-escapes to the bytes the adapter sent.
// Some span two input reports; none spans more.
- (void)testEveryReplyReencodesByteForByte {
    NSUInteger replies = 0;
    NSUInteger spanning = 0;
    NSUInteger escaped = 0;
    for (QLMCapture *capture in [self captures]) {
        for (QLMCaptureExchange *exchange in capture.exchanges) {
            NSData *frame = exchange.replyFrame;
            if (frame == nil) {
                continue;
            }
            QLMMessage reply = exchange.reply;
            XCTAssertEqual(reply.address, QLMAddressReply);
            uint8_t again[QLMFrameMax];
            size_t length = QLMEscapeFrame(&reply, again);
            XCTAssertEqualObjects(QLMBytes(again, length), frame);
            XCTAssertLessThanOrEqual(frame.length, 2u * QLMReportFrameMax);
            spanning += frame.length > QLMReportFrameMax ? 1 : 0;
            escaped += length > reply.length + 4 ? 1 : 0;
            replies += 1;
        }
    }
    XCTAssertGreaterThan(replies, 50000u);
    XCTAssertGreaterThan(spanning, 0u);
    XCTAssertGreaterThan(escaped, 0u);
}

// The adapter answers every probe and unicast with one frame: the monitor's,
// or the no-answer frame. Broadcasts get none. Only a capture's last
// exchange may lack its reply, cut off when the capture stopped. Each reply
// reads with the parser for its request.
- (void)testEveryReplyAnswersItsRequest {
    NSUInteger noAnswers = 0;
    NSUInteger telemetry = 0;
    NSUInteger identities = 0;
    for (QLMCapture *capture in [self captures]) {
        QLMCaptureExchange *last = capture.exchanges.lastObject;
        for (QLMCaptureExchange *exchange in capture.exchanges) {
            QLMMessage message = exchange.message;
            QLMMessage reply = exchange.reply;
            uint8_t opcode = message.payload[0];
            // Built only when an assertion fails.
            NSString * (^what)(void) = ^{
                return QLMDescribeExchange(exchange);
            };
            if (!QLMReportExpectsReply(&message)) {
                XCTAssertNil(exchange.replyFrame, @"%@", what());
                continue;
            }
            if (exchange.replyFrame == nil) {
                XCTAssertEqual(exchange, last, @"%@", what());
                continue;
            }
            if (!exchange.answered) {
                XCTAssertTrue(QLMReplyIsNoAnswer(&reply), @"%@", what());
                noAnswers += 1;
                continue;
            }
            XCTAssertGreaterThan(reply.length, 0u, @"%@", what());
            XCTAssertEqual(reply.payload[0], 0x09, @"%@", what());

            char text[QLMPayloadMax];
            if (opcode == 0xFE) {
                XCTAssertTrue(QLMReplyHardwareID(&reply, NULL), @"%@", what());
            } else if (message.address == QLMAddressMulticast) {
                uint8_t session = 0;
                XCTAssertEqual(opcode, 0x02, @"%@", what());
                XCTAssertTrue(QLMReplySessionAck(&reply, &session), @"%@", what());
                XCTAssertEqual(session, message.payload[4], @"%@", what());
            } else if (message.address == QLMAddressReply) {
                // The adapter itself: its status poll, identity strings, and mute.
                if (opcode == 0x08 || opcode == 0x2B) {
                    XCTAssertTrue(reply.length >= 2 || QLMReplyIsAck(&reply), @"%@", what());
                } else {
                    XCTAssertTrue(QLMReplyText(&reply, text, sizeof text), @"%@", what());
                }
            } else if (opcode == 0x08) {
                QLMTelemetry values;
                QLMTelemetryStatus status = QLMReplyTelemetry(&reply, &values);
                XCTAssertNotEqual(status, QLMTelemetryErrorUnknownTag, @"%@: tag %02X", what(), values.unknownTag);
                XCTAssertNotEqual(status, QLMTelemetryErrorTruncated, @"%@", what());
                telemetry += status == QLMTelemetryOK ? 1 : 0;
            } else if (opcode == 0x19) {
                XCTAssertTrue(QLMReplyText(&reply, text, sizeof text), @"%@", what());
                XCTAssertTrue(strlen(text) == 14 || strlen(text) == 15, @"%@", what());
            } else if (opcode == 0x39) {
                char model[32];
                char firmware[32];
                XCTAssertTrue(QLMReplyText(&reply, text, sizeof text), @"%@", what());
                XCTAssertTrue(QLMSystemInfoParse(text, model, sizeof model, firmware, sizeof firmware), @"%@", what());
                XCTAssertNotEqual(firmware[0], '\0', @"%@", what());
                identities += 1;
            } else {
                XCTAssertTrue(QLMReplyIsAck(&reply), @"%@", what());
            }
        }
    }
    XCTAssertGreaterThan(noAnswers, 0u);
    XCTAssertGreaterThan(telemetry, 5000u);
    XCTAssertGreaterThan(identities, 0u);
}

// docs/adapter-status.md: every reply to 01 08 reads with the tag rule and
// no unknown tag. startup-idle opens with the knob at its bottom stop and no
// mic, startup-idle-mic has the mic in, knob-sweep reaches the top stop, and
// volume-sweep loses the knob at 25.44 s.
- (void)testEveryAdapterStatusReplyReads {
    NSUInteger replies = 0;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *shapes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *highest = [NSMutableDictionary dictionary];
    for (NSString *scenario in QLMCaptureScenarios()) {
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        shapes[scenario] = seen;
        int32_t top = INT32_MIN;
        for (QLMCaptureExchange *exchange in QLMReadCapture(scenario, NULL).exchanges) {
            QLMMessage message = exchange.message;
            if (message.address != QLMAddressAdapter || message.payload[0] != 0x08 || !exchange.answered) {
                continue;
            }
            QLMMessage reply = exchange.reply;
            QLMAdapterStatus status;
            XCTAssertEqual(QLMReplyAdapterStatus(&reply, &status), QLMAdapterStatusOK, @"%@", QLMDescribeExchange(exchange));
            XCTAssertEqual(status.unknownTag, 0, @"%@", QLMDescribeExchange(exchange));
            XCTAssertEqual(status.knob, status.hasKnobPosition, @"%@", QLMDescribeExchange(exchange));
            [seen addObject:[NSString stringWithFormat:@"%@%@", status.mic ? @"mic" : @"", status.knob ? @"knob" : @""]];
            if (status.knob && status.knobTenths > top) {
                top = status.knobTenths;
            }
            replies += 1;
        }
        highest[scenario] = @(top);
    }
    XCTAssertGreaterThan(replies, 28000u);
    XCTAssertEqualObjects(shapes[@"startup-idle"], [NSSet setWithObject:@"knob"]);
    XCTAssertEqualObjects(shapes[@"startup-idle-mic"], [NSSet setWithObject:@"micknob"]);
    XCTAssertEqualObjects(shapes[@"volume-sweep"], ([NSSet setWithObjects:@"knob", @"", nil]));
    XCTAssertEqualObjects(highest[@"knob-sweep"], @0);

    QLMMessage first = QLMReadCapture(@"startup-idle", NULL).exchanges.firstObject.reply;
    QLMAdapterStatus status;
    XCTAssertEqual(QLMReplyAdapterStatus(&first, &status), QLMAdapterStatusOK);
    XCTAssertEqual(status.knobTenths, -1004);

    for (QLMCaptureExchange *exchange in QLMReadCapture(@"volume-sweep", NULL).exchanges) {
        QLMMessage message = exchange.message;
        if (exchange.time > 25.45 && message.address == QLMAddressAdapter && message.payload[0] == 0x08 && exchange.answered) {
            QLMMessage reply = exchange.reply;
            QLMReplyAdapterStatus(&reply, &status);
            XCTAssertFalse(status.knob, @"%@", QLMDescribeExchange(exchange));
        }
    }
}

// The report link's syncs rest on this. Replies name no request, but in
// every capture a reply has the adapter status's exact shape only when it
// answers 01 08, and reads as system info only when it answers 39. Every
// answered 01 08 and 39 gets that shape.
- (void)testOnlyStatusPollsAndSystemInfoQueriesGetTheirShapes {
    NSUInteger statuses = 0;
    NSUInteger infos = 0;
    for (QLMCapture *capture in [self captures]) {
        for (QLMCaptureExchange *exchange in capture.exchanges) {
            if (!exchange.answered) {
                continue;
            }
            QLMMessage message = exchange.message;
            QLMMessage reply = exchange.reply;
            BOOL statusPoll = message.address == QLMAddressAdapter && message.payload[0] == 0x08;
            BOOL infoQuery = message.payload[0] == 0x39;
            XCTAssertEqual(QLMReplyIsAdapterStatus(&reply), statusPoll, @"%@", QLMDescribeExchange(exchange));
            XCTAssertEqual(QLMReplyIsSystemInfo(&reply), infoQuery, @"%@", QLMDescribeExchange(exchange));
            statuses += statusPoll ? 1 : 0;
            infos += infoQuery ? 1 : 0;
        }
    }
    XCTAssertGreaterThan(statuses, 28000u);
    XCTAssertGreaterThan(infos, 10u);
}

static NSData *QLMDataFromHex(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    for (NSString *pair in [hex componentsSeparatedByString:@" "]) {
        if (pair.length == 2) {
            uint8_t byte = (uint8_t)strtoul(pair.UTF8String, NULL, 16);
            [data appendBytes:&byte length:1];
        }
    }
    return data;
}

// The descriptors dumpcap read at the start of a capture: the device
// descriptor's vendor and product, and the HID report descriptor, which
// declares no report IDs, 64-byte input and output reports, and a 1-byte
// feature report.
- (void)testTheAdapterDescriptorsMatchTheReportLayer {
    const uint8_t descriptor[] = {
        0x06, QLMAdapterUsagePage & 0xFF, QLMAdapterUsagePage >> 8, // usage page
        0x09, 0x01, 0xA1, 0x01,                                     // usage 1, application collection
        0x09, 0x00, 0x15, 0x00, 0x26, 0xFF, 0x00,                   // bytes 0 to FF
        0x75, 0x08, 0x95, QLMReportLength, 0x81, 0x02,              // input
        0x09, 0x00, 0x75, 0x08, 0x95, QLMReportLength, 0x91, 0x02,  // output
        0x09, 0x00, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x02,             // feature
        0xC0,
    };
    NSUInteger devices = 0;
    NSUInteger reports = 0;
    for (QLMCapture *capture in [self captures]) {
        for (NSString *comment in capture.comments) {
            NSArray<NSString *> *parts = [comment componentsSeparatedByString:@" data "];
            if (parts.count != 2) {
                continue;
            }
            NSData *data = QLMDataFromHex(parts[1]);
            if ([parts[0] hasSuffix:@"control 80 06 00 01 00 00 12 00"]) {
                const uint8_t *bytes = data.bytes;
                XCTAssertEqual(data.length, 18u);
                XCTAssertEqual(bytes[8] | bytes[9] << 8, QLMAdapterVendorID);
                XCTAssertEqual(bytes[10] | bytes[11] << 8, QLMAdapterProductID);
                devices += 1;
            } else if ([parts[0] containsString:@"control 81 06 00 22"]) {
                XCTAssertEqualObjects(data, QLMBytes(descriptor, sizeof descriptor));
                reports += 1;
            }
        }
    }
    XCTAssertGreaterThan(devices, 0u);
    XCTAssertGreaterThan(reports, 0u);
}

- (void)assertScenario:(NSString *)scenario sent:(QLMMessage)message {
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&message, report), QLMReportOK);
    NSData *packed = QLMBytes(report, sizeof report);
    NSUInteger found = [QLMReadCapture(scenario, NULL).exchanges indexOfObjectPassingTest:^BOOL(QLMCaptureExchange *exchange, NSUInteger index, BOOL *stop) {
        return [exchange.outputReport isEqualToData:packed];
    }];
    XCTAssertNotEqual(found, NSNotFound, @"%@ never sent %@", scenario, packed);
}

// GLM's own frames, from the captures the notes describe: startup, the
// standby and wake, the volume at -20 dB on quit, both ends of the volume
// sweep, the mute and dim, and a group switch's duck and DSP frames.
- (void)testTheBuildersMatchGLMsFrames {
    [self assertScenario:@"startup-idle" sent:QLMCommandProbe()];
    [self assertScenario:@"startup-idle" sent:QLMCommandKeepAlive()];
    [self assertScenario:@"startup-idle" sent:QLMCommandPoll(0x02)];
    [self assertScenario:@"startup-idle" sent:QLMCommandPoll(QLMAddressReply)];
    [self assertScenario:@"startup-idle" sent:QLMCommandSerialNumber(0x02)];
    [self assertScenario:@"startup-idle" sent:QLMCommandSystemInfo(0x02)];
    [self assertScenario:@"startup-idle" sent:QLMCommandPower(QLMPowerStepWakeFirst)];
    [self assertScenario:@"startup-idle" sent:QLMCommandPower(QLMPowerStepWakeSecond)];
    [self assertScenario:@"startup-idle" sent:QLMCommandVolume(-56.5, 0)];
    [self assertScenario:@"startup-idle" sent:QLMCommandPrepare(0x02)];
    [self assertScenario:@"startup-idle" sent:QLMCommandDelay(0x02, 0)];
    [self assertScenario:@"startup-idle" sent:QLMCommandLevel(0x02, QLMLevelWordForDecibels(0))];
    [self assertScenario:@"startup-idle" sent:QLMCommandLevelUnknown(0x02)];

    QLMCaptureExchange *lease = nil;
    for (QLMCaptureExchange *exchange in QLMReadCapture(@"startup-idle", NULL).exchanges) {
        if (exchange.message.address == QLMAddressMulticast) {
            lease = exchange;
            break;
        }
    }
    XCTAssertNotNil(lease);
    QLMMessage leased = lease.message;
    QLMMessage assign = QLMCommandAssignSession(leased.payload + 1, QLMAddressSessionFirst);
    uint8_t report[QLMReportLength];
    XCTAssertEqual(QLMReportPackOutput(&assign, report), QLMReportOK);
    XCTAssertEqualObjects(QLMBytes(report, sizeof report), lease.outputReport);

    [self assertScenario:@"standby-wake" sent:QLMCommandPower(QLMPowerStepStandbyPrepare)];
    [self assertScenario:@"standby-wake" sent:QLMCommandPower(QLMPowerStepPowerOff)];

    [self assertScenario:@"quit-glm" sent:QLMCommandVolume(-20, 0)];
    [self assertScenario:@"volume-sweep" sent:QLMCommandVolume(0, 0)];
    [self assertScenario:@"volume-sweep" sent:QLMCommandVolume(-130, 0)];

    [self assertScenario:@"mute-dim" sent:QLMCommandDim(-56.5, 0)];
    [self assertScenario:@"mute-dim" sent:QLMCommandMute(0x0B, QLMMuteValueMuted)];
    [self assertScenario:@"mute-dim" sent:QLMCommandMute(0x03, QLMMuteValueUnmuted)];

    NSString *groupSwitch = @"group-switch-main-2x2-main-2x1";
    const uint8_t unity[20] = {0x00, 0x00, 0x80, 0x3F};
    [self assertScenario:groupSwitch sent:QLMCommandDuck()];
    [self assertScenario:groupSwitch sent:QLMCommandPEQ(0x03, 0x00, unity)];
    [self assertScenario:groupSwitch sent:QLMCommandDelay(0x05, 0x190)];
    [self assertScenario:groupSwitch sent:QLMCommandCrossover(0x03, 0x003C)];
    [self assertScenario:groupSwitch sent:QLMCommandInputSync(0x03)];
    [self assertScenario:groupSwitch sent:QLMCommandRouting(0x03, 0x00, 0x02, 0x00, 0x01)];
}

@end
