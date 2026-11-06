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

QLMMessage QLMAdapterRecordMessage(NSData *_Nullable record) {
    if (record.length == 0) {
        return QLMMessageMake(0, NULL, 0);
    }
    const uint8_t *bytes = record.bytes;
    return QLMMessageMake(bytes[0], bytes + 1, record.length - 1);
}

void QLMTapExchange(QLMTrafficTap tap, const QLMMessage *request, const QLMMessage *_Nullable reply) {
    tap(QLMTrafficRequest, request);
    if (reply != NULL) {
        tap(QLMTrafficReply, reply);
    } else if (QLMReportExpectsReply(request)) {
        const uint8_t flag = QLMFrameFlag;
        QLMMessage noAnswer = QLMMessageMake(QLMAddressReply, &flag, 1);
        tap(QLMTrafficNoAnswer, &noAnswer);
    }
}
