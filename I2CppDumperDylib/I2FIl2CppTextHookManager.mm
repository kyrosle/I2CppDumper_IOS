#import "I2FIl2CppTextHookManager.h"

#import <UIKit/UIKit.h>

#import "Core/Il2cpp.hpp"
#import "I2FTextLogManager.h"
#import "includes/Dobby/dobby.h"

typedef void (*I2FSetTextFn)(void *self, void *str);

static NSMutableDictionary<NSNumber *, NSString *> *gAddressToRvaMap = nil;
static NSMutableArray<NSNumber *> *gInstalledAddresses = nil;

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

static void I2FSetterPreHandler(void *address, DobbyRegisterContext *ctx) {
    @autoreleasepool {
        NSString *rvaString = nil;
        @synchronized (gAddressToRvaMap) {
            rvaString = gAddressToRvaMap[@((unsigned long long)address)];
        }

        void *str = I2FGetSecondArgument(ctx);
        NSString *text = I2FConvertIl2CppStringToNSString(str);
        NSLog(@"I2FSetterPreHandler: text: '%@'\n rvaString: '%@'\n", text, rvaString);
        if (text.length > 0) {
            [[I2FTextLogManager sharedManager] appendText:text rvaString:(rvaString ?: @"")];
        }
    }
}

@implementation I2FIl2CppTextHookManager

+ (void)initialize {
    if (self == [I2FIl2CppTextHookManager class]) {
        gAddressToRvaMap = [NSMutableDictionary dictionary];
        gInstalledAddresses = [NSMutableArray array];
    }
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
    if (baseAddress == 0 || rvaStrings.count == 0) {
        return;
    }

    NSLog(@"[I2FIl2CppTextHookManager] installHooks base=0x%llx, count=%lu, rvas=%@",
          baseAddress, (unsigned long)rvaStrings.count, rvaStrings);

    for (NSString *rvaString in rvaStrings) {
        if (rvaString.length == 0) {
            continue;
        }

        // 统一使用 C 层解析，避免 NSScanner 在 16 进制场景下的歧义。
        NSString *trimmed = [rvaString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *lower = [trimmed lowercaseString];

        unsigned long long rva = 0;
        const char *cstr = [lower UTF8String];
        if (!cstr || cstr[0] == '\0') {
            NSLog(@"[I2FIl2CppTextHookManager] empty RVA string after trim '%@'", rvaString);
            continue;
        }

        char *endPtr = NULL;
        if (lower.length > 2 && [lower hasPrefix:@"0x"]) {
            rva = strtoull(cstr + 2, &endPtr, 16);
        } else {
            rva = strtoull(cstr, &endPtr, 10);
        }

        if (endPtr == cstr || rva == 0) {
            NSLog(@"[I2FIl2CppTextHookManager] failed to parse RVA from '%@'", rvaString);
            continue;
        }

        // 过滤掉过小的 RVA（一般不可能是方法体入口，避免误 hook 模块头部）。
        if (rva < 0x10000) {
            NSLog(@"[I2FIl2CppTextHookManager] skip too small RVA=0x%llx from '%@'", rva, rvaString);
            continue;
        }

        if (rva == 0) {
            continue;
        }

        uintptr_t address = (uintptr_t)(baseAddress + rva);
        NSLog(@"[I2FIl2CppTextHookManager] try hook RVA=%@ => addr=%p", rvaString, (void *)address);
        NSNumber *key = @((unsigned long long)address);

        @synchronized (gAddressToRvaMap) {
            if (gAddressToRvaMap[key] != nil) {
                continue;
            }
        }

        int ret = DobbyInstrument((void *)address, I2FSetterPreHandler);
        if (ret == 0) {
            NSLog(@"[I2FIl2CppTextHookManager] DobbyInstrument success at %p", (void *)address);
            @synchronized (gAddressToRvaMap) {
                gAddressToRvaMap[key] = rvaString;
                [gInstalledAddresses addObject:key];
            }
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] DobbyInstrument FAILED at %p, ret=%d", (void *)address, ret);
        }
    }
}

@end
