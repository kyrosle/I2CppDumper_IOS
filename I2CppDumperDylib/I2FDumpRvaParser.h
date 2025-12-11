#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 解析 set_Text 的 RVA，优先读取 dump 目录下的 set_text_rvas.json，若不存在则回退到 dump.cs 注释。
@interface I2FDumpRvaParser : NSObject

/// 从指定 dump 目录下的 dump.cs 中解析首个 set_Text 的 RVA，返回十六进制字符串（如 0x1234）。
+ (nullable NSString *)firstSetTextRvaStringInDumpDirectory:(NSString *)dumpDirectory;

/// 从 dump.cs 中解析所有 set_Text 的 RVA，返回去重后的十六进制字符串数组。
+ (NSArray<NSString *> *)allSetTextRvaStringsInDumpDirectory:(NSString *)dumpDirectory;

/// 返回包含 name（可选）和 rva（十六进制字符串）的 set_Text 条目数组，优先读取 set_text_rvas.json。
+ (NSArray<NSDictionary *> *)allSetTextEntriesInDumpDirectory:(NSString *)dumpDirectory;

@end

NS_ASSUME_NONNULL_END
