#import "I2FSetTextExtractor.h"

#import "I2FDumpRvaParser.h"

@implementation I2FSetTextExtractor

+ (NSArray<NSDictionary *> *)extractEntriesAtDumpPath:(NSString *)dumpPath
                                        writeJSONFile:(BOOL)writeJSON {
    if (dumpPath.length == 0) {
        return @[];
    }
    NSArray<NSDictionary *> *entries = [I2FDumpRvaParser allSetTextEntriesInDumpDirectory:dumpPath];
    if (writeJSON) {
        NSString *jsonPath = [dumpPath stringByAppendingPathComponent:@"set_text_rvas.json"];
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:entries options:NSJSONWritingPrettyPrinted error:&error];
        if (!error && data) {
            [data writeToFile:jsonPath atomically:YES];
        }
    }
    return entries ?: @[];
}

@end
