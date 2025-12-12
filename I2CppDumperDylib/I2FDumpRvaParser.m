#import "I2FDumpRvaParser.h"

#include <stdlib.h>

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
        [results addObject:entry];
    }
    return results;
}

@implementation I2FDumpRvaParser

+ (NSArray<NSDictionary *> *)allSetTextEntriesInDumpDirectory:(NSString *)dumpDirectory {
    if (dumpDirectory.length == 0) {
        return @[];
    }

    NSArray<NSDictionary *> *jsonEntries = I2FParseSetTextJson(dumpDirectory);
    return jsonEntries ?: @[];
}

@end
