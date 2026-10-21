//
//  AKTelephoneNumberFormatter.m
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

#import "AKTelephoneNumberFormatter.h"


@implementation AKTelephoneNumberFormatter

- (NSString *)stringForObjectValue:(id)anObject {
    if (![anObject isKindOfClass:[NSString class]]) {
        return nil;
    }
    
    NSString *theString;
    NSString *number = anObject;
    if ([number rangeOfString:@"^0[3589]00[0-9]{7}\\z" options:NSRegularExpressionSearch].location != NSNotFound) {
        return [NSString stringWithFormat:@"%@ %@ %@", [number substringToIndex:4],
                [number substringWithRange:NSMakeRange(4, 3)], [number substringFromIndex:7]];
    }

    NSString *country = @"";
    if (([number hasPrefix:@"+55"] && (number.length == 13 || number.length == 14)) ||
        ([number hasPrefix:@"55"] && (number.length == 12 || number.length == 13))) {
        NSUInteger prefixLength = [number hasPrefix:@"+"] ? 3 : 2;
        country = [[number substringToIndex:prefixLength] stringByAppendingString:@" "];
        number = [number substringFromIndex:prefixLength];
    }

    NSString *area = @"";
    if (number.length == 10 || number.length == 11) {
        NSString *candidate = [number substringToIndex:2];
        if ([candidate rangeOfString:@"^[1-9][0-9]\\z" options:NSRegularExpressionSearch].location != NSNotFound) {
            area = [NSString stringWithFormat:@"(%@) ", candidate];
            number = [number substringFromIndex:2];
        }
    }
    if ([number rangeOfString:@"^(?:[2-5][0-9]{7}|9[0-9]{8})\\z" options:NSRegularExpressionSearch].location != NSNotFound) {
        NSUInteger split = number.length - 4;
        return [NSString stringWithFormat:@"%@%@%@-%@", country, area,
                [number substringToIndex:split], [number substringFromIndex:split]];
    }

    // Preserve explicit North American/Russian formatting; do not regroup extensions or PBX codes.
    if ([[NSPredicate predicateWithFormat:@"SELF MATCHES '\\\\+(1|7)\\\\d{10}'"] evaluateWithObject:anObject]) {
        if ([self splitsLastFourDigits]) {        // +# (###) ###-##-##
            theString = [NSString stringWithFormat:@"%@ (%@) %@-%@-%@",
                         [anObject substringWithRange:NSMakeRange(0, 2)],
                         [anObject substringWithRange:NSMakeRange(2, 3)],
                         [anObject substringWithRange:NSMakeRange(5, 3)],
                         [anObject substringWithRange:NSMakeRange(8, 2)],
                         [anObject substringWithRange:NSMakeRange(10, 2)]];
        } else {                                  // +# (###) ###-####
            theString = [NSString stringWithFormat:@"%@ (%@) %@-%@",
                         [anObject substringWithRange:NSMakeRange(0, 2)],
                         [anObject substringWithRange:NSMakeRange(2, 3)],
                         [anObject substringWithRange:NSMakeRange(5, 3)],
                         [anObject substringWithRange:NSMakeRange(8, 4)]];
        }
    } else {
        theString = anObject;
    }
    
    return theString;
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error {
    BOOL returnValue = NO;
    
    NSMutableCharacterSet *phoneNumberCharacterSet
        = [NSMutableCharacterSet characterSetWithCharactersInString:@"0123456789"];
    NSScanner *scanner = [NSScanner scannerWithString:string];
    NSMutableString *telephoneNumber = [[NSMutableString alloc] init];
    
    if ([string hasPrefix:@"+"]) {
        [telephoneNumber appendString:@"+"];
        [scanner setScanLocation:1];
    } else {
        // If the number is not in the international format, allow asterisk and
        // number sign.
        [phoneNumberCharacterSet addCharactersInString:@"*#"];
    }
    
    NSString *aString;
    while (![scanner isAtEnd]) {
        [scanner scanUpToCharactersFromSet:phoneNumberCharacterSet intoString:NULL];
        BOOL scanned = [scanner scanCharactersFromSet:phoneNumberCharacterSet intoString:&aString];
        if (scanned) {
            [telephoneNumber appendString:aString];
        }
    }
    
    if ([telephoneNumber length] > 0) {
        returnValue = YES;
        if (anObject != NULL) {
            *anObject = [telephoneNumber copy];
        }
    } else if (error != NULL) {
        *error = [NSString stringWithFormat:@"Couldn't convert \"%@\" to telephone number", string];
    }
    
    return returnValue;
}

- (NSString *)telephoneNumberFromString:(NSString *)string {
    NSString *telephoneNumber, *error;
    BOOL converted = [self getObjectValue:&telephoneNumber forString:string errorDescription:&error];
    if (converted) {
        return telephoneNumber;
    } else {
        NSLog(@"%@", error);
        return nil;
    }
}

@end
