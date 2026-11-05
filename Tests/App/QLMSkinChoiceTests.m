#import <XCTest/XCTest.h>

#import "QLMPreferences.h"
#import "QLMSkinChoice.h"
#import "QLMTestSupport.h"

// The one owner of the skin that shows. Source: docs/ui.md's "The format":
// a refused skin falls back to modern, with the reason in Settings, and a
// fixed one takes when it is picked again.
@interface QLMSkinChoiceTests : XCTestCase
@end

@implementation QLMSkinChoiceTests {
    NSString *_suiteName;
    NSUserDefaults *_defaults;
    QLMPreferences *_preferences;
    NSURL *_work;
    NSURL *_mine;  // a user's skin
    QLMSkinLibrary *_library;
}

- (void)setUp {
    [super setUp];
    _suiteName = [@"QLMSkinChoiceTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
    _preferences = [[QLMPreferences alloc] initWithDefaults:_defaults];
    _work = [NSURL fileURLWithPath:QLMScratchPath() isDirectory:YES];
    NSURL *user = [_work URLByAppendingPathComponent:@"user"];
    _mine = [user URLByAppendingPathComponent:@"mine"];
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:NULL]);
    _library = [[QLMSkinLibrary alloc] initWithBuiltIn:QLMBuiltInSkinsURL() user:user];
}

- (void)tearDown {
    [NSFileManager.defaultManager removeItemAtURL:_work error:NULL];
    [_defaults removePersistentDomainForName:_suiteName];
    [super tearDown];
}

- (void)makeMineFrom:(NSURL *)skin {
    [NSFileManager.defaultManager removeItemAtURL:_mine error:NULL];
    XCTAssertTrue([NSFileManager.defaultManager copyItemAtURL:skin toURL:_mine error:NULL]);
}

- (void)breakMine {
    XCTAssertTrue([[@"[]" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[_mine URLByAppendingPathComponent:@"skin.json"]
                                                                   atomically:NO]);
}

- (QLMSkinChoice *)launch {
    return [[QLMSkinChoice alloc] initWithPreferences:_preferences library:_library];
}

- (void)testAPickShowsAndIsKept {
    QLMSkinChoice *choice = [self launch];
    XCTAssertEqualObjects(choice.skin.name, @"modern");
    XCTAssertNil(choice.refusal);
    XCTAssertNil([choice chooseSkinNamed:@"retro"]);
    XCTAssertEqualObjects(choice.skin.name, @"retro");
    XCTAssertEqualObjects(_preferences.skinName, @"retro");
}

// A refused pick keeps nothing: the skin that shows, its refusal, and the
// preference stay.
- (void)testARefusedPickKeepsNothing {
    QLMSkinChoice *choice = [self launch];
    QLMSkin *shown = choice.skin;
    [self makeMineFrom:QLMFixtureSkinURL()];
    [self breakMine];
    NSString *refusal = [choice chooseSkinNamed:@"mine"];
    XCTAssertTrue([refusal hasPrefix:@"The skin mine is refused. skin.json is not an object"], @"%@", refusal);
    XCTAssertEqual(choice.skin, shown);
    XCTAssertNil(choice.refusal);
    XCTAssertEqualObjects(_preferences.skinName, @"modern");
}

// The saved name refused at launch shows modern, and says why.
- (void)testARefusedSavedSkinFallsBackAtLaunch {
    [self makeMineFrom:QLMFixtureSkinURL()];
    [self breakMine];
    _preferences.skinName = @"mine";
    QLMSkinChoice *choice = [self launch];
    XCTAssertEqualObjects(choice.skin.name, @"modern");
    XCTAssertTrue([choice.refusal hasPrefix:@"The skin mine is refused"], @"%@", choice.refusal);
    XCTAssertEqualObjects(_preferences.skinName, @"mine");
}

// A user fixes the refused skin and picks it again, by the same name. The
// pick reads the file again, and so does a pick of the skin that shows.
- (void)testTheSameNameLoadsAgain {
    [self makeMineFrom:QLMFixtureSkinURL()];
    [self breakMine];
    _preferences.skinName = @"mine";
    QLMSkinChoice *choice = [self launch];
    [self makeMineFrom:QLMFixtureSkinURL()];
    XCTAssertNil([choice chooseSkinNamed:@"mine"]);
    XCTAssertEqualObjects(choice.skin.name, @"mine");
    XCTAssertNil(choice.refusal);
    XCTAssertEqual(choice.skin.osd.frame.size.width, 300);

    [self makeMineFrom:QLMModernSkinURL()];
    QLMSkin *before = choice.skin;
    XCTAssertNil([choice chooseSkinNamed:@"mine"]);
    XCTAssertNotEqual(choice.skin, before);
    XCTAssertEqualObjects(choice.skin.name, @"mine");
    XCTAssertEqual(choice.skin.osd.frame.size.width, 480);
}

@end
