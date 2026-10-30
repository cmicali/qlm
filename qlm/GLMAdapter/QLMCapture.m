#import "QLMCapture.h"

#import "QLMAdapter.h"
#include "QLMReport.h"

@interface QLMCaptureExchange ()
@property (nonatomic, readwrite, nullable) NSData *replyFrame;
@property (nonatomic, readwrite) BOOL answered;
@end

@implementation QLMCaptureExchange

- (instancetype)initWithTime:(NSTimeInterval)time outputReport:(NSData *)outputReport {
    self = [super init];
    if (self) {
        _time = time;
        _outputReport = [outputReport copy];
    }
    return self;
}

// The capture checked both frames when it read them.
- (QLMMessage)message {
    const uint8_t *frame = NULL;
    size_t length = 0;
    QLMMessage message;
    memset(&message, 0, sizeof message);
    if (QLMReportUnpackOutput(_outputReport.bytes, _outputReport.length, &frame, &length) == QLMReportOK) {
        QLMFrameDecode(frame, length, &message);
    }
    return message;
}

- (QLMMessage)reply {
    QLMMessage reply;
    memset(&reply, 0, sizeof reply);
    if (_replyFrame != nil) {
        QLMFrameDecode(_replyFrame.bytes, _replyFrame.length, &reply);
    }
    return reply;
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
    // strtod needs a terminated string, so the time is copied out.
    char number[32];
    const char *cursor = line;
    while (cursor < end && *cursor != ' ' && *cursor != '\t') {
        cursor++;
    }
    size_t digits = (size_t)(cursor - line);
    char *afterTime = NULL;
    if (digits == 0 || digits >= sizeof number) {
        return @"no time";
    }
    memcpy(number, line, digits);
    number[digits] = '\0';
    *time = strtod(number, &afterTime);
    if (afterTime != number + digits) {
        return @"no time";
    }
    cursor = QLMSkipSpaces(cursor, end);
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
    NSMutableArray<QLMCaptureExchange *> *exchanges = [NSMutableArray array];
    NSMutableArray<NSString *> *comments = [NSMutableArray array];
    QLMReportAssembly assembly;
    QLMReportAssemblyReset(&assembly);
    QLMCaptureExchange *current = nil;

    const char *cursor = data.bytes;
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
        cursor = end < stop ? end + 1 : stop;
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

        if (output) {
            const uint8_t *frame = NULL;
            size_t length = 0;
            QLMMessage message;
            if (QLMReportAssemblyIsPending(&assembly)) {
                problem = @"an output report cuts a reply short";
            } else if (QLMReportUnpackOutput(bytes, sizeof bytes, &frame, &length) != QLMReportOK) {
                problem = @"the output report does not unpack";
            } else if (QLMFrameDecode(frame, length, &message) != QLMFrameOK) {
                problem = @"the output frame does not decode";
            } else {
                current = [[QLMCaptureExchange alloc] initWithTime:time outputReport:[NSData dataWithBytes:bytes length:sizeof bytes]];
                [exchanges addObject:current];
            }
            continue;
        }

        if (current == nil) {
            problem = @"a reply before any output report";
            break;
        }
        QLMMessage reply;
        QLMReportStatus status = QLMReportReadInput(&assembly, bytes, sizeof bytes, &reply);
        if (status == QLMReportPending) {
            continue;
        }
        if (status != QLMReportOK && status != QLMReportNoAnswer) {
            problem = @"the input report does not read";
        } else if (current.replyFrame != nil) {
            problem = @"a second reply to one output report";
        } else {
            current.replyFrame = [NSData dataWithBytes:assembly.frame length:assembly.length];
            current.answered = status == QLMReportOK;
        }
    }
    if (problem == nil && QLMReportAssemblyIsPending(&assembly)) {
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
    _exchanges = [exchanges copy];
    _comments = [comments copy];
    return self;
}

@end
