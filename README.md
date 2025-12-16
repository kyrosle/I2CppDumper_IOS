# I2CppDumper

MonkeyDev host app plus an injected dylib that dumps Unity IL2CPP (`UnityFramework` by default), generates `dump.cs`/headers, and can auto-install `set_Text` hooks. An in-app floating ball opens a control panel for toggles and live text logs.

[中文](README_CN.md)

## Highlights
- Automated dump: waits for IL2CPP to be ready and ~10s delay, then produces `<AppName>_UNITYDUMP` and a zip with `dump.cs`, `Assembly/` headers, and `set_text_rvas.json`.
- `set_Text` harvesting: parses dump.cs/JSON to build hook entries, then installs by writing the method pointer slot at `base + rva` (no MemberInfo offsets needed). Falls back to name resolution if no RVA is present and records intercepted strings into an in-app log.
- Control panel: tap the “I2F” floating ball to toggle auto dump/auto hook/post-dump hook, re-parse the latest dump, clear hooks or logs, and view hook list plus captured text.
- Crash guard: if installing a hook caused a crash last time, the entry is auto-disabled on next launch.
- Debug helpers: Cycript server on port 6666 in debug builds; includes AntiAntiDebug, fishhook, and MethodTrace utilities.

## Repository Layout
- `I2CppDumper/`: MonkeyDev host project; `Config/MDConfig.plist` for target app settings; `TargetApp/` for decrypted `.app`/IPA contents; `Scripts/quick-resign.sh` resign helper.
- `I2CppDumperDylib/`: injected logic; `Core/` implements the IL2CPP dumper; `includes/` bundles SSZipArchive, MISFloatingBall, SDAutoLayout, etc.; `Trace/`, `AntiAntiDebug/`, `fishhook/` tools; `Il2CppDumpEntry.mm` is the dump/hook entry; `I2F*` files handle UI, config, and logging.
- `LatestBuild/`: Xcode/MonkeyDev outputs (IPA and helper scripts).

## Prerequisites
- MonkeyDev installed and able to build/sign to a real device.
- Place the decrypted target app inside `I2CppDumper/TargetApp/`, or configure acquisition in `MDConfig.plist`.
- To change the IL2CPP binary name or delay, edit `I2CppDumperDylib/Core/config.h` (`UnityFramework` and 10s by default).

## Quick Start (Xcode)
1. Open `I2CppDumper.xcodeproj`, pick the MonkeyDev scheme and your device.
2. Ensure signing settings and `MDConfig.plist` match the target; verify `TargetApp/` contains the app.
3. Press `⌘R`: MonkeyDev resigns and installs, then dumps/installs `set_Text` hooks according to the toggles.
4. Inside the app, tap the “I2F” floating ball to view the control panel, text log, and hook list.

## Fast Re-sign
Run inside `I2CppDumper/Scripts`:

```bash
./quick-resign.sh [insert] /abs/path/origin.ipa /abs/path/output/Target.ipa
```

- Use `insert` to inject the dylib; omit it to just resign.
- The resulting IPA is also placed at `LatestBuild/Target.ipa`.

## Dump & Hook Flow
- On first run or when auto dump is on, a worker waits ~10s and for the IL2CPP domain, then starts the dump.
- Output lives in `Documents/<AppName>_UNITYDUMP/` plus `<AppName>_UNITYDUMP.zip`; `set_text_rvas.json` stores matched `set_Text` RVAs/signatures for later installs.
- With auto install enabled (default), entries are saved to `NSUserDefaults` and hooked on launch or after dump by writing the function pointer slot at `base + rva` from the dump; intercepted text streams into the panel log. You can still provide manual `slot_offset`/`orig_offset` entries for special cases.
- “Re-parse dump.cs” rebuilds the hook list from the latest dump and tries to install, useful after a fresh dump.

## Validation & Troubleshooting
- No unit tests; verify on-device: check `Documents/<AppName>_UNITYDUMP` exists and the panel shows captured text.
- If dumping fails, inspect `logs.txt` on device or Xcode console; ensure the target is an IL2CPP/Unity app and decrypted.
