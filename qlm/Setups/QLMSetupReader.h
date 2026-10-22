#import <Foundation/Foundation.h>

#import "QLMSetup.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const QLMSetupErrorDomain;

typedef NS_ERROR_ENUM(QLMSetupErrorDomain, QLMSetupError) {
    QLMSetupErrorEncoding = 1,
    QLMSetupErrorMagic,      // not a GLM5_v2 file
    QLMSetupErrorStructure,  // a line or section out of place; the line is in userInfo
    QLMSetupErrorValue,      // a number that does not parse
};

extern NSString *const QLMSetupErrorLineKey;  // NSNumber, the 1-based line

// Reads a GLM 5 setup file. Strict about the structure, so a changed format
// fails loudly, and it carries every key it does not know in unknownKeys
// rather than dropping it. Format source: Tests/Setups/Fixtures/Main.sam,
// a redacted GLM 5.2.1 file.
@interface QLMSetupReader : NSObject

+ (nullable QLMSetup *)readData:(NSData *)data error:(NSError **)error;
+ (nullable QLMSetup *)readFileAtPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
