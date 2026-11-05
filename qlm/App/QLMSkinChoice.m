#import "QLMSkinChoice.h"

#import "QLMSkinImages.h"

@implementation QLMSkinChoice {
    QLMPreferences *_preferences;
    QLMSkinLibrary *_library;
}

- (instancetype)initWithPreferences:(QLMPreferences *)preferences library:(QLMSkinLibrary *)library {
    self = [super init];
    if (self) {
        _preferences = preferences;
        _library = library;
        NSString *refusal = nil;
        _skin = [library loadSkinNamed:preferences.skinName refusal:&refusal];
        _refusal = [refusal copy];
        NSAssert(_skin != nil, @"the default skin is refused");
        [[QLMSkinImages imagesOfSkin:_skin] warm];
    }
    return self;
}

- (NSString *)chooseSkinNamed:(NSString *)name {
    NSString *refusal = nil;
    QLMSkin *skin = [_library loadSkinNamed:name refusal:&refusal];
    if (refusal != nil) {
        return refusal;
    }
    _skin = skin;
    _refusal = nil;
    [[QLMSkinImages imagesOfSkin:skin] warm];
    _preferences.skinName = name;
    return nil;
}

@end
