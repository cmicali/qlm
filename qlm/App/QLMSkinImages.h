#import <Cocoa/Cocoa.h>

#import "QLMSkin.h"

NS_ASSUME_NONNULL_BEGIN

// Every image a skin's drawing reads or makes, kept for the skin's life:
// its decoded files, and the images drawn from them and from its styles.
// The decoded files are read and written only on the skin's own serial
// queue. Everything else is on the main queue.
@interface QLMSkinImages : NSObject

// The skin's one set, made on its first use. On the main queue.
+ (instancetype)imagesOfSkin:(QLMSkin *)skin;
- (instancetype)init NS_UNAVAILABLE;

// png/<name>.png at scale 1, or its @2x at 2. NULL when the file won't
// load. A miss waits on the skin's queue, behind any decode already asked
// for, so nothing decodes twice.
- (nullable CGImageRef)decodedImage:(NSString *)name scale:(NSInteger)scale CF_RETURNS_NOT_RETAINED;
// Decodes every image the skin names, at `scale`, largest first, on the
// skin's queue.
- (void)warmAtScale:(NSInteger)scale;

// The value kept for `key`, made the first time it's asked for.
- (nullable id)objectForKey:(NSString *)key make:(id _Nullable (^)(void))make;
// The same, but a family keeps only its last few keys, for what a live
// resize makes a size a frame.
- (nullable id)objectForKey:(NSString *)key inFamily:(NSString *)family make:(id _Nullable (^)(void))make;

@end

NS_ASSUME_NONNULL_END
