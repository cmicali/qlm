#import "QLMSkinLibrary.h"

NSString *const QLMSkinDefaultName = @"modern";

@implementation QLMSkinLibrary {
    NSURL *_builtIn;
    NSURL *_user;
}

- (NSURL *)userDirectory {
    return _user;
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

static BOOL QLMSkinHasFile(NSURL *_Nullable directory, NSString *name) {
    NSURL *file = [[directory URLByAppendingPathComponent:name isDirectory:YES] URLByAppendingPathComponent:@"skin.json"];
    return directory != nil && [NSFileManager.defaultManager fileExistsAtPath:file.path];
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
        if (QLMSkinHasFile(directory, entry.lastPathComponent)) {
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
    return QLMSkinIsPlainName(name) && QLMSkinHasFile(_builtIn, name);
}

- (QLMSkin *)loadSkinNamed:(NSString *)name refusal:(NSString **)refusal {
    NSError *error = nil;
    QLMSkin *skin = nil;
    if (QLMSkinIsPlainName(name)) {
        NSURL *directory = [self isBuiltIn:name] || _user == nil ? _builtIn : _user;
        skin = [QLMSkin skinAtURL:[directory URLByAppendingPathComponent:name isDirectory:YES] error:&error];
    }
    NSString *reason = nil;
    if (skin == nil) {
        reason = error.localizedDescription ?: [NSString stringWithFormat:@"There is no skin named %@.", name];
        skin = [QLMSkin skinAtURL:[_builtIn URLByAppendingPathComponent:QLMSkinDefaultName isDirectory:YES] error:NULL];
    }
    if (refusal != NULL) {
        *refusal = reason;
    }
    return skin;
}

@end

NSString *QLMSkinNote(NSString *refusal, NSString *shownName, NSURL *userDirectory) {
    if (refusal != nil) {
        return [NSString stringWithFormat:@"%@ %@ shows instead.", refusal, shownName];
    }
    NSString *folder = userDirectory.path.stringByAbbreviatingWithTildeInPath ?: @"qlm's skins folder";
    return [NSString stringWithFormat:@"A skin is a folder with skin.json and png/ in %@. "
                                      @"qlm/App/Skins/README.md gives the format.", folder];
}
