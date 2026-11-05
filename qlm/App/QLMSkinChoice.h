#import <Foundation/Foundation.h>

#import "QLMPreferences.h"
#import "QLMSkin.h"
#import "QLMSkinLibrary.h"

NS_ASSUME_NONNULL_BEGIN

// The skin that shows: the saved name's, or the default in place of a
// refused one. It loads each choice once, so the window, the OSD, and
// Settings show the same skin, and decodes its images off the main queue
// as it loads it. On the main queue.
@interface QLMSkinChoice : NSObject

// Loads the saved name's skin.
- (instancetype)initWithPreferences:(QLMPreferences *)preferences library:(QLMSkinLibrary *)library NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) QLMSkin *skin;
// Why the saved name did not load, while the default shows in its place.
@property (nonatomic, readonly, copy, nullable) NSString *refusal;

// Loads the named skin and keeps it in the preferences. It loads the skin
// that shows again too, so a fixed skin.json takes. Returns the library's
// refusal, and then keeps nothing.
- (nullable NSString *)chooseSkinNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
