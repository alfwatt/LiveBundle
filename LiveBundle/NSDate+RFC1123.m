#import "NSDate+RFC1123.h"

@implementation NSDate (NSDateRFC1123)

+ (NSDate*) dateFromRFC1123:(NSString*)value
{
    if(value == nil)
        return nil;
    static NSDateFormatter *rfc1123 = nil;
    if(rfc1123 == nil)
    {
        rfc1123 = [[NSDateFormatter alloc] init];
        rfc1123.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        rfc1123.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        rfc1123.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss z";
    }
    NSDate *ret = [rfc1123 dateFromString:value];
    if(ret != nil)
        return ret;
    
    static NSDateFormatter *rfc850 = nil;
    if(rfc850 == nil)
    {
        rfc850 = [[NSDateFormatter alloc] init];
        rfc850.locale = rfc1123.locale;
        rfc850.timeZone = rfc1123.timeZone;
        rfc850.dateFormat = @"EEEE',' dd'-'MMM'-'yy HH':'mm':'ss z";
    }
    ret = [rfc850 dateFromString:value];
    if(ret != nil)
        return ret;
    
    static NSDateFormatter *asctime = nil;
    if(asctime == nil)
    {
        asctime = [[NSDateFormatter alloc] init];
        asctime.locale = rfc1123.locale;
        asctime.timeZone = rfc1123.timeZone;
        asctime.dateFormat = @"EEE MMM d HH':'mm':'ss yyyy";
    }
    return [asctime dateFromString:value];
}

-(NSString*)rfc1123String
{
    static NSDateFormatter *df = nil;
    if(df == nil)
    {
        df = [[NSDateFormatter alloc] init];
        df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        df.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        df.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    }
    return [df stringFromDate:self];
}

@end
