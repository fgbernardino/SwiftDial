//
//  AKKeychain.m
//  Telephone
//
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

#import "AKKeychain.h"

@import Security;

@implementation AKKeychain

+ (nonnull NSString *)passwordForService:(nonnull NSString *)service account:(nonnull NSString *)account {
    NSParameterAssert(service);
    NSParameterAssert(account);
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSData *data = CFBridgingRelease(result);
    if (status != errSecSuccess) { return @""; }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

+ (BOOL)addItemWithService:(nonnull NSString *)service account:(nonnull NSString *)account password:(nonnull NSString *)password {
    NSParameterAssert(service);
    NSParameterAssert(account);
    NSParameterAssert(password);
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account
    };
    NSDictionary *values = @{(__bridge id)kSecValueData: [password dataUsingEncoding:NSUTF8StringEncoding]};
    NSMutableDictionary *item = [query mutableCopy];
    [item addEntriesFromDictionary:values];
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecDuplicateItem) {
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)values);
    }
    return status == errSecSuccess;
}

@end
