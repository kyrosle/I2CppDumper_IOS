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
#import "I2FIl2CppTextHookManager.h"

extern "C" unsigned long long I2FCurrentIl2CppBaseAddress(void) {
    return (unsigned long long)Variables::info.address;
}

static void dump_thread(void) {
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

    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    NSString *binaryPath = [NSString stringWithUTF8String:BINARY_NAME];
    if ([binaryPath isEqualToString:@"UnityFramework"]) {
        binaryPath = [appPath stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
    } else {
        binaryPath = [appPath stringByAppendingPathComponent:binaryPath];
    }

    Variables::IL2CPP::processAttach(binaryPath.UTF8String);

    if (Dumper::status != Dumper::DumpStatus::SUCCESS) {
        if (Dumper::status == Dumper::DumpStatus::ERROR_FRAMEWORK) {
            showError(@"Error while dumping, error framework");
            return;
        }
        if (Dumper::status == Dumper::DumpStatus::ERROR_SYMBOLS) {
            showError(@"Error while dumping, error symbols");
            return;
        }
    }

    // 安装 set_Text hook（使用之前从 dump.cs 解析得到的 RVA，如果有的话）。
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *storedRvas = [defaults arrayForKey:@"I2F.SetTextRvaStrings"];
    NSString *storedRva = [defaults stringForKey:@"I2F.SetTextRvaString"];
    if (storedRvas.count > 0) {
        [I2FIl2CppTextHookManager installHooksWithBaseAddress:(unsigned long long)Variables::info.address
                                                   rvaStrings:storedRvas];
    } else if (storedRva.length > 0) {
        [I2FIl2CppTextHookManager installHookWithBaseAddress:(unsigned long long)Variables::info.address
                                                   rvaString:storedRva];
    }

    NSLog(@"[I2CppDumper] UNITY_PATH: %@", dumpPath);

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
        return;
    }

    BOOL shouldDump = [I2FConfigManager autoDumpEnabled] || ![I2FConfigManager hasDumpedOnce];

    SCLAlertView *waitingAlert = nil;
    if (shouldDump) {
        showWaiting(@"Dumping...", &waitingAlert);
    }

    Dumper::DumpStatus dumpStatus = Dumper::DumpStatus::SUCCESS;
    if (shouldDump) {
        dumpStatus = Dumper::dump(dumpPath.UTF8String, headersDumpPath.UTF8String);
    }

    if ([fileManager fileExistsAtPath:zipDumpPath]) {
        [fileManager removeItemAtPath:zipDumpPath error:nil];
    }
    if (shouldDump) {
        [SSZipArchive createZipFileAtPath:zipDumpPath withContentsOfDirectory:dumpPath];
        dismisWaiting(waitingAlert);
    }

    if (shouldDump && dumpStatus != Dumper::DumpStatus::SUCCESS) {
        showError(@"Error while dumping, check logs.txt");
        return;
    }

    if (shouldDump && dumpStatus == Dumper::DumpStatus::SUCCESS) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:dumpPath forKey:@"I2F.LastDumpDirectory"];

        [I2FConfigManager setHasDumpedOnce:YES];

        NSArray<NSString *> *allRvas = [I2FDumpRvaParser allSetTextRvaStringsInDumpDirectory:dumpPath];
        if (allRvas.count > 0) {
            [defaults setObject:allRvas forKey:@"I2F.SetTextRvaStrings"];
            NSString *firstRva = allRvas.firstObject;
            [defaults setObject:firstRva forKey:@"I2F.SetTextRvaString"];
            [defaults synchronize];

            [I2FIl2CppTextHookManager installHookWithBaseAddress:(unsigned long long)Variables::info.address
                                                      rvaString:firstRva];
        } else {
            [defaults synchronize];
        }
    }

    NSLog(@"[I2CppDumper] Dump finished.");

    dispatch_async(dispatch_get_main_queue(), ^{
        if (shouldDump) {
            showSuccess([NSString stringWithFormat:@"Dump at: \n%@\nFolder: %@", zipDumpPath, dumpPath]);
        }
    });
}

extern "C" void StartIl2CppDumpThread(void) {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        NSLog(@"[I2CppDumper] ========= START DUMPER =========");
        dump_thread();
        NSLog(@"[I2CppDumper] ========= END DUMPER =========");
    });
}
