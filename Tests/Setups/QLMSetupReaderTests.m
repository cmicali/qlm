#import <XCTest/XCTest.h>

#import "QLMSetupInternal.h"
#import "QLMSetupReader.h"
#import "QLMTestSupport.h"

// Source: Fixtures/Main.sam, a GLM 5.2.1 setup file with six devices and
// four groups, redacted by tools/redact-setup.py. Every value asserted here
// is read from that file.
@interface QLMSetupReaderTests : XCTestCase
@end

@implementation QLMSetupReaderTests

- (NSData *)fixture {
    NSData *data = [NSData dataWithContentsOfFile:QLMFixturePath(@"Main.sam")];
    XCTAssertNotNil(data);
    return data;
}

- (void)testHeader {
    QLMSetup *setup = QLMReadFixtureSetup();
    XCTAssertEqualObjects(setup.magic, @"GLM5_v2");
    XCTAssertTrue([setup.glmVersion hasPrefix:@"5.2.1"]);
    XCTAssertEqualObjects(setup.layoutStyle, @"Stereo with sub");
    XCTAssertEqual(setup.volume, -52.5);
    XCTAssertFalse(setup.volumeMute);
    XCTAssertFalse(setup.volumeDim);
    XCTAssertEqual(setup.volumeMaxLimit, 0);
    XCTAssertEqual(setup.startupLevel, -56.5);
    XCTAssertTrue(setup.startupLevelEnabled);
    XCTAssertTrue(setup.automaticPowerUp);
    XCTAssertFalse(setup.automaticShutDown);
    XCTAssertEqual(setup.issDelay, 30);
    XCTAssertEqual(setup.inputMode, 2);
    XCTAssertEqual(setup.activeGroup, 3);
    XCTAssertEqualObjects(setup.adapter.model, @"GLM Adapter");
    XCTAssertEqual(setup.adapter.type, 0);
    XCTAssertEqualObjects(setup.adapter.microVersion, @"1.4.0.6113");
}

- (void)testDevices {
    QLMSetup *setup = QLMReadFixtureSetup();
    XCTAssertEqual(setup.devices.count, 6u);
    NSArray<NSString *> *models = @[@"8351B", @"8351B", @"8330A", @"8330A", @"7370A", @"7350A"];
    NSArray<NSNumber *> *types = @[@3, @3, @2, @2, @1, @1];
    for (NSUInteger i = 0; i < 6; i++) {
        XCTAssertEqualObjects(setup.devices[i].model, models[i]);
        XCTAssertEqual(setup.devices[i].type, types[i].integerValue);
        XCTAssertEqualObjects(setup.devices[i].serial, ([NSString stringWithFormat:@"%ld", 1000002L + (long)i]));
    }
    QLMSetupDevice *left = setup.devices[0];
    XCTAssertEqualObjects(left.name, @"Left");
    XCTAssertEqualObjects(left.hardwareVersion, @"0.0.1152");
    XCTAssertEqualObjects(left.dspVersion, @"6470");
    XCTAssertEqualObjects(left.microVersion, @"1.24.07.6470");
    XCTAssertTrue(left.dbmFilter);
    XCTAssertEqualObjects(setup.devices[2].name, @"Rear Left 8330A");
    XCTAssertFalse(setup.devices[2].dbmFilter);
    XCTAssertEqualObjects([setup deviceWithSerial:@"1000006"].model, @"7370A");
    XCTAssertNil([setup deviceWithSerial:@"9"]);
}

- (void)testGroups {
    QLMSetup *setup = QLMReadFixtureSetup();
    XCTAssertEqual(setup.groups.count, 4u);
    NSArray<NSString *> *names = @[@"Main 4x2", @"Main 2x2", @"Main 2x1", @"Group_4"];
    for (NSUInteger i = 0; i < 4; i++) {
        XCTAssertEqualObjects(setup.groups[i].name, names[i]);
        XCTAssertEqual(setup.groups[i].nodes.count, 6u);
    }
    QLMSetupGroup *main = setup.groups[0];
    XCTAssertEqualObjects(main.calibrated, @"Calibrated 29 Oct 2025");
    XCTAssertEqual(main.groupSensitivity, 0);
    XCTAssertEqual(main.crossover, 85);
    XCTAssertEqual(main.crossoverGlobalMode, 1);
    // The fields a three-way's 43 and 4B may carry instead of its own: the
    // same in every group of every setup in the repository.
    for (QLMSetupGroup *group in setup.groups) {
        XCTAssertEqualObjects(group.groupDelayCompensation, @2, @"%@", group.name);
        XCTAssertEqualObjects(group.bassExtensionMode, @0, @"%@", group.name);
        XCTAssertEqualObjects(group.bassExtensionCrossoverMin, @150, @"%@", group.name);
        XCTAssertEqualObjects(group.bassExtensionCrossoverMax, @250, @"%@", group.name);
    }
    XCTAssertEqualObjects(main.volumePreset1, @(-40));
    XCTAssertEqualObjects(main.volumePreset2, @(-50));
    XCTAssertFalse(main.subwooferBypass);
    // The group shelves are designed at 96 kHz, host side.
    XCTAssertEqual(main.lowShelf.type, QLMSetupBandLowShelf);
    XCTAssertEqual(main.lowShelf.frequency, 100);
    XCTAssertEqual(main.lowShelf.gain, 0);
    XCTAssertEqual(main.lowShelf.sampleRate, 96000);
    XCTAssertEqual(main.highShelf.frequency, 1000);

    // Node classes come in the file's order, not the device list's.
    NSArray<NSNumber *> *classes = @[@(QLMSetupNodeClassTwoWay), @(QLMSetupNodeClassThreeWay), @(QLMSetupNodeClassTwoWay),
                                     @(QLMSetupNodeClassSubwoofer), @(QLMSetupNodeClassThreeWay), @(QLMSetupNodeClassSubwoofer)];
    for (NSUInteger i = 0; i < 6; i++) {
        XCTAssertEqual(main.nodes[i].nodeClass, classes[i].integerValue, @"node %lu", (unsigned long)i);
    }

    // In "Main 2x2" the two 8330A are off. Elsewhere every node is on.
    QLMSetupGroup *twoByTwo = setup.groups[1];
    XCTAssertFalse(twoByTwo.nodes[0].on);
    XCTAssertTrue(twoByTwo.nodes[1].on);
    XCTAssertFalse(twoByTwo.nodes[2].on);
    XCTAssertTrue(twoByTwo.nodes[3].on);
    for (QLMSetupNode *node in main.nodes) {
        XCTAssertTrue(node.on);
    }

    // The device list's order, the order of GLM's DSP pass
    // (captures/group-switch-main-4x2-main-2x1, 13.020 to 13.344 s).
    NSArray<NSString *> *deviceOrder = @[@"1000002", @"1000003", @"1000004", @"1000005", @"1000006", @"1000007"];
    for (QLMSetupGroup *group in setup.groups) {
        XCTAssertEqualObjects([group.nodesInDeviceOrder valueForKey:@"serial"], deviceOrder, @"%@", group.name);
    }
    QLMSetupGroup *made = [[QLMSetupGroup alloc] init];
    made.nodes = @[main.nodes[4], main.nodes[1]];
    XCTAssertEqualObjects(made.nodesInDeviceOrder, made.nodes);
}

- (void)testTwoWayNode {
    QLMSetupNode *node = QLMReadFixtureSetup().groups[0].nodes[0];
    XCTAssertEqualObjects(node.className, @"TwowayGen2");
    XCTAssertEqualObjects(node.serial, @"1000005");
    XCTAssertEqual(node.levelSensitivity, -0.2);
    XCTAssertEqualWithAccuracy(node.calibrationLevel, -0.200001, 1e-9);
    XCTAssertEqual(node.optionalGain, 0);
    XCTAssertEqual(node.timeOfFlightCompensation, 6);
    XCTAssertEqual(node.input, 2);
    XCTAssertEqual(node.aesChannel, 2);
    XCTAssertEqual(node.crossoverFrequency, 85);
    XCTAssertNil(node.phaseDegrees);
    XCTAssertNil(node.lfeCrossoverFrequency);

    // Two low shelves, two high shelves, sixteen peaks, all at 48 kHz.
    XCTAssertEqual(node.bands.count, 20u);
    NSUInteger shelves = 0, peaks = 0;
    for (QLMSetupBand *band in node.bands) {
        XCTAssertEqual(band.sampleRate, 48000);
        if (band.type == QLMSetupBandPeak) {
            peaks++;
        } else {
            shelves++;
            XCTAssertEqual(band.q, 0);
        }
    }
    XCTAssertEqual(shelves, 4u);
    XCTAssertEqual(peaks, 16u);
    QLMSetupBand *highShelf2 = node.bands[3];
    XCTAssertEqual(highShelf2.type, QLMSetupBandHighShelf);
    XCTAssertEqual(highShelf2.index, 2);
    XCTAssertEqual(highShelf2.frequency, 500.67);
    XCTAssertEqual(highShelf2.gain, -0.27);
    QLMSetupBand *peak1 = node.bands[4];
    XCTAssertEqual(peak1.type, QLMSetupBandPeak);
    XCTAssertEqual(peak1.index, 1);
    XCTAssertEqual(peak1.frequency, 250.31);
    XCTAssertEqual(peak1.gain, 3);
    XCTAssertEqual(peak1.q, 0.7);
}

// An 8351B. The file states 96 kHz for its bands, which the spec leaves
// unresolved on the wire.
- (void)testThreeWayNode {
    QLMSetupNode *node = QLMReadFixtureSetup().groups[0].nodes[1];
    XCTAssertEqual(node.nodeClass, QLMSetupNodeClassThreeWay);
    XCTAssertEqualObjects(node.serial, @"1000002");
    XCTAssertEqual(node.levelSensitivity, -0.17);
    XCTAssertEqual(node.timeOfFlightCompensation, 1.23);
    XCTAssertEqual(node.input, 1);
    XCTAssertEqualObjects(node.groupDelayCompensation, @2);
    XCTAssertEqualObjects(node.bassExtensionCrossover, @1);
    XCTAssertEqual(node.bands.count, 20u);
    for (QLMSetupBand *band in node.bands) {
        XCTAssertEqual(band.sampleRate, 96000);
    }
}

// At node level only the 8351B has GroupDelayCompensation and
// BassExtensionXO(Hz). Each group has its own GroupDelayCompensation, which
// the reader passes over.
- (void)testOnlyTheThreeWaysHaveTheirOwnFields {
    for (QLMSetupGroup *group in QLMReadFixtureSetup().groups) {
        for (QLMSetupNode *node in group.nodes) {
            BOOL threeWay = node.nodeClass == QLMSetupNodeClassThreeWay;
            XCTAssertEqual(node.groupDelayCompensation != nil, threeWay, @"%@ %@", group.name, node.serial);
            XCTAssertEqual(node.bassExtensionCrossover != nil, threeWay, @"%@ %@", group.name, node.serial);
        }
    }
}

- (void)testSubwooferNode {
    QLMSetupNode *node = QLMReadFixtureSetup().groups[0].nodes[3];
    XCTAssertEqual(node.nodeClass, QLMSetupNodeClassSubwoofer);
    XCTAssertEqualObjects(node.serial, @"1000006");
    XCTAssertEqual(node.levelSensitivity, -1.3);
    XCTAssertEqual(node.input, 3);
    XCTAssertEqual(node.aesChannel, 3);
    XCTAssertEqual(node.crossoverFrequency, 85);
    XCTAssertEqualObjects(node.phaseDegrees, @150);
    XCTAssertEqualObjects(node.lfePlus10, @0);
    XCTAssertEqualObjects(node.lfeChannel, @0);
    XCTAssertEqualObjects(node.lfeCrossoverFrequency, @120);
    XCTAssertEqualObjects(node.lfeLevel, @0);
    XCTAssertEqualObjects(node.subwooferGroupID, @0);
    // Twenty peaks at 12 kHz, no shelves.
    XCTAssertEqual(node.bands.count, 20u);
    for (QLMSetupBand *band in node.bands) {
        XCTAssertEqual(band.type, QLMSetupBandPeak);
        XCTAssertEqual(band.sampleRate, 12000);
    }
    XCTAssertEqual([QLMReadFixtureSetup().groups[0] nodeWithSerial:@"1000006"].nodeClass, QLMSetupNodeClassSubwoofer);
}

// Source: captures/startup-idle, the F0 02 leases from 8.432 s to 8.481 s.
// Each lease's three-byte hardware ID, read big-endian in decimal, is the
// Serial of the node of the same model in the user's setup file. No serial
// from 19 01 ends in a node's Serial.
- (void)testANodesSerialIsItsMonitorsHardwareID {
    const uint8_t rearRight[] = {0x0F, 0x42, 0x45};  // the fixture's 1000005
    QLMSetupNode *node = [QLMReadFixtureSetup().groups[0] nodeWithSerial:@"1000005"];
    XCTAssertEqualObjects(node.hardwareID, QLMBytes(rearRight, sizeof rearRight));

    NSMutableString *text = [[NSMutableString alloc] initWithData:[self fixture] encoding:NSUTF8StringEncoding];
    NSRange serial = [text rangeOfString:@"Serial:1000005\r\nGroup_ON:1\r\n"];
    [text replaceCharactersInRange:serial withString:@"Serial:16777216\r\nGroup_ON:1\r\n"];
    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNotNil(setup, @"%@", error);
    XCTAssertNil([setup.groups[0] nodeWithSerial:@"16777216"].hardwareID);  // more than three bytes
}

// The same source: a device's Serial is its monitor's hardware ID too, so a
// monitor on the bus finds its device, and its name, by hardware ID.
- (void)testADevicesSerialIsItsMonitorsHardwareID {
    const uint8_t rearRight[] = {0x0F, 0x42, 0x45};  // the fixture's 1000005
    QLMSetup *setup = QLMReadFixtureSetup();
    QLMSetupDevice *device = [setup deviceWithHardwareID:QLMBytes(rearRight, sizeof rearRight)];
    XCTAssertEqualObjects(device.serial, @"1000005");
    XCTAssertEqualObjects(device.hardwareID, QLMBytes(rearRight, sizeof rearRight));
    XCTAssertEqual(device, [setup deviceWithSerial:@"1000005"]);
    const uint8_t unknown[] = {0x11, 0x22, 0x33};
    XCTAssertNil([setup deviceWithHardwareID:QLMBytes(unknown, sizeof unknown)]);
    for (QLMSetupDevice *each in setup.devices) {
        XCTAssertNotNil(each.hardwareID, @"%@", each.serial);
    }
}

- (void)testEveryKeyInTheFixtureIsKnown {
    XCTAssertEqualObjects(QLMReadFixtureSetup().unknownKeys, @[]);
}

- (void)testUnknownKeysAreReportedNotDropped {
    NSMutableString *text = [[NSMutableString alloc] initWithData:[self fixture] encoding:NSUTF8StringEncoding];
    NSRange header = [text rangeOfString:@"Volume: -52.5\r\n"];
    XCTAssertNotEqual(header.location, NSNotFound);
    [text insertString:@"NewHeaderKey: 7\r\n" atIndex:header.location];
    NSRange node = [text rangeOfString:@"Serial:1000005\r\nGroup_ON:1\r\n"];
    XCTAssertNotEqual(node.location, NSNotFound);
    [text insertString:@"NewNodeKey:1\r\n" atIndex:node.location + node.length];

    NSError *error = nil;
    QLMSetup *setup = [QLMSetupReader readData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNotNil(setup, @"%@", error);
    NSArray *expected = @[@"header: NewHeaderKey", @"group Main 4x2 node 1000005: NewNodeKey"];
    XCTAssertEqualObjects(setup.unknownKeys, expected);
    XCTAssertEqual(setup.volume, -52.5);
}

- (void)testRejectsWhatItCannotRead {
    NSError *error = nil;
    NSData *garbage = [@"hello\r\nworld\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertNil([QLMSetupReader readData:garbage error:&error]);
    XCTAssertEqualObjects(error.domain, QLMSetupErrorDomain);
    XCTAssertEqual(error.code, QLMSetupErrorStructure);

    NSMutableString *text = [[NSMutableString alloc] initWithData:[self fixture] encoding:NSUTF8StringEncoding];
    NSRange magic = [text rangeOfString:@"Magic: GLM5_v2"];
    [text replaceCharactersInRange:magic withString:@"Magic: GLM6_v1"];
    XCTAssertNil([QLMSetupReader readData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertEqual(error.code, QLMSetupErrorMagic);

    text = [[NSMutableString alloc] initWithData:[self fixture] encoding:NSUTF8StringEncoding];
    NSRange volume = [text rangeOfString:@"Volume: -52.5"];
    [text replaceCharactersInRange:volume withString:@"Volume: loud"];
    XCTAssertNil([QLMSetupReader readData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertEqual(error.code, QLMSetupErrorValue);
    XCTAssertNotNil(error.userInfo[QLMSetupErrorLineKey]);

    NSData *whole = [self fixture];
    NSData *truncated = [whole subdataWithRange:NSMakeRange(0, whole.length / 2)];
    XCTAssertNil([QLMSetupReader readData:truncated error:&error]);
    XCTAssertEqual(error.code, QLMSetupErrorStructure);

    text = [[NSMutableString alloc] initWithData:[self fixture] encoding:NSUTF8StringEncoding];
    NSRange band = [text rangeOfString:@"Notch:1\r\nFrequency:250.31"];
    [text replaceCharactersInRange:band withString:@"Frequency:250.31"];
    XCTAssertNil([QLMSetupReader readData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertEqual(error.code, QLMSetupErrorStructure);

    text = [[NSMutableString alloc] initWithData:[self fixture] encoding:NSUTF8StringEncoding];
    NSRange nodes = [text rangeOfString:@"Group_Nodes:6"];
    [text replaceCharactersInRange:nodes withString:@"Group_Nodes:-1"];
    XCTAssertNil([QLMSetupReader readData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertEqual(error.code, QLMSetupErrorStructure);
    XCTAssertNotNil(error.userInfo[QLMSetupErrorLineKey]);
}

@end
