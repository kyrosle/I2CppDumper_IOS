# I2CppDumper

MonkeyDev 宿主 + 注入动态库，用于自动 dump Unity IL2CPP（默认二进制 `UnityFramework`）、生成 `dump.cs`/头文件并可自动安装 set_Text hook，内置浮动球控制面板便于查看和调试。

[English](README.md)

## 功能特点
- 自动 dump：启动后等待 IL2CPP 就绪并延迟约 10 秒，生成 `<AppName>_UNITYDUMP` 文件夹和同名 zip，包含 `dump.cs`、`Assembly/` 头文件、`set_text_rvas.json`。
- set_Text 收集：解析 dump.cs/JSON 生成 hook 列表，可在启动或 dump 完成后自动安装，截获文本写入内置日志。
- 控制面板：点击屏幕右侧 “I2F” 浮动球切换自动 dump/自动 hook/ dump 后自动 hook，可重新解析 dump、清空 hook 或日志，并查看当前 hook 与文本记录。
- 崩溃防护：如果上次安装 hook 崩溃，会自动禁用对应条目并提示。
- 调试辅助：调试构建下开启 Cycript（6666 端口）；附带 AntiAntiDebug、fishhook、MethodTrace 等工具代码。

## 目录结构
- `I2CppDumper/`：MonkeyDev 宿主工程；`Config/MDConfig.plist` 配置目标 App；`TargetApp/` 放置解密 `.app`/IPA 内容；`Scripts/quick-resign.sh` 重新签名脚本。
- `I2CppDumperDylib/`：注入逻辑；`Core/` 为 IL2CPP dumper；`includes/` 集成 SSZipArchive、MISFloatingBall、SDAutoLayout 等；`Trace/`、`AntiAntiDebug/`、`fishhook/` 工具；`Il2CppDumpEntry.mm` 为 dump 与 hook 主流程；`I2F*` 前缀文件实现 UI、配置与日志。
- `LatestBuild/`：Xcode/MonkeyDev 构建输出（IPA 与辅助脚本）。

## 环境与准备
- 已安装 MonkeyDev，能在真机上构建并签名。
- 将解密后的目标 App 放入 `I2CppDumper/TargetApp/`，或在 `MDConfig.plist` 中配置下载/安装方式。
- 若需调整 IL2CPP 二进制名称或等待时间，可编辑 `I2CppDumperDylib/Core/config.h`（默认二进制 `UnityFramework`，等待 10 秒）。

## 快速开始（Xcode）
1. 打开 `I2CppDumper.xcodeproj`，选择 MonkeyDev scheme 和目标设备。
2. 确保证书与 `MDConfig.plist` 配置正确，`TargetApp/` 下已有目标 App。
3. `⌘R` 运行：MonkeyDev 会重签宿主并安装到设备，按配置自动 dump/安装 set_Text hook。
4. 在 App 内点击 “I2F” 浮动球查看控制面板、文本日志与 hook 列表。

## 快速重新签名
在 `I2CppDumper/Scripts` 目录执行：

```bash
./quick-resign.sh [insert] /abs/path/origin.ipa /abs/path/output/Target.ipa
```

- 加 `insert` 参数会将 dylib 注入；不加则仅重签。
- 输出 IPA 同时保存在 `LatestBuild/Target.ipa`。

## dump 与 hook 流程
- 首次运行或开启自动 dump 时，线程会等待约 10 秒并确认 IL2CPP 域可用后开始 dump。
- 结果保存在沙盒 `Documents/<AppName>_UNITYDUMP/`，并生成 `<AppName>_UNITYDUMP.zip`；`set_text_rvas.json` 存储匹配到的 set_Text RVA/签名，供后续自动安装。
- 若启用自动安装 hook（默认开启），会在启动或 dump 后写入 NSUserDefaults 并安装；截获文本实时写入控制面板日志。
- “重新解析 dump.cs” 会使用最新 dump 重新生成 hook 列表并尝试安装，便于更新。

## 验证与排错
- 项目无单元测试；请在真机上验证：确认 `Documents/<AppName>_UNITYDUMP` 存在、控制面板能看到日志。
- dump 失败可检查设备上生成的 `logs.txt` 或 Xcode 控制台；确保目标为 IL2CPP/Unity 应用且已解密。
