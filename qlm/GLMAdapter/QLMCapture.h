#import <Foundation/Foundation.h>

#include "QLMFrame.h"

NS_ASSUME_NONNULL_BEGIN

// One HID report from a capture's reports.txt.
@interface QLMCaptureReport : NSObject

@property (nonatomic, readonly) NSTimeInterval time;  // seconds from the capture's first packet
@property (nonatomic, readonly) BOOL output;          // host to adapter
@property (nonatomic, readonly) NSData *bytes;        // QLMReportLength bytes

@end

// One output report and the reply the adapter gave before the next one.
@interface QLMCaptureExchange : NSObject

@property (nonatomic, readonly) NSTimeInterval time;
@property (nonatomic, readonly) NSData *outputReport;
@property (nonatomic, readonly) QLMMessage message;
@property (nonatomic, readonly) BOOL hasReply;  // NO for a broadcast, or a reply the capture cut off
@property (nonatomic, readonly) QLMMessage reply;

@end

// A capture in the text form tools/pcapng-to-reports.py writes: a `#` line is
// a comment, and every other line is the time, `out` or `in`, and the
// report's bytes in hex. Reading fails on any report the report layer or the
// frame codec rejects, or on a reply with no output report before it.
@interface QLMCapture : NSObject

+ (nullable instancetype)captureWithContentsOfFile:(NSString *)path error:(NSError **)error;
- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSArray<QLMCaptureReport *> *reports;
@property (nonatomic, readonly) NSArray<QLMCaptureExchange *> *exchanges;
@property (nonatomic, readonly) NSArray<NSString *> *comments;  // without the `# `

@end

NS_ASSUME_NONNULL_END
