#import "QLMSkinLibrary.h"

NSString *const QLMSkinDefaultName = @"modern";

@implementation QLMSkinLibrary {
    NSURL *_builtIn;
    NSURL *_user;
}

+ (instancetype)standardLibrary {
    NSURL *builtIn = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Skins" isDirectory:YES];
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    NSURL *user = [support URLByAppendingPathComponent:@"qlm/Skins" isDirectory:YES];
    return [[self alloc] initWithBuiltIn:builtIn user:user];
}

- (instancetype)initWithBuiltIn:(NSURL *)builtIn user:(NSURL *)user {
    self = [super init];
    if (self) {
        _builtIn = builtIn;
        _user = user;
    }
    return self;
}

// The directories in `directory` that hold a skin.json, sorted.
static NSArray<NSString *> *QLMSkinNamesIn(NSURL *_Nullable directory) {
    if (directory == nil) {
        return @[];
    }
    NSArray<NSURL *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
                                                            includingPropertiesForKeys:nil
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:NULL];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSURL *entry in entries) {
        if ([NSFileManager.defaultManager fileExistsAtPath:[entry URLByAppendingPathComponent:@"skin.json"].path]) {
            [names addObject:entry.lastPathComponent];
        }
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSArray<NSString *> *)skinNames {
    NSArray<NSString *> *builtIn = QLMSkinNamesIn(_builtIn);
    NSMutableArray<NSString *> *names = [builtIn mutableCopy];
    for (NSString *name in QLMSkinNamesIn(_user)) {
        if (![builtIn containsObject:name]) {
            [names addObject:name];
        }
    }
    return names;
}

- (BOOL)isBuiltIn:(NSString *)name {
    return [QLMSkinNamesIn(_builtIn) containsObject:name];
}

- (NSURL *)directoryOfSkin:(NSString *)name {
    BOOL builtIn = [self isBuiltIn:name] || _user == nil;
    return [(builtIn ? _builtIn : _user) URLByAppendingPathComponent:name isDirectory:YES];
}

- (QLMSkin *)loadSkinNamed:(NSString *)name refusal:(NSString **)refusal {
    NSError *error = nil;
    QLMSkin *skin = nil;
    if (name.length > 0 && ![name containsString:@"/"] && ![name hasPrefix:@"."]) {
        skin = [QLMSkin skinAtURL:[self directoryOfSkin:name] error:&error];
    }
    NSString *reason = nil;
    if (skin == nil) {
        reason = error.localizedDescription ?: [NSString stringWithFormat:@"There is no skin named %@.", name];
        skin = [QLMSkin skinAtURL:[_builtIn URLByAppendingPathComponent:QLMSkinDefaultName isDirectory:YES] error:NULL];
    }
    _lastRefusal = [reason copy];
    if (refusal != NULL) {
        *refusal = reason;
    }
    return skin;
}

@end
