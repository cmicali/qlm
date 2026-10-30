#import "QLMCapture.h"

#import "QLMAdapter.h"
#include "QLMReport.h"

@implementation QLMCaptureReport

- (instancetype)initWithTime:(NSTimeInterval)time output:(BOOL)output bytes:(NSData *)bytes {
    self = [super init];
    if (self) {
        _time = time;
        _output = output;
        _bytes = [bytes copy];
    }
    return self;
}

@end

@interface QLMCaptureExchange ()
@property (nonatomic, readwrite) BOOL hasReply;
@property (nonatomic, readwrite) QLMMessage reply;
@end

@implementation QLMCaptureExchange

- (instancetype)initWithTime:(NSTimeInterval)time outputReport:(NSData *)outputReport message:(QLMMessage)message {
    self = [super init];
    if (self) {
        _time = time;
        _outputReport = [outputReport copy];
        _message = message;
    }
    return self;
}

@end

static int QLMHexDigit(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return -1;
}

static const char *QLMSkipSpaces(const char *cursor, const char *end) {
    while (cursor < end && (*cursor == ' ' || *cursor == '\t' || *cursor == '\r')) {
        cursor++;
    }
    return cursor;
}

// One report line: the time, the direction, then exactly one report's bytes.
// Returns a description of what is wrong, or nil.
static NSString *QLMParseReportLine(const char *line, const char *end, NSTimeInterval *time, BOOL *output,
                                    uint8_t bytes[QLMReportLength]) {
    char *afterTime = NULL;
    *time = strtod(line, &afterTime);
    if (afterTime == line || afterTime > end) {
        return @"no time";
    }
    const char *cursor = QLMSkipSpaces(afterTime, end);
    if (end - cursor >= 4 && strncmp(cursor, "out ", 4) == 0) {
        *output = YES;
        cursor += 4;
    } else if (end - cursor >= 3 && strncmp(cursor, "in ", 3) == 0) {
        *output = NO;
        cursor += 3;
    } else {
        return @"no direction";
    }
    size_t count = 0;
    for (cursor = QLMSkipSpaces(cursor, end); cursor < end; cursor = QLMSkipSpaces(cursor, end)) {
        int high = QLMHexDigit(cursor[0]);
        int low = cursor + 1 < end ? QLMHexDigit(cursor[1]) : -1;
        if (high < 0 || low < 0 || (cursor + 2 < end && cursor[2] != ' ' && cursor[2] != '\r')) {
            return @"a byte is not two hex digits";
        }
        if (count == QLMReportLength) {
            return @"more than one report's bytes";
        }
        bytes[count++] = (uint8_t)(high << 4 | low);
        cursor += 2;
    }
    return count == QLMReportLength ? nil : @"fewer than one report's bytes";
}

@implementation QLMCapture

+ (instancetype)captureWithContentsOfFile:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
    if (data == nil) {
        return nil;
    }
    return [[self alloc] initWithData:data error:error];
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    NSMutableArray<QLMCaptureReport *> *reports = [NSMutableArray array];
    NSMutableArray<QLMCaptureExchange *> *exchanges = [NSMutableArray array];
    NSMutableArray<NSString *> *comments = [NSMutableArray array];
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMCaptureExchange *current = nil;

    NSMutableData *text = [data mutableCopy];
    [text appendBytes:"" length:1];
    const char *cursor = text.bytes;
    const char *stop = cursor + data.length;
    NSUInteger lineNumber = 0;
    NSString *problem = nil;
    while (cursor < stop && problem == nil) {
        lineNumber++;
        const char *end = memchr(cursor, '\n', (size_t)(stop - cursor));
        if (end == NULL) {
            end = stop;
        }
        const char *line = QLMSkipSpaces(cursor, end);
        cursor = end + 1;
        if (line == end) {
            continue;
        }
        if (*line == '#') {
            const char *body = QLMSkipSpaces(line + 1, end);
            NSString *comment = [[NSString alloc] initWithBytes:body length:(NSUInteger)(end - body) encoding:NSUTF8StringEncoding];
            [comments addObject:comment ?: @""];
            continue;
        }

        NSTimeInterval time = 0;
        BOOL output = NO;
        uint8_t bytes[QLMReportLength];
        problem = QLMParseReportLine(line, end, &time, &output, bytes);
        if (problem != nil) {
            break;
        }
        NSData *report = [NSData dataWithBytes:bytes length:sizeof bytes];
        [reports addObject:[[QLMCaptureReport alloc] initWithTime:time output:output bytes:report]];

        if (output) {
            const uint8_t *frame = NULL;
            size_t length = 0;
            QLMMessage message;
            if (assembly.length > 0 && !assembly.complete) {
                problem = @"an output report cuts a reply short";
            } else if (QLMReportUnpackOutput(bytes, sizeof bytes, &frame, &length) != QLMReportOK) {
                problem = @"the output report does not unpack";
            } else if (QLMFrameDecode(frame, length, &message) != QLMFrameOK) {
                problem = @"the output frame does not decode";
            } else {
                current = [[QLMCaptureExchange alloc] initWithTime:time outputReport:report message:message];
                [exchanges addObject:current];
            }
            continue;
        }

        if (current == nil) {
            problem = @"a reply before any output report";
            break;
        }
        QLMReportStatus status = QLMReportAssemblyAdd(&assembly, bytes, sizeof bytes);
        if (status == QLMReportPending) {
            continue;
        }
        QLMMessage reply;
        if (status != QLMReportOK) {
            problem = @"the input report does not assemble";
        } else if (QLMFrameDecode(assembly.frame, assembly.length, &reply) != QLMFrameOK) {
            problem = @"the reply frame does not decode";
        } else if (current.hasReply) {
            problem = @"a second reply to one output report";
        } else {
            current.reply = reply;
            current.hasReply = YES;
        }
    }
    if (problem == nil && assembly.length > 0 && !assembly.complete) {
        problem = @"the capture ends inside a reply";
    }
    if (problem != nil) {
        if (error != NULL) {
            NSString *description = [NSString stringWithFormat:@"Line %lu: %@.", (unsigned long)lineNumber, problem];
            *error = [NSError errorWithDomain:QLMAdapterErrorDomain code:QLMAdapterErrorCapture
                                     userInfo:@{NSLocalizedDescriptionKey: description}];
        }
        return nil;
    }
    _reports = [reports copy];
    _exchanges = [exchanges copy];
    _comments = [comments copy];
    return self;
}

@end
