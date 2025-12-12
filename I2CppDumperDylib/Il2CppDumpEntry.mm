//
//  Il2CppDumpEntry.mm
//  I2CppDumperDylib
//

#import <Foundation/Foundation.h>

#import "includes/SSZipArchive/SSZipArchive.h"
#import "AlertUtils.h"

#include "Core/config.h"
#include "Core/Il2cpp.hpp"
#include "Core/Dumper.hpp"

#import "I2FConfigManager.h"
#import "I2FDumpRvaParser.h"
#import "I2FSetTextExtractor.h"
#import "I2FIl2CppTextHookManager.h"

static dispatch_once_t gIl2cppAttachOnce;
static dispatch_queue_t gIl2cppWorkerQueue;

extern "C" unsigned long long I2FCurrentIl2CppBaseAddress(void) {
    return (unsigned long long)Variables::info.address;
}

static void I2FAttachIl2cppIfNeeded(void) {
    dispatch_once(&gIl2cppAttachOnce, ^{
        NSString *appPath = [[NSBundle mainBundle] bundlePath];
        NSString *binaryPath = [NSString stringWithUTF8String:BINARY_NAME];
        if ([binaryPath isEqualToString:@"UnityFramework"]) {
            binaryPath = [appPath stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
        } else {
            binaryPath = [appPath stringByAppendingPathComponent:binaryPath];
        }
        Variables::IL2CPP::processAttach(binaryPath.UTF8String);
    });
}

static BOOL I2FWaitIl2cppReady(NSUInteger retryCount, NSTimeInterval interval) {
    for (NSUInteger i = 0; i < retryCount; i++) {
        if (Variables::IL2CPP::il2cpp_domain_get && Variables::IL2CPP::il2cpp_domain_get_assemblies) {
            void *domain = Variables::IL2CPP::il2cpp_domain_get();
            if (domain) {
                size_t count = 0;
                Variables::IL2CPP::il2cpp_domain_get_assemblies(domain, &count);
                if (count > 0) {
                    return YES;
                }
            }
        }
        [NSThread sleepForTimeInterval:interval];
    }
    return NO;
}

static void I2FHandlePreviousHookCrashMarker(void) {
    NSDictionary *lastEntry = [I2FConfigManager lastInstallingHookEntry];
    if (!lastEntry) {
        return;
    }
    NSString *name = lastEntry[@"name"];
    if (name.length == 0) {
        [I2FConfigManager setLastInstallingHookEntry:nil];
        return;
    }

    NSMutableArray<NSDictionary *> *entries = [[I2FConfigManager setTextHookEntries] mutableCopy];
    BOOL changed = NO;
    for (NSUInteger i = 0; i < entries.count; i++) {
        NSDictionary *entry = entries[i];
        if ([name isEqualToString:entry[@"name"]]) {
            NSMutableDictionary *m = [entry mutableCopy];
            m[@"enabled"] = @NO;
            entries[i] = [m copy];
            changed = YES;
        }
    }
    if (changed) {
        [I2FConfigManager setSetTextHookEntries:entries];
        showInfo([NSString stringWithFormat:@"上次安装 hook 可能崩溃，已禁用 %@", name], 2.0f);
    }
    [I2FConfigManager setLastInstallingHookEntry:nil];
}

static void I2FInstallSetTextHooksFromConfig(void) {
    if (![I2FConfigManager autoInstallHookOnLaunch] && ![I2FConfigManager autoInstallHookAfterDump]) {
        return;
    }

    NSArray<NSDictionary *> *entries = [I2FConfigManager setTextHookEntries];
    NSMutableArray<NSDictionary *> *enabledEntries = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        BOOL enabled = YES;
        id enabledObj = entry[@"enabled"];
        if ([enabledObj respondsToSelector:@selector(boolValue)]) {
            enabled = [enabledObj boolValue];
        }
        if (enabled) {
            [enabledEntries addObject:entry];
        }
    }

    if (enabledEntries.count == 0) {
        return;
    }
    [I2FIl2CppTextHookManager installHooksWithEntries:enabledEntries];
}

static BOOL I2FPerformDump(NSString *dumpPath,
                           NSString *headersDumpPath,
                           NSString *zipDumpPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:dumpPath]) {
        [fileManager removeItemAtPath:dumpPath error:nil];
    }
    if ([fileManager fileExistsAtPath:zipDumpPath]) {
        [fileManager removeItemAtPath:zipDumpPath error:nil];
    }

    NSError *error = nil;
    if (![fileManager createDirectoryAtPath:headersDumpPath
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error]) {
        NSLog(@"[I2CppDumper] Failed to create folders. Error: %@", error);
        showError([NSString stringWithFormat:@"Failed to create folders.\nError: %@", error]);
        return NO;
    }

    SCLAlertView *waitingAlert = nil;
    showWaiting(@"Dumping...", &waitingAlert);

    Dumper::DumpStatus dumpStatus = Dumper::dump(dumpPath.UTF8String, headersDumpPath.UTF8String);

    if ([fileManager fileExistsAtPath:zipDumpPath]) {
        [fileManager removeItemAtPath:zipDumpPath error:nil];
    }
    [SSZipArchive createZipFileAtPath:zipDumpPath withContentsOfDirectory:dumpPath];
    dismisWaiting(waitingAlert);

    if (dumpStatus != Dumper::DumpStatus::SUCCESS) {
        showError(@"Error while dumping, check logs.txt");
        return NO;
    }

    [I2FConfigManager setLastDumpDirectory:dumpPath];
    [I2FConfigManager setHasDumpedOnce:YES];

    NSArray<NSDictionary *> *entries = [I2FSetTextExtractor extractEntriesAtDumpPath:dumpPath writeJSONFile:YES];
    if (entries.count > 0) {
        [I2FConfigManager setSetTextHookEntries:entries];
    } else {
        [I2FConfigManager setSetTextHookEntries:@[]];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        showSuccess([NSString stringWithFormat:@"Dump at: \n%@\nFolder: %@", zipDumpPath, dumpPath]);
    });

    return YES;
}

static BOOL I2FRunDumpSequence(void) {
    showInfo([NSString stringWithFormat:@"Dumping after %d seconds.", WAIT_TIME_SEC], WAIT_TIME_SEC / 2.0f);
    sleep(WAIT_TIME_SEC);

    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey];
    NSString *dumpFolderName = [NSString stringWithFormat:@"%@_%s",
                                [appName stringByReplacingOccurrencesOfString:@" " withString:@""],
                                DUMP_FOLDER];

    NSString *dumpPath = [docDir stringByAppendingPathComponent:dumpFolderName];
    NSString *headersDumpPath = [dumpPath stringByAppendingPathComponent:@"Assembly"];
    NSString *zipDumpPath = [dumpPath stringByAppendingString:@".zip"];

    if (!I2FWaitIl2cppReady(50, 0.1)) {
        NSLog(@"[I2CppDumper] Dump worker skip: IL2CPP not ready.");
        return NO;
    }

    if (Dumper::status != Dumper::DumpStatus::SUCCESS) {
        if (Dumper::status == Dumper::DumpStatus::ERROR_FRAMEWORK) {
            showError(@"Error while dumping, error framework");
            return NO;
        }
        if (Dumper::status == Dumper::DumpStatus::ERROR_SYMBOLS) {
            showError(@"Error while dumping, error symbols");
            return NO;
        }
    }

    NSLog(@"[I2CppDumper] UNITY_PATH: %@", dumpPath);

    BOOL ok = I2FPerformDump(dumpPath, headersDumpPath, zipDumpPath);
    if (ok) {
        NSLog(@"[I2CppDumper] Dump finished.");
    }
    return ok;
}

extern "C" void StartIl2CppDumpThread(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gIl2cppWorkerQueue = dispatch_queue_create("com.i2cpp.worker", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(gIl2cppWorkerQueue, ^{
        NSLog(@"[I2CppDumper] ========= START IL2CPP WORKER =========");

        I2FAttachIl2cppIfNeeded();

        BOOL shouldDump = [I2FConfigManager autoDumpEnabled] || ![I2FConfigManager hasDumpedOnce];
        BOOL didDump = NO;

        // 处理崩溃标记。
        I2FHandlePreviousHookCrashMarker();

        // 预装 hook（启动时）。
        if ([I2FConfigManager autoInstallHookOnLaunch]) {
            if (!I2FWaitIl2cppReady(50, 0.1)) {
                NSLog(@"[I2CppDumper] Hook install skipped (IL2CPP not ready).");
            } else {
                NSLog(@"[I2CppDumper] Hook install start.");
                I2FInstallSetTextHooksFromConfig();
                NSLog(@"[I2CppDumper] Hook install end.");
            }
        }

        // Dump（可选）。
        if (shouldDump) {
            didDump = I2FRunDumpSequence();
        } else {
            NSLog(@"[I2CppDumper] skip dump (already dumped and autoDump disabled).");
        }

        // Dump 完成后按需安装 hook（仅当本轮执行了 dump）。
        if (didDump && [I2FConfigManager autoInstallHookAfterDump]) {
            if (!I2FWaitIl2cppReady(50, 0.1)) {
                NSLog(@"[I2CppDumper] After-dump hook install skipped (IL2CPP not ready).");
            } else {
                NSLog(@"[I2CppDumper] Hook install start.");
                I2FInstallSetTextHooksFromConfig();
                NSLog(@"[I2CppDumper] Hook install end.");
            }
        }

        NSLog(@"[I2CppDumper] ========= END IL2CPP WORKER =========");
    });
}
