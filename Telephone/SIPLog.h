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

NS_ASSUME_NONNULL_BEGIN

NSString *SIPRedactedLogMessage(NSData *data);
BOOL SIPLogOpen(NSString *path, NSUInteger consoleLevel);
void SIPLogWrite(int level, const char *data, int length);
void SIPLogClose(void);

NS_ASSUME_NONNULL_END
