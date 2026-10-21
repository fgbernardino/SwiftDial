//
//  AKNetworkReachability.h
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

#import <Foundation/Foundation.h>


// Notifications.
//
// Sent when a network path allows a connection attempt, including route changes.
extern NSString * const AKNetworkReachabilityDidBecomeReachableNotification;
//
// Sent when no usable general network path is available.
extern NSString * const AKNetworkReachabilityDidBecomeUnreachableNotification;

// Network path changes trigger registration attempts; SIP determines host availability.
@interface AKNetworkReachability : NSObject

@property(nonatomic, readonly, copy) NSString *host;

// Returns a new instance of the network reachability for the given host.
// Returns nil when |nameOrAddress| is nil or @"".
+ (AKNetworkReachability *)networkReachabilityWithHost:(NSString *)nameOrAddress;

// Designated initializer.
// Returns nil when |nameOrAddress| is nil or @"".
- (instancetype)initWithHost:(NSString *)nameOrAddress;

@end
