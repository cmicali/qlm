#import "QLMSkinImages.h"

#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

// What a family keeps: a group's three buttons, at their places on the
// pixels, and a resize's last frame.
static const NSUInteger QLMSkinFamilySize = 4;

static char QLMSkinImagesKey;

@implementation QLMSkinImages {
    __weak QLMSkin *_skin;
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, id> *_decoded;  // on _queue only
    NSMutableDictionary<NSString *, id> *_objects;
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_families;  // newest last
}

+ (instancetype)imagesOfSkin:(QLMSkin *)skin {
    QLMSkinImages *images = objc_getAssociatedObject(skin, &QLMSkinImagesKey);
    if (images == nil) {
        images = [[QLMSkinImages alloc] initWithSkin:skin];
        objc_setAssociatedObject(skin, &QLMSkinImagesKey, images, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return images;
}

- (instancetype)initWithSkin:(QLMSkin *)skin {
    self = [super init];
    if (self) {
        _skin = skin;
        dispatch_queue_attr_t attributes =
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _queue = dispatch_queue_create("com.commonwealthrecordings.qlm.skin-images", attributes);
        _decoded = [NSMutableDictionary dictionary];
        _objects = [NSMutableDictionary dictionary];
        _families = [NSMutableDictionary dictionary];
    }
    return self;
}

static NSString *QLMSkinDecodedKey(NSString *name, NSInteger scale) {
    return [NSString stringWithFormat:@"%@@%ldx", name, (long)scale];
}

// On _queue.
- (id)decodeOnQueue:(NSString *)name scale:(NSInteger)scale {
    NSString *key = QLMSkinDecodedKey(name, scale);
    id image = _decoded[key];
    if (image == nil) {
        QLMSkin *skin = _skin;
        CGImageSourceRef source =
            skin ? CGImageSourceCreateWithURL((__bridge CFURLRef)[skin imageURLForName:name scale:scale], NULL) : NULL;
        if (source != NULL) {
            NSDictionary *options = @{(id)kCGImageSourceShouldCacheImmediately: @YES};
            image = CFBridgingRelease(CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options));
            CFRelease(source);
        }
        image = image ?: NSNull.null;
        _decoded[key] = image;
    }
    return image;
}

- (CGImageRef)decodedImage:(NSString *)name scale:(NSInteger)scale {
    __block id image;
    dispatch_sync(_queue, ^{
        image = [self decodeOnQueue:name scale:scale];
    });
    return image == NSNull.null ? NULL : (__bridge CGImageRef)image;
}

- (void)warmAtScale:(NSInteger)scale {
    QLMSkin *skin = _skin;
    if (skin == nil) {
        return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *sizes = [NSMutableDictionary dictionary];
    for (NSString *name in skin.imageNames) {
        NSNumber *size = nil;
        [[skin imageURLForName:name scale:scale] getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        sizes[name] = size ?: @0;
    }
    NSArray<NSString *> *largestFirst = [sizes keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];
    // A block per file, so a miss waits behind those queued ahead of it,
    // not the whole list.
    for (NSString *name in largestFirst) {
        dispatch_async(_queue, ^{
            [self decodeOnQueue:name scale:scale];
        });
    }
}

- (id)objectForKey:(NSString *)key make:(id _Nullable (^)(void))make {
    id object = _objects[key];
    if (object == nil) {
        object = make() ?: NSNull.null;
        _objects[key] = object;
    }
    return object == NSNull.null ? nil : object;
}

- (id)objectForKey:(NSString *)key inFamily:(NSString *)family make:(id _Nullable (^)(void))make {
    NSString *full = [family stringByAppendingFormat:@"|%@", key];
    NSMutableArray<NSString *> *recent = _families[family];
    if (recent == nil) {
        recent = [NSMutableArray array];
        _families[family] = recent;
    }
    [recent removeObject:full];
    [recent addObject:full];
    while (recent.count > QLMSkinFamilySize) {
        [_objects removeObjectForKey:recent.firstObject];
        [recent removeObjectAtIndex:0];
    }
    return [self objectForKey:full make:make];
}

@end
