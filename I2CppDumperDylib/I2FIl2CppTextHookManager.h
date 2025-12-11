#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装基于 RVA 的 Unity Text.set_text hook。
@interface I2FIl2CppTextHookManager : NSObject

/// 使用基址和单个 RVA 字符串安装 hook（便捷调用，会转到多 RVA 接口）。
+ (void)installHookWithBaseAddress:(unsigned long long)baseAddress
                        rvaString:(nullable NSString *)rvaString;

/// 使用基址和多个 RVA 字符串安装 hook，会对每个 RVA 对应的地址做 inline hook。
+ (void)installHooksWithBaseAddress:(unsigned long long)baseAddress
                         rvaStrings:(NSArray<NSString *> *)rvaStrings;

/// 使用基址和带 name 的条目安装 hook，entry 包含 @"rva" 必填（十六进制字符串），@"name" 可选。
+ (void)installHooksWithBaseAddress:(unsigned long long)baseAddress
                            entries:(NSArray<NSDictionary *> *)entries;

@end

NS_ASSUME_NONNULL_END
