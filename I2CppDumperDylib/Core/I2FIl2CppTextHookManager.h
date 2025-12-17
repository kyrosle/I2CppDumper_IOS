#import <Foundation/Foundation.h>

#import "I2FIl2CppTextHookTypes.h"

NS_ASSUME_NONNULL_BEGIN

/// 按名称解析并安装 Unity Text.set_text hook，支持基于 MethodInfo 或 base+offset 的指针替换。
@interface I2FIl2CppTextHookManager : NSObject

/// 使用带 name 的条目安装 hook，entry 需包含 @"name"。
+ (void)installHooksWithEntries:(NSArray<NSDictionary *> *)entries;

/// 卸载指定名称对应的 hook。
+ (void)uninstallHooksWithEntries:(NSArray<NSDictionary *> *)entries;

/// 调整文本处理流水线（日志、翻译、字体）开关。
+ (void)setPipelineOptions:(I2FTextHookPipelineOptions)options;
+ (I2FTextHookPipelineOptions)pipelineOptions;

@end

NS_ASSUME_NONNULL_END
