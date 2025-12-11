#import "I2FDumpRvaParser.h"

#include <stdlib.h>

static BOOL I2FParseRvaString(NSString *rawString, unsigned long long *outValue) {
    if (!rawString) {
        return NO;
    }
    NSString *trimmed = [rawString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }
    NSString *lower = [trimmed lowercaseString];
    const char *cstr = [lower UTF8String];
    if (!cstr || cstr[0] == '\0') {
        return NO;
    }

    char *endPtr = NULL;
    unsigned long long value = 0;
    if (lower.length > 2 && [lower hasPrefix:@"0x"]) {
        value = strtoull(cstr + 2, &endPtr, 16);
    } else {
        value = strtoull(cstr, &endPtr, 10);
    }

    if (endPtr == cstr) {
        return NO;
    }
    if (outValue) {
        *outValue = value;
    }
    return YES;
}

@implementation I2FDumpRvaParser

+ (nullable NSString *)firstSetTextRvaStringInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return nil;
    }
    NSString *dumpPath = [dumpDirectory stringByAppendingPathComponent:@"dump.cs"];
    NSData *data = [NSData dataWithContentsOfFile:dumpPath];
    if (!data) {
        return nil;
    }
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (content.length == 0) {
        return nil;
    }
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSRegularExpression *setTextRegex = [NSRegularExpression regularExpressionWithPattern:@"set_Text\\s*\\(" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *rvaRegex = [NSRegularExpression regularExpressionWithPattern:@"RVA:\\s*(0x[0-9a-fA-F]+|\\d+)" options:0 error:nil];

    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *prev = lines[i - 1];
        NSString *line = lines[i];
        if ([setTextRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] == 0) {
            continue;
        }
        NSTextCheckingResult *rvaMatch = [rvaRegex firstMatchInString:prev options:0 range:NSMakeRange(0, prev.length)];
        if (!rvaMatch || rvaMatch.numberOfRanges < 2) {
            continue;
        }
        NSRange valueRange = [rvaMatch rangeAtIndex:1];
        if (valueRange.location == NSNotFound || valueRange.length == 0) {
            continue;
        }
        NSString *raw = [prev substringWithRange:valueRange];
        unsigned long long numeric = 0;
        if (!I2FParseRvaString(raw, &numeric)) {
            continue;
        }
        return [NSString stringWithFormat:@"0x%llx", numeric];
    }
    return nil;
}

+ (NSArray<NSString *> *)allSetTextRvaStringsInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return @[];
    }
    NSString *dumpPath = [dumpDirectory stringByAppendingPathComponent:@"dump.cs"];
    NSData *data = [NSData dataWithContentsOfFile:dumpPath];
    if (!data) {
        return @[];
    }
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (content.length == 0) {
        return @[];
    }
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSRegularExpression *setTextRegex = [NSRegularExpression regularExpressionWithPattern:@"set_Text\\s*\\(" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *rvaRegex = [NSRegularExpression regularExpressionWithPattern:@"RVA:\\s*(0x[0-9a-fA-F]+|\\d+)" options:0 error:nil];

    NSMutableOrderedSet<NSString *> *results = [NSMutableOrderedSet orderedSet];

    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *prev = lines[i - 1];
        NSString *line = lines[i];
        if ([setTextRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] == 0) {
            continue;
        }
        NSTextCheckingResult *rvaMatch = [rvaRegex firstMatchInString:prev options:0 range:NSMakeRange(0, prev.length)];
        if (!rvaMatch || rvaMatch.numberOfRanges < 2) {
            continue;
        }
        NSRange valueRange = [rvaMatch rangeAtIndex:1];
        if (valueRange.location == NSNotFound || valueRange.length == 0) {
            continue;
        }
        NSString *raw = [prev substringWithRange:valueRange];
        unsigned long long numeric = 0;
        if (!I2FParseRvaString(raw, &numeric)) {
            continue;
        }
        NSString *normalized = [NSString stringWithFormat:@"0x%llx", numeric];
        [results addObject:normalized];
    }
    return results.array;
}

@end
