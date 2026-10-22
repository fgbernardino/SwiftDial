//
//  AKNetworkReachability.m
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

#import "AKNetworkReachability.h"

@import Network;

NSString * const AKNetworkReachabilityDidBecomeReachableNotification = @"AKNetworkReachabilityDidBecomeReachable";
NSString * const AKNetworkReachabilityDidBecomeUnreachableNotification = @"AKNetworkReachabilityDidBecomeUnreachable";

@interface AKNetworkReachability ()
@property(nonatomic, copy) NSString *host;
@property(nonatomic, strong) nw_path_monitor_t monitor;
@end

@implementation AKNetworkReachability

+ (AKNetworkReachability *)networkReachabilityWithHost:(NSString *)nameOrAddress {
    return [[self alloc] initWithHost:nameOrAddress];
}

- (instancetype)initWithHost:(NSString *)nameOrAddress {
    self = [super init];
    if (self == nil || nameOrAddress.length == 0) { return nil; }
    _host = [nameOrAddress copy];
    _monitor = nw_path_monitor_create();
    __weak AKNetworkReachability *weakSelf = self;
    nw_path_monitor_set_update_handler(_monitor, ^(nw_path_t path) {
        [weakSelf pathStatusChanged:nw_path_get_status(path)];
    });
    nw_path_monitor_set_queue(_monitor, dispatch_get_main_queue());
    nw_path_monitor_start(_monitor);
    return self;
}

- (void)pathStatusChanged:(nw_path_status_t)status {
    BOOL canAttemptConnection = status == nw_path_status_satisfied || status == nw_path_status_satisfiable;
    [[NSNotificationCenter defaultCenter] postNotificationName:canAttemptConnection
        ? AKNetworkReachabilityDidBecomeReachableNotification
        : AKNetworkReachabilityDidBecomeUnreachableNotification object:self];
}

- (void)dealloc {
    if (_monitor != nil) { nw_path_monitor_cancel(_monitor); }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ network path monitor", self.host];
}

@end
