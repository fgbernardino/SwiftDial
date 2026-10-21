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


#import <XCTest/XCTest.h>
#import "../Telephone/SIPLog.h"
#import <unistd.h>

@interface SIPLogTests : XCTestCase
@end

@implementation SIPLogTests

- (void)tearDown {
    SIPLogClose();
    [super tearDown];
}

- (void)testPreservesStatusAndOrdinaryHeaders {
    NSString *input = @"RX 80 bytes\r\nSIP/2.0 486 Busy Here\r\nCSeq: 1 INVITE\r\n";
    XCTAssertEqualObjects(SIPRedactedLogMessage([input dataUsingEncoding:NSUTF8StringEncoding]),
                          @"RX 80 bytes\nSIP/2.0 486 Busy Here\nCSeq: 1 INVITE\n");
}

- (void)testDropsCredentialRecordsIncludingFoldedTruncatedAndEncodedForms {
    for (NSString *input in @[
        @"Authorization: Digest username=alice,\r\n\tresponse=synthetic-value",
        @"pRoXy-AuThOrIzAtIoN \t: Bearer synthetic-value",
        @"WWW-Authenticate: Digest realm=test, nonce=synthetic-value",
        @"Authentication-Info: nextnonce=synthetic-value",
        @"password='synthetic-value", @"passwd: synthetic-value", @"access_token=synthetic-value",
        @"X-API-Key: synthetic-value", @"Cookie: session=synthetic-value",
        @"a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:synthetic-value",
        @"a=ice-pwd:synthetic-value", @"k=clear:synthetic-value",
        @"TX: AES_CM_128_HMAC_SHA1_80 key=c3ludGhldGlj",
        @"RX: AES_CM_128_HMAC_SHA1_80 key=c3ludGhldGlj",
        @"Digest response = synthetic-value",
        @"%2541uthorization%253A%2520synthetic-value"
    ]) {
        NSString *safe = SIPRedactedLogMessage([input dataUsingEncoding:NSUTF8StringEncoding]);
        XCTAssertEqualObjects(safe, @"[redacted credential-bearing SIP diagnostic]\n");
    }
}

- (void)testRemovesWholeURIsIncludingTruncatedUserinfo {
    for (NSString *uri in @[@"sip:alice:synthetic-value@example.test", @"SIPS:alice:synthetic-value",
                             @"https://alice:synthetic-value@example.test/path?route=value", @"tel:+5511999999999"]) {
        NSString *input = [NSString stringWithFormat:@"Call <%@> failed: 403", uri];
        XCTAssertEqualObjects(SIPRedactedLogMessage([input dataUsingEncoding:NSUTF8StringEncoding]),
                              @"Call <[redacted URI]> failed: 403");
    }
    XCTAssertEqualObjects(SIPRedactedLogMessage([@"sip%3Aalice:value@example.test%ZZ" dataUsingEncoding:NSUTF8StringEncoding]),
                          @"[redacted malformed encoded SIP diagnostic]\n");
    XCTAssertEqualObjects(SIPRedactedLogMessage([@"s%2569p:alice:synthetic-value@example.test" dataUsingEncoding:NSUTF8StringEncoding]),
                          @"[redacted encoded SIP URI]\n");
}

- (void)testOmitsBodiesWithoutNeedingToKnowTheirFormat {
    for (NSString *newline in @[@"\r\n", @"\n", @"\r"]) {
        NSString *input = [NSString stringWithFormat:@"SIP/2.0 200 OK%@Content-Type: application/sdp%@%@private-body", newline, newline, newline];
        NSString *safe = SIPRedactedLogMessage([input dataUsingEncoding:NSUTF8StringEncoding]);
        XCTAssertEqualObjects(safe, @"SIP/2.0 200 OK\nContent-Type: application/sdp\n[redacted message body]\n");
    }
}

- (void)testFailsClosedForInvalidUTF8AndEmbeddedNUL {
    const unsigned char invalid[] = {0xff, 'a'};
    const char nul[] = {'a', 0, 'b'};
    for (NSData *data in @[[NSData dataWithBytes:invalid length:sizeof(invalid)], [NSData dataWithBytes:nul length:sizeof(nul)]]) {
        XCTAssertEqualObjects(SIPRedactedLogMessage(data), @"[redacted invalid SIP diagnostic]\n");
    }
}

- (void)testFileAndConsoleReceiveOnlySanitizedBytesAndRespectLevels {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    FILE *capture = tmpfile();
    XCTAssertNotEqual(capture, NULL);
    int original = dup(STDERR_FILENO);
    fflush(stderr);
    dup2(fileno(capture), STDERR_FILENO);
    @try {
        XCTAssertTrue(SIPLogOpen(path, 2));
        const char *sensitive = "Authorization: Digest synthetic-value\n";
        SIPLogWrite(2, sensitive, (int)strlen(sensitive));
        SIPLogWrite(3, "file-only\n", 10);
        SIPLogWrite(2, "safe ignored-tail", 4);
        SIPLogClose();
    } @finally {
        fflush(stderr);
        dup2(original, STDERR_FILENO);
        close(original);
    }
    rewind(capture);
    char buffer[1024] = {0};
    size_t count = fread(buffer, 1, sizeof(buffer), capture);
    fclose(capture);
    NSString *console = [[NSString alloc] initWithBytes:buffer length:count encoding:NSUTF8StringEncoding];
    NSString *file = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertEqualObjects(console, @"[redacted credential-bearing SIP diagnostic]\nsafe");
    XCTAssertEqualObjects(file, @"[redacted credential-bearing SIP diagnostic]\nfile-only\nsafe");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)testConcurrentCallbacksDrainBeforeCloseAndRestartUsesNewFile {
    NSString *first = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *second = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    XCTAssertTrue(SIPLogOpen(first, 0));
    dispatch_apply(100, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t index) {
        SIPLogWrite(3, "SIP/2.0 200 OK\n", 15);
    });
    SIPLogClose();
    NSString *result = [NSString stringWithContentsOfFile:first encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertEqual([result componentsSeparatedByString:@"SIP/2.0 200 OK\n"].count, 101U);
    XCTAssertTrue(SIPLogOpen(second, 0));
    SIPLogWrite(3, "restart\n", 8);
    SIPLogClose();
    XCTAssertEqualObjects([NSString stringWithContentsOfFile:second encoding:NSUTF8StringEncoding error:NULL], @"restart\n");
    XCTAssertEqualObjects([NSString stringWithContentsOfFile:first encoding:NSUTF8StringEncoding error:NULL], result);
    [[NSFileManager defaultManager] removeItemAtPath:first error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:second error:NULL];
}

- (void)testEmptyPathAndOpenFailureAreExplicit {
    XCTAssertTrue(SIPLogOpen(@"", 0));
    XCTAssertFalse(SIPLogOpen([NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathComponent:@"missing/log"]], 0));
    SIPLogWrite(3, "safe\n", 5);
}

@end
