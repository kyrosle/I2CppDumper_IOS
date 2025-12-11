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

@end

NS_ASSUME_NONNULL_END

