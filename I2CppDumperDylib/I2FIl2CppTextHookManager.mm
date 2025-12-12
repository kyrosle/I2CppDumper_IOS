#import "I2FIl2CppTextHookManager.h"

#import <UIKit/UIKit.h>

#import "Core/Il2cpp.hpp"
#import "I2FTextLogManager.h"
#import "I2FConfigManager.h"
#import "includes/Dobby/dobby.h"

#include <string.h>

typedef struct {
    NSString *full;
    NSString *namespaceName;
    NSString *className;
    NSString *methodName;
} I2FTargetSpec;

static NSMutableDictionary<NSNumber *, NSString *> *gAddressToNameMap = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gNameToAddressMap = nil;
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

static BOOL I2FParseTarget(NSString *fullName, I2FTargetSpec *outSpec) {
    if (fullName.length == 0) {
        return NO;
    }
    NSString *trimmed = [fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange lastDot = [trimmed rangeOfString:@"." options:NSBackwardsSearch];
    if (lastDot.location == NSNotFound || lastDot.location + 1 >= trimmed.length) {
        return NO;
    }
    NSString *method = [trimmed substringFromIndex:lastDot.location + 1];
    NSString *classAndNs = [trimmed substringToIndex:lastDot.location];
    NSRange secondLast = [classAndNs rangeOfString:@"." options:NSBackwardsSearch];
    NSString *ns = @"";
    NSString *klass = classAndNs;
    if (secondLast.location != NSNotFound) {
        ns = [classAndNs substringToIndex:secondLast.location];
        klass = [classAndNs substringFromIndex:secondLast.location + 1];
    }
    if (klass.length == 0 || method.length == 0) {
        return NO;
    }
    if (outSpec) {
        outSpec->full = trimmed;
        outSpec->namespaceName = ns;
        outSpec->className = klass;
        outSpec->methodName = method;
    }
    return YES;
}

static BOOL I2FApiReady(void) {
    return Variables::IL2CPP::il2cpp_domain_get
        && Variables::IL2CPP::il2cpp_domain_get_assemblies
        && Variables::IL2CPP::il2cpp_assembly_get_image
        && Variables::IL2CPP::il2cpp_class_from_name
        && Variables::IL2CPP::il2cpp_class_get_methods
        && Variables::IL2CPP::il2cpp_method_get_name;
}

static void I2FAttachThreadIfNeeded(void) {
    if (!Variables::IL2CPP::il2cpp_thread_attach || !Variables::IL2CPP::il2cpp_domain_get) {
        return;
    }
    if (Variables::IL2CPP::il2cpp_is_vm_thread && Variables::IL2CPP::il2cpp_is_vm_thread(nullptr)) {
        return;
    }
    void *domain = Variables::IL2CPP::il2cpp_domain_get();
    if (domain) {
        Variables::IL2CPP::il2cpp_thread_attach(domain);
    }
}

static void *I2FResolveMethodPointer(const I2FTargetSpec &spec) {
    if (!I2FApiReady()) {
        NSLog(@"[I2FIl2CppTextHookManager] IL2CPP API not ready, skip %@", spec.full);
        return nullptr;
    }

    void *domain = Variables::IL2CPP::il2cpp_domain_get();
    if (!domain) {
        return nullptr;
    }

    size_t assemblyCount = 0;
    void **assemblies = Variables::IL2CPP::il2cpp_domain_get_assemblies(domain, &assemblyCount);
    if (!assemblies || assemblyCount == 0) {
        return nullptr;
    }

    const char *ns = spec.namespaceName.length > 0 ? [spec.namespaceName UTF8String] : "";
    const char *klass = [spec.className UTF8String];
    const char *methodName = [spec.methodName UTF8String];

    for (size_t i = 0; i < assemblyCount; i++) {
        const void *image = Variables::IL2CPP::il2cpp_assembly_get_image(assemblies[i]);
        if (!image) {
            continue;
        }
        void *klassPtr = Variables::IL2CPP::il2cpp_class_from_name(image, ns, klass);
        if (!klassPtr) {
            continue;
        }

        void *method = nullptr;
        if (Variables::IL2CPP::il2cpp_class_get_method_from_name) {
            method = Variables::IL2CPP::il2cpp_class_get_method_from_name(klassPtr, methodName, 1);
            if (!method) {
                method = Variables::IL2CPP::il2cpp_class_get_method_from_name(klassPtr, methodName, 0);
            }
        }
        if (!method) {
            if (!Variables::IL2CPP::il2cpp_class_get_methods || !Variables::IL2CPP::il2cpp_method_get_name) {
                continue;
            }
            void *iter = nullptr;
            while ((method = Variables::IL2CPP::il2cpp_class_get_methods(klassPtr, &iter))) {
                const char *name = Variables::IL2CPP::il2cpp_method_get_name(method);
                if (name && strcmp(name, methodName) == 0) {
                    break;
                }
            }
        }

        if (method) {
            void *methodPointer = *(void **)method;
            if (methodPointer) {
                return methodPointer;
            }
        }
    }
    return nullptr;
}

static void I2FSetterPreHandler(void *address, DobbyRegisterContext *ctx) {
    @autoreleasepool {
        NSString *nameString = nil;
        @synchronized (gAddressToNameMap) {
            nameString = gAddressToNameMap[@((unsigned long long)address)];
        }

        void *str = I2FGetSecondArgument(ctx);
        NSString *text = I2FConvertIl2CppStringToNSString(str);
        if (text.length > 0) {
            [[I2FTextLogManager sharedManager] appendText:text rvaString:(nameString ?: @"")];
        }
    }
}

@implementation I2FIl2CppTextHookManager

+ (void)initialize {
    if (self == [I2FIl2CppTextHookManager class]) {
        gAddressToNameMap = [NSMutableDictionary dictionary];
        gNameToAddressMap = [NSMutableDictionary dictionary];
        gInstalledAddresses = [NSMutableArray array];
    }
}

+ (void)installHooksWithNames:(NSArray<NSString *> *)names {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        if (name.length == 0) {
            continue;
        }
        [entries addObject:@{ @"name": name }];
    }
    [self installHooksWithEntries:entries];
}

+ (void)installHooksWithEntries:(NSArray<NSDictionary *> *)entries {
    if (entries.count == 0) {
        return;
    }

    I2FAttachThreadIfNeeded();

    NSMutableArray<NSDictionary *> *uniqueEntries = [NSMutableArray array];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
    for (NSDictionary *entry in entries) {
        NSString *name = entry[@"name"];
        if (name.length == 0 || [seenNames containsObject:name]) {
            continue;
        }
        [seenNames addObject:name];
        [uniqueEntries addObject:entry];
    }

    NSLog(@"[I2FIl2CppTextHookManager] installHooks count=%lu, entries=%@",
          (unsigned long)uniqueEntries.count, uniqueEntries);

    for (NSDictionary *entry in uniqueEntries) {
        NSString *fullName = entry[@"name"];
        if (fullName.length == 0) {
            continue;
        }

        I2FTargetSpec spec;
        if (!I2FParseTarget(fullName, &spec)) {
            NSLog(@"[I2FIl2CppTextHookManager] invalid target name %@", fullName);
            continue;
        }

        @synchronized (gNameToAddressMap) {
            if (gNameToAddressMap[fullName] != nil) {
                continue;
            }
        }

        [I2FConfigManager setLastInstallingHookEntry:entry];

        void *methodPointer = I2FResolveMethodPointer(spec);
        if (!methodPointer) {
            NSLog(@"[I2FIl2CppTextHookManager] resolve failed for %@", fullName);
            [I2FConfigManager setLastInstallingHookEntry:nil];
            continue;
        }

        NSNumber *addrKey = @((unsigned long long)methodPointer);
        @synchronized (gAddressToNameMap) {
            if (gAddressToNameMap[addrKey]) {
                gNameToAddressMap[fullName] = addrKey;
                continue;
            }
        }

        int ret = DobbyInstrument(methodPointer, I2FSetterPreHandler);
        if (ret == 0) {
            NSLog(@"[I2FIl2CppTextHookManager] Hook success %@ @ %p", fullName, methodPointer);
            @synchronized (gAddressToNameMap) {
                gAddressToNameMap[addrKey] = fullName;
                gNameToAddressMap[fullName] = addrKey;
                [gInstalledAddresses addObject:addrKey];
            }
            [I2FConfigManager setLastInstallingHookEntry:nil];
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] Hook failed %@, ret=%d", fullName, ret);
            [I2FConfigManager setLastInstallingHookEntry:nil];
        }
    }
}

+ (void)uninstallHooksWithEntries:(NSArray<NSDictionary *> *)entries {
    if (entries.count == 0) {
        return;
    }

    for (NSDictionary *entry in entries) {
        NSString *fullName = entry[@"name"];
        if (fullName.length == 0) {
            continue;
        }
        NSNumber *addrKey = nil;
        @synchronized (gNameToAddressMap) {
            addrKey = gNameToAddressMap[fullName];
        }
        if (!addrKey) {
            continue;
        }
        void *addr = (void *)addrKey.unsignedLongLongValue;
        int ret = DobbyDestroy(addr);
        if (ret == 0) {
            NSLog(@"[I2FIl2CppTextHookManager] Unhook success %@ @ %p", fullName, addr);
            @synchronized (gAddressToNameMap) {
                [gAddressToNameMap removeObjectForKey:addrKey];
                [gNameToAddressMap removeObjectForKey:fullName];
                [gInstalledAddresses removeObject:addrKey];
            }
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] Unhook failed %@ @ %p, ret=%d", fullName, addr, ret);
        }
    }
}

+ (BOOL)isHookInstalledWithName:(NSString *)name {
    if (name.length == 0) {
        return NO;
    }
    @synchronized (gNameToAddressMap) {
        return gNameToAddressMap[name] != nil;
    }
}

@end
