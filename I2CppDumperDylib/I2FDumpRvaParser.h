#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 解析 set_Text 的元信息，优先读取 dump 目录下的 set_text_rvas.json。
@interface I2FDumpRvaParser : NSObject

/// 返回包含 name（必选）和 rva（可选，十六进制字符串）的 set_Text 条目数组。
+ (NSArray<NSDictionary *> *)allSetTextEntriesInDumpDirectory:(NSString *)dumpDirectory;

@end

NS_ASSUME_NONNULL_END
