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

/// set_Text hook 条目（字典，包含 name，name 形如 Namespace.Class.set_Text）。
+ (NSArray<NSDictionary *> *)setTextHookEntries;
/// 存储 set_Text hook 条目。
+ (void)setSetTextHookEntries:(NSArray<NSDictionary *> *)entries;

/// 上一次正在安装的 hook 条目（用于崩溃检测）。
+ (nullable NSDictionary *)lastInstallingHookEntry;
+ (void)setLastInstallingHookEntry:(nullable NSDictionary *)entry;

@end

NS_ASSUME_NONNULL_END
