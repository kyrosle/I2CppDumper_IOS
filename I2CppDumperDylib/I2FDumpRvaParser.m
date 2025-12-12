#import "I2FDumpRvaParser.h"

#include <stdlib.h>

static NSString *I2FNormalizeRvaString(NSString *rawString) {
    if (rawString.length == 0) {
        return nil;
    }
    NSString *trimmed = [rawString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = [trimmed lowercaseString];
    const char *cstr = [lower UTF8String];
    if (!cstr || cstr[0] == '\0') {
        return nil;
    }

    char *endPtr = NULL;
    unsigned long long value = 0;
    if (lower.length > 2 && [lower hasPrefix:@"0x"]) {
        value = strtoull(cstr + 2, &endPtr, 16);
    } else {
        value = strtoull(cstr, &endPtr, 10);
    }
    if (endPtr == cstr || value == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"0x%llx", value];
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
        NSString *name = nil;
        id nameObj = [dict objectForKey:@"name"];
        if ([nameObj isKindOfClass:[NSString class]]) {
            name = (NSString *)nameObj;
        }
        if (name.length == 0) {
            continue;
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"name"] = name;
        id rvaObj = [dict objectForKey:@"rva"];
        if ([rvaObj isKindOfClass:[NSString class]]) {
            entry[@"rva"] = rvaObj;
        } else if ([rvaObj respondsToSelector:@selector(stringValue)]) {
            entry[@"rva"] = [rvaObj stringValue];
        }
        id sigObj = [dict objectForKey:@"signature"];
        if ([sigObj isKindOfClass:[NSString class]] && [sigObj length] > 0) {
            entry[@"signature"] = sigObj;
        }
        // 尝试推导 namespace/class/method 三段，便于 UI 展示或后续校验。
        NSArray<NSString *> *parts = [name componentsSeparatedByString:@"."];
        if (parts.count >= 2) {
            entry[@"class"] = parts[parts.count - 2];
            entry[@"method"] = parts.lastObject;
            if (parts.count >= 3) {
                NSRange nsRange = NSMakeRange(0, parts.count - 2);
                entry[@"namespace"] = [[parts subarrayWithRange:nsRange] componentsJoinedByString:@"."];
            }
        }
        [results addObject:entry];
    }
    return results;
}

static NSArray<NSDictionary *> *I2FFilterEntries(NSArray<NSDictionary *> *entries) {
    if (entries.count == 0) {
        return entries;
    }
    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in entries) {
        NSString *name = entry[@"name"];
        if (name.length == 0) {
            continue;
        }
        if ([name hasPrefix:@"System."]) {
            continue;
        }
        if ([seen containsObject:name]) {
            continue;
        }
        [seen addObject:name];
        [filtered addObject:entry];
    }
    return filtered;
}

// 解析 dump.cs：提取当前 namespace/class，并匹配 set_text 方法行，抓取前一行 RVA。
static NSArray<NSDictionary *> *I2FParseSetTextFromDumpCS(NSString *dumpDirectory) {
    NSString *dumpPath = [dumpDirectory stringByAppendingPathComponent:@"dump.cs"];
    NSData *data = [NSData dataWithContentsOfFile:dumpPath];
    if (!data) {
        return @[];
    }
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (content.length == 0) {
        return @[];
    }

    NSRegularExpression *nsRegex = [NSRegularExpression regularExpressionWithPattern:@"//\\s*Namespace:\\s*(.+)" options:0 error:nil];
    NSRegularExpression *classRegex = [NSRegularExpression regularExpressionWithPattern:@"\\b(class|struct|interface|enum)\\s+([A-Za-z0-9_`]+)" options:0 error:nil];
    NSRegularExpression *rvaRegex = [NSRegularExpression regularExpressionWithPattern:@"RVA:\\s*(0x[0-9a-fA-F]+|\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSRegularExpression *methodRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*public\\b(?!.*\\bvirtual\\b).*?\\bVoid\\s+(set_text|set_Text)\\s*\\(\\s*(?<!\\.)String\\s+\\w+\\s*\\)\\s*\\{?" options:NSRegularExpressionCaseInsensitive error:nil];

    NSMutableOrderedSet<NSDictionary *> *results = [NSMutableOrderedSet orderedSet];
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    NSString *currentNamespace = @"";
    NSString *currentClass = @"";
    NSString *lastRva = nil;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];

        NSTextCheckingResult *nsMatch = [nsRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (nsMatch.numberOfRanges >= 2) {
            currentNamespace = [line substringWithRange:[nsMatch rangeAtIndex:1]];
            continue;
        }

        NSTextCheckingResult *classMatch = [classRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (classMatch.numberOfRanges >= 3) {
            NSString *rawClass = [line substringWithRange:[classMatch rangeAtIndex:2]];
            // 去掉泛型后缀 `1 等
            NSArray<NSString *> *parts = [rawClass componentsSeparatedByString:@"`"];
            currentClass = parts.firstObject ?: rawClass;
            continue;
        }

        NSTextCheckingResult *rvaMatch = [rvaRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (rvaMatch.numberOfRanges >= 2) {
            NSString *raw = [line substringWithRange:[rvaMatch rangeAtIndex:1]];
            lastRva = I2FNormalizeRvaString(raw);
            continue;
        }

        NSTextCheckingResult *methodMatch = [methodRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (methodMatch.numberOfRanges >= 2) {
            NSString *methodName = [line substringWithRange:[methodMatch rangeAtIndex:1]];
            NSString *fullName = nil;
            if (currentNamespace.length > 0) {
                fullName = [NSString stringWithFormat:@"%@.%@.%@", currentNamespace, currentClass, methodName];
            } else {
                fullName = [NSString stringWithFormat:@"%@.%@", currentClass, methodName];
            }
            if (fullName.length == 0) {
                continue;
            }
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = fullName;
            if (lastRva.length > 0) {
                entry[@"rva"] = lastRva;
            }
            NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmedLine.length > 0) {
                entry[@"signature"] = trimmedLine;
            }
            [results addObject:entry];
        }
    }
    return results.array;
}

@implementation I2FDumpRvaParser

+ (NSArray<NSDictionary *> *)allSetTextEntriesInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return @[];
    }

    // 优先使用 dump.cs 严格解析（过滤 virtual，匹配 String 单参）。
    NSArray<NSDictionary *> *csEntries = I2FParseSetTextFromDumpCS(dumpDirectory);
    if (csEntries.count > 0) {
        return I2FFilterEntries(csEntries);
    }
    // 回退 JSON（可能包含 virtual/其它签名，但仍过滤 System.* 和去重）。
    return I2FFilterEntries(I2FParseSetTextJson(dumpDirectory) ?: @[]);
}

@end
