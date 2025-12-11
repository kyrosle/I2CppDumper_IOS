#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 配置管理：控制是否自动 dump 以及是否已经成功 dump 过一次。
@interface I2FConfigManager : NSObject

/// 是否在启动时自动执行 dump（默认 YES）。
+ (BOOL)autoDumpEnabled;
/// 设置是否在启动时自动执行 dump。
+ (void)setAutoDumpEnabled:(BOOL)enabled;

/// 当前安装周期是否已经成功 dump 过一次。
+ (BOOL)hasDumpedOnce;
/// 设置当前安装周期是否已经成功 dump 过一次。
+ (void)setHasDumpedOnce:(BOOL)done;

/// 重置 dump 状态相关标记。
+ (void)resetDumpFlags;

/// 是否在启动后自动安装基于 RVA 的 set_Text hook（默认 YES）。
+ (BOOL)autoInstallHookOnLaunch;
/// 设置启动后是否自动安装 set_Text hook。
+ (void)setAutoInstallHookOnLaunch:(BOOL)enabled;

/// 是否在 dump 成功后自动安装最新的 set_Text hook（默认 YES）。
+ (BOOL)autoInstallHookAfterDump;
/// 设置 dump 成功后是否自动安装 set_Text hook。
+ (void)setAutoInstallHookAfterDump:(BOOL)enabled;

/// 最近一次 dump 生成的目录路径。
+ (nullable NSString *)lastDumpDirectory;
/// 记录最近一次 dump 生成的目录路径。
+ (void)setLastDumpDirectory:(nullable NSString *)path;

/// 解析到的所有 set_Text RVA（去重后的十六进制字符串，如 0x1234）。
+ (NSArray<NSString *> *)setTextRvaStrings;
/// 存储解析到的 set_Text RVA 列表。
+ (void)setSetTextRvaStrings:(NSArray<NSString *> *)rvas;

/// set_Text hook 条目（字典，包含 name 可选、rva 必填，rva 为十六进制字符串如 0x1234）。
+ (NSArray<NSDictionary *> *)setTextHookEntries;
/// 存储 set_Text hook 条目。
+ (void)setSetTextHookEntries:(NSArray<NSDictionary *> *)entries;

/// 首选的 set_Text RVA 字符串（通常是列表第一个）。
+ (nullable NSString *)primarySetTextRvaString;
/// 设置首选的 set_Text RVA 字符串。
+ (void)setPrimarySetTextRvaString:(nullable NSString *)rva;

@end

NS_ASSUME_NONNULL_END
