#import <Foundation/Foundation.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// The skin every refusal falls back to. It ships in the app.
extern NSString *const QLMSkinDefaultName;

// Finds the skins: the app's, then the user's. Foundation only.
@interface QLMSkinLibrary : NSObject

// The app's Resources/Skins, then ~/Library/Application Support/qlm/Skins.
+ (instancetype)standardLibrary;

// Each directory holds one directory per skin. The first is the app's.
- (instancetype)initWithBuiltIn:(NSURL *)builtIn user:(nullable NSURL *)user NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The skins' names: the app's, sorted, then the user's, sorted. A user's
// skin with an app skin's name is left out, since the app's wins.
- (NSArray<NSString *> *)skinNames;
- (BOOL)isBuiltIn:(NSString *)name;

// The named skin. A skin that is missing or refused gives the default
// skin, with the reason in refusal. Nil only when the default is refused
// too, which a test rules out.
- (nullable QLMSkin *)loadSkinNamed:(NSString *)name refusal:(NSString *_Nullable *_Nullable)refusal;

// The reason the last load fell back, or nil. For Settings.
@property (nonatomic, readonly, copy, nullable) NSString *lastRefusal;

@end

NS_ASSUME_NONNULL_END
