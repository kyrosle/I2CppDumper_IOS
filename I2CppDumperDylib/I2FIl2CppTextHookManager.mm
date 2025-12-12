#import "I2FIl2CppTextHookManager.h"

#import <UIKit/UIKit.h>

#import "Core/Il2cpp.hpp"
#import "I2FTextLogManager.h"
#import "I2FConfigManager.h"
#import "includes/Dobby/dobby.h"

#include <unordered_set>

typedef void (*I2FSetTextFn)(void *self, void *str);

static NSMutableDictionary<NSNumber *, NSString *> *gAddressToRvaMap = nil;
static NSMutableDictionary<NSNumber *, NSString *> *gAddressToNameMap = nil;
static NSMutableArray<NSNumber *> *gInstalledAddresses = nil;
static std::unordered_set<uint64_t> gValidMethodRvas;
static BOOL gValidMethodRvasBuilt = NO;

static NSString *I2FConvertIl2CppStringToNSString(void *il2cppString) {
    if (!il2cppString || !Variables::IL2CPP::il2cpp_string_chars) {
        return @"";
    }
    uint16_t *chars = Variables::IL2CPP::il2cpp_string_chars(il2cppString);
    if (!chars) {
        return @"";
    }
    NSMutableString *result = [NSMutableString string];
    while (*chars) {
        unichar c = (unichar)(*chars);
        [result appendFormat:@"%C", c];
        chars++;
    }
    return result;
}

static void *I2FGetSecondArgument(DobbyRegisterContext *ctx) {
#if defined(__aarch64__)
    return (void *)ctx->general.regs.x1;
#elif defined(__arm__)
    return (void *)ctx->general.regs.r1;
#elif defined(__x86_64__)
    return (void *)ctx->general.regs.rsi;
#else
    return NULL;
#endif
}

static BOOL I2FParseRvaString(NSString *rvaString, unsigned long long *outRva) {
    if (rvaString.length == 0) {
        return NO;
    }
    NSString *trimmed = [rvaString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = [trimmed lowercaseString];
    const char *cstr = [lower UTF8String];
    if (!cstr || cstr[0] == '\0') {
        return NO;
    }

    char *endPtr = NULL;
    unsigned long long rva = 0;
    if (lower.length > 2 && [lower hasPrefix:@"0x"]) {
        rva = strtoull(cstr + 2, &endPtr, 16);
    } else {
        rva = strtoull(cstr, &endPtr, 10);
    }

    if (endPtr == cstr || rva == 0) {
        return NO;
    }
    if (outRva) {
        *outRva = rva;
    }
    return YES;
}

static void I2FSetterPreHandler(void *address, DobbyRegisterContext *ctx) {
    @autoreleasepool {
        NSLog(@"I2FSetterPreHandler: Enter Hook");
        NSString *rvaString = nil;
        NSString *nameString = nil;
        @synchronized (gAddressToRvaMap) {
            rvaString = gAddressToRvaMap[@((unsigned long long)address)];
            nameString = gAddressToNameMap[@((unsigned long long)address)];
        }

        void *str = I2FGetSecondArgument(ctx);
        NSString *text = I2FConvertIl2CppStringToNSString(str);
        NSLog(@"I2FSetterPreHandler: text: '%@'\n rvaString: '%@'\n name: '%@'", text, rvaString, nameString);
        if (text.length > 0) {
            [[I2FTextLogManager sharedManager] appendText:text rvaString:(rvaString ?: @"")];
        }
        NSLog(@"I2FSetterPreHandler: Exit Hook");
    }
}

@implementation I2FIl2CppTextHookManager

+ (void)initialize {
    if (self == [I2FIl2CppTextHookManager class]) {
        gAddressToRvaMap = [NSMutableDictionary dictionary];
        gAddressToNameMap = [NSMutableDictionary dictionary];
        gInstalledAddresses = [NSMutableArray array];
    }
}

// 构建一张 "合法方法 RVA" 表，用于过滤掉非方法入口的地址，避免乱 hook 造成崩溃。
static void I2FBuildValidMethodRvaSetIfNeeded(void) {
    if (gValidMethodRvasBuilt) {
        return;
    }
    gValidMethodRvasBuilt = YES;

    if (!Variables::IL2CPP::il2cpp_domain_get || !Variables::IL2CPP::il2cpp_domain_get_assemblies) {
        NSLog(@"[I2FIl2CppTextHookManager] IL2CPP symbols not ready, skip RVA validation.");
        return;
    }

    void *domain = Variables::IL2CPP::il2cpp_domain_get();
    if (!domain) {
        NSLog(@"[I2FIl2CppTextHookManager] il2cpp_domain_get returned null.");
        return;
    }

    size_t assemblyCount = 0;
    void **assemblies = Variables::IL2CPP::il2cpp_domain_get_assemblies(domain, &assemblyCount);
    if (!assemblies || assemblyCount == 0) {
        NSLog(@"[I2FIl2CppTextHookManager] no assemblies found when building RVA table.");
        return;
    }

    uint64_t baseAddress = (uint64_t)Variables::info.address;
    if (baseAddress == 0) {
        NSLog(@"[I2FIl2CppTextHookManager] base address is 0 when building RVA table.");
        return;
    }

    for (size_t i = 0; i < assemblyCount; i++) {
        const void *image = Variables::IL2CPP::il2cpp_assembly_get_image(assemblies[i]);
        if (!image) {
            continue;
        }

        const Variables::Il2CppImage *il2cppImage = static_cast<const Variables::Il2CppImage *>(image);
        if (!Variables::IL2CPP::il2cpp_image_get_class_count || !Variables::IL2CPP::il2cpp_image_get_class) {
            continue;
        }

        size_t classCount = Variables::IL2CPP::il2cpp_image_get_class_count(il2cppImage);
        for (size_t j = 0; j < classCount; ++j) {
            void *klass = Variables::IL2CPP::il2cpp_image_get_class(il2cppImage, j);
            if (!klass) {
                continue;
            }

            void *iter = nullptr;
            while (auto method = Variables::IL2CPP::il2cpp_class_get_methods(klass, &iter)) {
                auto methodPointer = *(void **)method;
                if (!methodPointer) {
                    continue;
                }
                uint64_t rva = (uint64_t)methodPointer - baseAddress;
                gValidMethodRvas.insert(rva);
            }
        }
    }

    NSLog(@"[I2FIl2CppTextHookManager] Built valid RVA table with %zu entries.", gValidMethodRvas.size());
}

+ (void)installHookWithBaseAddress:(unsigned long long)baseAddress
                        rvaString:(nullable NSString *)rvaString {
    if (baseAddress == 0 || rvaString.length == 0) {
        return;
    }
    [self installHooksWithBaseAddress:baseAddress rvaStrings:@[rvaString]];
}

+ (void)installHooksWithBaseAddress:(unsigned long long)baseAddress
                         rvaStrings:(NSArray<NSString *> *)rvaStrings {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:rvaStrings.count];
    for (NSString *rva in rvaStrings) {
        if (rva.length == 0) continue;
        [entries addObject:@{@"rva": rva}];
    }
    [self installHooksWithBaseAddress:baseAddress entries:entries];
}

+ (void)installHooksWithBaseAddress:(unsigned long long)baseAddress
                            entries:(NSArray<NSDictionary *> *)entries {
    if (baseAddress == 0 || entries.count == 0) {
        return;
    }

    I2FBuildValidMethodRvaSetIfNeeded();

    NSLog(@"[I2FIl2CppTextHookManager] installHooks base=0x%llx, count=%lu, entries=%@",
          baseAddress, (unsigned long)entries.count, entries);

    // 去重同一 RVA，避免重复日志/遍历。
    NSMutableArray<NSDictionary *> *uniqueEntries = [NSMutableArray array];
    NSMutableSet<NSString *> *seenRva = [NSMutableSet set];
    for (NSDictionary *entry in entries) {
        NSString *rva = entry[@"rva"];
        if (rva.length == 0 || [seenRva containsObject:rva]) {
            continue;
        }
        [seenRva addObject:rva];
        [uniqueEntries addObject:entry];
    }

    for (NSDictionary *entry in uniqueEntries) {
        NSString *rvaString = entry[@"rva"];
        if (rvaString.length == 0) {
            continue;
        }
        NSString *name = entry[@"name"];

        unsigned long long rva = 0;
        if (!I2FParseRvaString(rvaString, &rva)) {
            NSLog(@"[I2FIl2CppTextHookManager] failed to parse RVA from '%@'", rvaString);
            continue;
        }

        if (rva < 0x10000) {
            NSLog(@"[I2FIl2CppTextHookManager] skip too small RVA=0x%llx from '%@'", rva, rvaString);
            continue;
        }

        // 校验该 RVA 是否存在于 "方法入口表" 中，避免 hook 到非方法地址。
        if (!gValidMethodRvas.empty() && gValidMethodRvas.find(rva) == gValidMethodRvas.end()) {
            NSLog(@"[I2FIl2CppTextHookManager] skip RVA=0x%llx from '%@' (not found in IL2CPP methods)", rva, rvaString);
            continue;
        }

        uintptr_t address = (uintptr_t)(baseAddress + rva);
        NSLog(@"[I2FIl2CppTextHookManager] try hook RVA=%@ (%@) => addr=%p", rvaString, name, (void *)address);
        NSNumber *key = @((unsigned long long)address);

        @synchronized (gAddressToRvaMap) {
            if (gAddressToRvaMap[key] != nil) {
                continue;
            }
        }

        // 标记正在安装的 hook，用于崩溃检测。
        [I2FConfigManager setLastInstallingHookEntry:entry];

        int ret = DobbyInstrument((void *)address, I2FSetterPreHandler);
        if (ret == 0) {
            NSLog(@"[I2FIl2CppTextHookManager] DobbyInstrument success at %p", (void *)address);
            @synchronized (gAddressToRvaMap) {
                gAddressToRvaMap[key] = rvaString;
                if (name.length > 0) {
                    gAddressToNameMap[key] = name;
                }
                [gInstalledAddresses addObject:key];
            }
            [I2FConfigManager setLastInstallingHookEntry:nil];
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] DobbyInstrument FAILED at %p, ret=%d", (void *)address, ret);
            [I2FConfigManager setLastInstallingHookEntry:nil];
        }
    }
}

+ (void)uninstallHooksWithBaseAddress:(unsigned long long)baseAddress
                              entries:(NSArray<NSDictionary *> *)entries {
    if (baseAddress == 0 || entries.count == 0) {
        return;
    }

    for (NSDictionary *entry in entries) {
        NSString *rvaString = entry[@"rva"];
        unsigned long long rva = 0;
        if (!I2FParseRvaString(rvaString, &rva)) {
            continue;
        }
        uintptr_t address = (uintptr_t)(baseAddress + rva);
        NSNumber *key = @((unsigned long long)address);
        @synchronized (gAddressToRvaMap) {
            if (!gAddressToRvaMap[key]) {
                continue;
            }
        }
        int ret = DobbyDestroy((void *)address);
        if (ret == 0) {
            NSLog(@"[I2FIl2CppTextHookManager] DobbyDestroy success at %p", (void *)address);
            @synchronized (gAddressToRvaMap) {
                [gAddressToRvaMap removeObjectForKey:key];
                [gAddressToNameMap removeObjectForKey:key];
                [gInstalledAddresses removeObject:key];
            }
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] DobbyDestroy FAILED at %p, ret=%d", (void *)address, ret);
        }
    }
}

+ (BOOL)isHookInstalledWithBaseAddress:(unsigned long long)baseAddress
                             rvaString:(NSString *)rvaString {
    if (baseAddress == 0 || rvaString.length == 0) {
        return NO;
    }
    unsigned long long rva = 0;
    if (!I2FParseRvaString(rvaString, &rva)) {
        return NO;
    }
    uintptr_t address = (uintptr_t)(baseAddress + rva);
    NSNumber *key = @((unsigned long long)address);
    @synchronized (gAddressToRvaMap) {
        return gAddressToRvaMap[key] != nil;
    }
}

@end
