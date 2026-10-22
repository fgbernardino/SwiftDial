//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//


#import "SIPLog.h"

static dispatch_queue_t LogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.swiftdial.sip-log", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static FILE *logFile;
static NSUInteger consoleLogLevel;

NSString *SIPRedactedLogMessage(NSData *data) {
    NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!message || [message rangeOfString:@"\0"].location != NSNotFound) {
        return @"[redacted invalid SIP diagnostic]\n";
    }
    message = [[message stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
               stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    static NSRegularExpression *sensitive;
    static NSRegularExpression *uri;
    static NSRegularExpression *body;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sensitive = [NSRegularExpression regularExpressionWithPattern:
            @"authorization|authenticate|authentication-info|password|passwd|pwd|secret|token|credential|nonce|api[-_]?key|cookie|\\b(?:key|response)\\s*[:=]|a=(?:crypto|ice-pwd|ice-ufrag)|(?:^|[\\r\\n])k="
            options:NSRegularExpressionCaseInsensitive error:NULL];
        uri = [NSRegularExpression regularExpressionWithPattern:@"(?:sips?|tels?|https?):[^\\s<>\"']*"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        body = [NSRegularExpression regularExpressionWithPattern:@"\\n[ \\t]*\\n"
            options:0 error:NULL];
    });
    // Drop the whole record so folded, truncated and encoded credentials cannot survive a partial replacement.
    NSString *decoded = message;
    while (YES) {
        if ([sensitive firstMatchInString:decoded options:0 range:NSMakeRange(0, decoded.length)]) {
            return @"[redacted credential-bearing SIP diagnostic]\n";
        }
        if (decoded != message && [uri firstMatchInString:decoded options:0 range:NSMakeRange(0, decoded.length)]) {
            return @"[redacted encoded SIP URI]\n";
        }
        NSString *next = decoded.stringByRemovingPercentEncoding;
        if (!next) { return @"[redacted malformed encoded SIP diagnostic]\n"; }
        if ([next isEqualToString:decoded]) { break; }
        decoded = next;
    }
    NSTextCheckingResult *separator = [body firstMatchInString:message options:0 range:NSMakeRange(0, message.length)];
    if (separator) {
        message = [[message substringToIndex:separator.range.location] stringByAppendingString:@"\n[redacted message body]\n"];
    }
    return [uri stringByReplacingMatchesInString:message options:0 range:NSMakeRange(0, message.length)
                                   withTemplate:@"[redacted URI]"];
}

BOOL SIPLogOpen(NSString *path, NSUInteger level) {
    __block BOOL success;
    dispatch_sync(LogQueue(), ^{
        if (logFile) { fclose(logFile); }
        logFile = path.length ? fopen(path.stringByExpandingTildeInPath.fileSystemRepresentation, "w") : NULL;
        consoleLogLevel = level;
        success = !path.length || logFile != NULL;
    });
    return success;
}

void SIPLogWrite(int level, const char *data, int length) {
    if (!data || length <= 0) { return; }
    @autoreleasepool {
        NSData *safe = [SIPRedactedLogMessage([NSData dataWithBytes:data length:(NSUInteger)length])
                       dataUsingEncoding:NSUTF8StringEncoding];
        dispatch_async(LogQueue(), ^{
            if (logFile && (fwrite(safe.bytes, 1, safe.length, logFile) != safe.length || fflush(logFile) != 0)) {
                fclose(logFile);
                logFile = NULL;
                fputs("Could not write SIP diagnostic log.\n", stderr);
            }
            if (level <= (int)consoleLogLevel) {
                fwrite(safe.bytes, 1, safe.length, stderr);
            }
        });
    }
}

void SIPLogClose(void) {
    dispatch_sync(LogQueue(), ^{
        if (logFile) { fclose(logFile); logFile = NULL; }
        consoleLogLevel = 0;
    });
}
