#import <XCTest/XCTest.h>
@import Security;
@import Network;
#import "../Telephone/AKNetworkReachability.h"

static NSDictionary *lastQuery;
static NSDictionary *lastLookup;
static NSDictionary *lastUpdate;
static OSStatus readStatus, addStatus, updateStatus;
static NSData *readData;
static OSStatus TestCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    lastQuery = [(__bridge NSDictionary *)query copy];
    lastLookup = lastQuery;
    *result = readData == nil ? NULL : CFBridgingRetain(readData);
    return readStatus;
}
static OSStatus TestAdd(CFDictionaryRef query, CFTypeRef *result) {
    lastQuery = [(__bridge NSDictionary *)query copy];
    return addStatus;
}
static OSStatus TestUpdate(CFDictionaryRef query, CFDictionaryRef values) {
    lastQuery = [(__bridge NSDictionary *)query copy];
    lastUpdate = [(__bridge NSDictionary *)values copy];
    return updateStatus;
}
// Compile the wrapper against fakes so these tests never touch saved credentials.
#define SecItemCopyMatching TestCopyMatching
#define SecItemAdd TestAdd
#define SecItemUpdate TestUpdate
#import "../Telephone/AKKeychain.m"
#undef SecItemCopyMatching
#undef SecItemAdd
#undef SecItemUpdate

@interface AKNetworkReachability (Testing)
- (void)pathStatusChanged:(nw_path_status_t)status;
@end

@interface SystemServicesTests : XCTestCase
@end
@implementation SystemServicesTests
- (void)setUp {
    [super setUp];
    lastQuery = nil;
    lastLookup = nil;
    lastUpdate = nil;
    readData = nil;
    readStatus = addStatus = updateStatus = errSecSuccess;
}
- (void)testKeychainReadPreservesLegacyLookupAndHandlesFailure {
    readData = [@"sênha 🔐" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects([AKKeychain passwordForService:@"SIP: example.test" account:@"100"], @"sênha 🔐");
    XCTAssertEqualObjects(lastQuery[(__bridge id)kSecClass], (__bridge id)kSecClassGenericPassword);
    XCTAssertEqualObjects(lastQuery[(__bridge id)kSecAttrService], @"SIP: example.test");
    XCTAssertEqualObjects(lastQuery[(__bridge id)kSecAttrAccount], @"100");
    XCTAssertNil(lastQuery[(__bridge id)kSecUseDataProtectionKeychain]);
    readData = nil;
    readStatus = errSecItemNotFound;
    XCTAssertEqualObjects([AKKeychain passwordForService:@"SIP: example.test" account:@"100"], @"");
    readStatus = errSecAuthFailed;
    XCTAssertEqualObjects([AKKeychain passwordForService:@"SIP: example.test" account:@"100"], @"");
}
- (void)testKeychainAddsAndUpdatesOnlyDuplicates {
    XCTAssertTrue([AKKeychain addItemWithService:@"SIP: example.test" account:@"100" password:@"á"]);
    XCTAssertEqualObjects(lastQuery[(__bridge id)kSecValueData], [@"á" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertNil(lastUpdate);
    addStatus = errSecDuplicateItem;
    readData = [@"first-item-reference" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([AKKeychain addItemWithService:@"SIP: example.test" account:@"100" password:@""]);
    XCTAssertEqualObjects(lastLookup[(__bridge id)kSecAttrService], @"SIP: example.test");
    XCTAssertEqualObjects(lastLookup[(__bridge id)kSecAttrAccount], @"100");
    XCTAssertEqualObjects(lastLookup[(__bridge id)kSecMatchLimit], (__bridge id)kSecMatchLimitOne);
    XCTAssertEqualObjects(lastLookup[(__bridge id)kSecReturnPersistentRef], @YES);
    XCTAssertEqualObjects(lastQuery[(__bridge id)kSecMatchItemList], @[readData]);
    XCTAssertEqualObjects(lastUpdate[(__bridge id)kSecValueData], [NSData data]);
    updateStatus = errSecAuthFailed;
    XCTAssertFalse([AKKeychain addItemWithService:@"SIP: example.test" account:@"100" password:@"new"]);
    lastUpdate = nil;
    addStatus = errSecAuthFailed;
    XCTAssertFalse([AKKeychain addItemWithService:@"SIP: example.test" account:@"100" password:@"new"]);
    XCTAssertNil(lastUpdate);
}
- (void)testDuplicatePasswordIsNotUpdatedWhenItemLookupFails {
    addStatus = errSecDuplicateItem;
    for (NSNumber *status in @[@(errSecItemNotFound), @(errSecAuthFailed), @(errSecSuccess)]) {
        readStatus = status.intValue;
        readData = nil;
        XCTAssertFalse([AKKeychain addItemWithService:@"SIP: example.test" account:@"100" password:@"new"]);
        XCTAssertNil(lastUpdate);
    }
}
- (void)testNetworkPathNotificationsIncludeUsableRouteChangesAndOnDemandConnections {
    XCTAssertNil([AKNetworkReachability networkReachabilityWithHost:@""]);
    AKNetworkReachability *monitor = [AKNetworkReachability networkReachabilityWithHost:@"example.test"];
    XCTAssertEqualObjects(monitor.host, @"example.test");
    NSMutableArray *notifications = [NSMutableArray array];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:nil object:monitor queue:nil
        usingBlock:^(NSNotification *note) { [notifications addObject:note.name]; }];
    [monitor pathStatusChanged:nw_path_status_satisfied];
    [monitor pathStatusChanged:nw_path_status_satisfied];
    [monitor pathStatusChanged:nw_path_status_unsatisfied];
    [monitor pathStatusChanged:nw_path_status_satisfiable];
    XCTAssertEqualObjects(notifications, (@[AKNetworkReachabilityDidBecomeReachableNotification,
        AKNetworkReachabilityDidBecomeReachableNotification, AKNetworkReachabilityDidBecomeUnreachableNotification,
        AKNetworkReachabilityDidBecomeReachableNotification]));
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}
@end
