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

static NSArray<NSDictionary *> *I2FParseSetTextJson(NSString *dumpDirectory) {
    NSString *jsonPath = [dumpDirectory stringByAppendingPathComponent:@"set_text_rvas.json"];
    NSData *data = [NSData dataWithContentsOfFile:jsonPath];
    if (!data) {
        return nil;
    }

    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![obj isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSArray *arr = (NSArray *)obj;
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    for (id item in arr) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = (NSDictionary *)item;
        id rvaObj = [dict objectForKey:@"rva"];
        unsigned long long numeric = 0;
        if ([rvaObj isKindOfClass:[NSString class]]) {
            if (!I2FParseRvaString((NSString *)rvaObj, &numeric)) {
                continue;
            }
        } else if ([rvaObj isKindOfClass:[NSNumber class]]) {
            numeric = [(NSNumber *)rvaObj unsignedLongLongValue];
        } else {
            continue;
        }
        NSString *normalized = [NSString stringWithFormat:@"0x%llx", numeric];
        NSString *name = nil;
        id nameObj = [dict objectForKey:@"name"];
        if ([nameObj isKindOfClass:[NSString class]]) {
            name = (NSString *)nameObj;
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"rva"] = normalized;
        if (name.length > 0) {
            entry[@"name"] = name;
        }
        [results addObject:entry];
    }
    return results;
}

@implementation I2FDumpRvaParser

+ (nullable NSString *)firstSetTextRvaStringInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return nil;
    }
    NSArray<NSString *> *all = [self allSetTextRvaStringsInDumpDirectory:dumpDirectory];
    return all.firstObject;
}

+ (NSArray<NSString *> *)allSetTextRvaStringsInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return @[];
    }

    // 优先使用结构化的 JSON 文件。
    NSArray<NSDictionary *> *jsonEntries = I2FParseSetTextJson(dumpDirectory);
    if (jsonEntries.count > 0) {
        NSMutableArray<NSString *> *rvas = [NSMutableArray arrayWithCapacity:jsonEntries.count];
        for (NSDictionary *entry in jsonEntries) {
            NSString *rva = entry[@"rva"];
            if (rva.length > 0) {
                [rvas addObject:rva];
            }
        }
        return rvas;
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

+ (NSArray<NSDictionary *> *)allSetTextEntriesInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return @[];
    }

    // 优先 JSON。
    NSArray<NSDictionary *> *jsonEntries = I2FParseSetTextJson(dumpDirectory);
    if (jsonEntries.count > 0) {
        return jsonEntries;
    }

    // 回退 dump.cs，只能提供 rva，没有精确的 namespace/class 信息。
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSArray<NSString *> *rvas = [self allSetTextRvaStringsInDumpDirectory:dumpDirectory];
    for (NSString *rva in rvas) {
        if (rva.length == 0) continue;
        [entries addObject:@{ @"rva": rva }];
    }
    return entries;
}

@end
