#import "QLMAdapter.h"

NSErrorDomain const QLMAdapterErrorDomain = @"QLMAdapterErrorDomain";

NSError *QLMAdapterErrorMake(QLMAdapterError code, NSString *description) {
    return [NSError errorWithDomain:QLMAdapterErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

BOOL QLMAdapterPackReport(const QLMMessage *message, uint8_t report[QLMReportLength], NSError **error) {
    QLMReportStatus status = QLMReportPackOutput(message, report);
    if (status == QLMReportOK) {
        return YES;
    }
    if (error != NULL) {
        if (status == QLMReportErrorForbidden) {
            *error = QLMAdapterErrorMake(QLMAdapterErrorForbidden, @"The allowlist refused the message.");
        } else {
            *error = QLMAdapterErrorMake(QLMAdapterErrorTooLong, @"The frame does not fit one output report.");
        }
    }
    return NO;
}

NSData *QLMAdapterRecord(const QLMMessage *message) {
    NSMutableData *record = [NSMutableData dataWithBytes:&message->address length:1];
    [record appendBytes:message->payload length:message->length];
    return record;
}
