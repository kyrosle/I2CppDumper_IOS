#import "I2FIl2CppTextHookManager.h"

#import <UIKit/UIKit.h>

#import "Core/Il2cpp.hpp"
#import "I2FTextLogManager.h"
#import "I2FConfigManager.h"

#include <string.h>

typedef struct {
    NSString *full;
    NSString *namespaceName;
    NSString *className;
    NSString *methodName;
} I2FTargetSpec;

typedef struct {
    void *methodInfo;
    void *methodPointer;
} I2FResolvedMethod;

static NSMutableDictionary<NSValue *, NSString *> *gMethodToNameMap = nil;              // methodInfo -> name
static NSMutableDictionary<NSValue *, NSValue *> *gMethodToOriginalMap = nil;          // methodInfo -> original function ptr
static NSMutableDictionary<NSString *, NSValue *> *gNameToMethodMap = nil;             // name -> methodInfo
static NSMutableSet<NSString *> *gInstalledNames = nil;

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

static BOOL I2FResolveMethod(const I2FTargetSpec &spec, I2FResolvedMethod *outResolved) {
    if (!outResolved) {
        return NO;
    }
    if (!I2FApiReady()) {
        return NO;
    }

    void *domain = Variables::IL2CPP::il2cpp_domain_get();
    if (!domain) {
        return NO;
    }

    size_t assemblyCount = 0;
    void **assemblies = Variables::IL2CPP::il2cpp_domain_get_assemblies(domain, &assemblyCount);
    if (!assemblies || assemblyCount == 0) {
        return NO;
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
                outResolved->methodInfo = method;
                outResolved->methodPointer = methodPointer;
                return YES;
            }
        }
    }
    return NO;
}

typedef void (*I2FSetTextOriginalFunc)(void *self, void *il2cppString, const void *method);

static void I2FSetterReplacement(void *self, void *il2cppString, const void *method) {
    @autoreleasepool {
        NSValue *key = [NSValue valueWithPointer:method];

        NSString *nameString = nil;
        NSValue *origPtrValue = nil;
        @synchronized (gMethodToNameMap) {
            nameString = gMethodToNameMap[key];
        }
        @synchronized (gMethodToOriginalMap) {
            origPtrValue = gMethodToOriginalMap[key];
        }

        NSString *text = I2FConvertIl2CppStringToNSString(il2cppString);
        if (text.length > 0) {
            [[I2FTextLogManager sharedManager] appendText:text rvaString:(nameString ?: @"")];
        }

        I2FSetTextOriginalFunc orig = (I2FSetTextOriginalFunc)(origPtrValue.pointerValue);
        if (orig) {
            orig(self, il2cppString, method);
        }
    }
}

@implementation I2FIl2CppTextHookManager

+ (void)initialize {
    if (self == [I2FIl2CppTextHookManager class]) {
        gMethodToNameMap = [NSMutableDictionary dictionary];
        gMethodToOriginalMap = [NSMutableDictionary dictionary];
        gNameToMethodMap = [NSMutableDictionary dictionary];
        gInstalledNames = [NSMutableSet set];
    }
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

        @synchronized (gNameToMethodMap) {
            if (gNameToMethodMap[fullName] != nil) {
                continue;
            }
        }

        [I2FConfigManager setLastInstallingHookEntry:entry];

        I2FResolvedMethod resolved = {0};
        if (!I2FResolveMethod(spec, &resolved)) {
            NSLog(@"[I2FIl2CppTextHookManager] resolve failed for %@", fullName);
            [I2FConfigManager setLastInstallingHookEntry:nil];
            continue;
        }

        NSValue *methodKey = [NSValue valueWithPointer:resolved.methodInfo];
        BOOL alreadyInstalled = NO;
        @synchronized (gMethodToOriginalMap) {
            alreadyInstalled = (gMethodToOriginalMap[methodKey] != nil);
        }
        if (alreadyInstalled) {
            @synchronized (gNameToMethodMap) {
                gNameToMethodMap[fullName] = methodKey;
            }
            [I2FConfigManager setLastInstallingHookEntry:nil];
            continue;
        }

        void **methodPointerField = (void **)resolved.methodInfo; // MethodInfo 首字段即函数指针
        void *expected = resolved.methodPointer;
        BOOL swapped = __sync_bool_compare_and_swap(methodPointerField, expected, (void *)&I2FSetterReplacement);
        if (!swapped) {
            // 如果已经被替换成我们的函数，视为成功；否则失败。
            if (*methodPointerField != (void *)&I2FSetterReplacement) {
                NSLog(@"[I2FIl2CppTextHookManager] Hook failed %@, pointer write rejected", fullName);
                [I2FConfigManager setLastInstallingHookEntry:nil];
                continue;
            }
        }

        @synchronized (gMethodToOriginalMap) {
            gMethodToOriginalMap[methodKey] = [NSValue valueWithPointer:expected];
        }
        @synchronized (gMethodToNameMap) {
            gMethodToNameMap[methodKey] = fullName;
        }
        @synchronized (gNameToMethodMap) {
            gNameToMethodMap[fullName] = methodKey;
        }
        @synchronized (gInstalledNames) {
            [gInstalledNames addObject:fullName];
        }

        NSLog(@"[I2FIl2CppTextHookManager] Hook success %@ @ %p -> %p", fullName, resolved.methodPointer, methodPointerField);
        [I2FConfigManager setLastInstallingHookEntry:nil];
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
        NSValue *methodKey = nil;
        @synchronized (gNameToMethodMap) {
            methodKey = gNameToMethodMap[fullName];
        }
        if (!methodKey) {
            continue;
        }
        NSValue *origPtrValue = nil;
        @synchronized (gMethodToOriginalMap) {
            origPtrValue = gMethodToOriginalMap[methodKey];
        }
        if (!origPtrValue) {
            continue;
        }
        void **methodPointerField = (void **)methodKey.pointerValue;
        void *current = *methodPointerField;
        if (current == (void *)&I2FSetterReplacement) {
            *methodPointerField = origPtrValue.pointerValue;
            NSLog(@"[I2FIl2CppTextHookManager] Unhook success %@ @ %p", fullName, methodPointerField);
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] Unhook skipped %@ (pointer already changed)", fullName);
        }

        @synchronized (gMethodToOriginalMap) {
            [gMethodToOriginalMap removeObjectForKey:methodKey];
        }
        @synchronized (gMethodToNameMap) {
            [gMethodToNameMap removeObjectForKey:methodKey];
        }
        @synchronized (gNameToMethodMap) {
            [gNameToMethodMap removeObjectForKey:fullName];
        }
        @synchronized (gInstalledNames) {
            [gInstalledNames removeObject:fullName];
        }
    }
}

@end
