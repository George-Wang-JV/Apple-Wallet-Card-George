#ifndef AIRCARD_OS_TRACE_H
#define AIRCARD_OS_TRACE_H

#import <Foundation/Foundation.h>

// Wire format reference:
// https://github.com/libimobiledevice/libimobiledevice/blob/master/include/libimobiledevice/ostrace.h

// os_trace_relay frames use a type byte followed by a 32-bit payload length.
// Plist replies (type 1) use big endian; activity records (type 2) use little
// endian. Read through the service connection so secure sessions work too.
typedef long (*ScreenTraceReceive)(void *connection, void *bytes, long length);

static BOOL ScreenTraceReadExact(ScreenTraceReceive receive, void *connection,
                                 void *bytes, NSUInteger length) {
    NSUInteger offset = 0;
    while (offset < length) {
        long count = receive(connection, (uint8_t *)bytes + offset,
                             (long)(length - offset));
        if (count <= 0 || (NSUInteger)count > length - offset) return NO;
        offset += (NSUInteger)count;
    }
    return YES;
}

static uint32_t ScreenTraceUInt32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static uint16_t ScreenTraceUInt16(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static NSData *ScreenTraceReadFrame(ScreenTraceReceive receive,
                                    void *connection, uint8_t *type,
                                    NSString **error) {
    uint8_t header[5];
    if (!ScreenTraceReadExact(receive, connection, header, sizeof(header))) {
        *error = @"The device log stream disconnected or ended unexpectedly.";
        return nil;
    }
    *type = header[0];
    uint32_t length;
    if (*type == 1) {
        length = ((uint32_t)header[1] << 24) | ((uint32_t)header[2] << 16) |
                 ((uint32_t)header[3] << 8) | header[4];
    } else if (*type == 2) {
        length = ScreenTraceUInt32(header + 1);
    } else {
        *error = @"The device returned an unsupported log frame type.";
        return nil;
    }
    // Reject corrupt lengths before allocating or waiting for a payload.
    if (length == 0 || length > 16 * 1024 * 1024) {
        *error = @"The device returned an invalid log frame length.";
        return nil;
    }
    NSMutableData *payload = [NSMutableData dataWithLength:length];
    if (!ScreenTraceReadExact(receive, connection, payload.mutableBytes, length)) {
        *error = @"The device log stream ended in the middle of a record.";
        return nil;
    }
    return payload;
}

static NSString *ScreenTraceString(const uint8_t *bytes, NSUInteger length) {
    while (length && bytes[length - 1] == 0) length--;
    NSString *text = [[NSString alloc] initWithBytes:bytes length:length
                                          encoding:NSUTF8StringEncoding];
    return text ?: [[NSString alloc] initWithBytes:bytes length:length
                                          encoding:NSISOLatin1StringEncoding];
}

static NSString *ScreenTraceLogLine(NSData *record) {
    // The activity record has a 129-byte header, then length-delimited process,
    // image and message strings. Read fields explicitly to avoid alignment and
    // host-endian assumptions. Ignore non-log or incomplete activity records.
    if (record.length < 129) return nil;
    const uint8_t *bytes = record.bytes;
    if (bytes[0] != 2) return nil;
    NSUInteger headerLength = ScreenTraceUInt32(bytes + 5);
    NSUInteger processLength = ScreenTraceUInt16(bytes + 37);
    NSUInteger imageLength = ScreenTraceUInt16(bytes + 107);
    NSUInteger messageLength = ScreenTraceUInt32(bytes + 109);
    if (headerLength < 129 || headerLength > record.length ||
        !processLength || !messageLength ||
        processLength + imageLength + messageLength > record.length - headerLength)
        return nil;

    const uint8_t *text = bytes + headerLength;
    NSString *process = ScreenTraceString(text, processLength).lastPathComponent;
    NSString *image = ScreenTraceString(text + processLength, imageLength).lastPathComponent;
    NSString *message = ScreenTraceString(text + processLength + imageLength,
                                           messageLength);
    // One stdout line must remain one activity record. iOS 27 emits some NFC
    // selection details on continuation lines; flatten those lines so the app
    // keeps the process context and can parse the complete event atomically.
    message = [message stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    message = [message stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return [NSString stringWithFormat:@"%@(%@): %@\n", process, image, message];
}

#endif
