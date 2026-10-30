#import "QLMAdapter.h"

NSErrorDomain const QLMAdapterErrorDomain = @"QLMAdapterErrorDomain";

BOOL QLMAdapterPackReport(const QLMMessage *message, uint8_t report[QLMReportLength], NSError **error) {
    QLMReportStatus status = QLMReportPackOutput(message, report);
    if (status == QLMReportOK) {
        return YES;
    }
    if (error != NULL) {
        QLMAdapterError code = status == QLMReportErrorForbidden ? QLMAdapterErrorForbidden : QLMAdapterErrorTooLong;
        *error = [NSError errorWithDomain:QLMAdapterErrorDomain code:code userInfo:nil];
    }
    return NO;
}

NSData *QLMAdapterRecord(const QLMMessage *message) {
    NSMutableData *record = [NSMutableData dataWithBytes:&message->address length:1];
    [record appendBytes:message->payload length:message->length];
    return record;
}
