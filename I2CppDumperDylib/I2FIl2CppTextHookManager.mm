#import "I2FIl2CppTextHookManager.h"

#import <UIKit/UIKit.h>

#import "Core/Il2cpp.hpp"
#import "I2FTextLogManager.h"
#import "I2FConfigManager.h"
#import "I2FTranslationManager.h"

#include <string.h>
#include <stdlib.h>

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

@interface I2FPendingRefresh : NSObject
@property (nonatomic, strong) NSValue *targetPointer;  // void * il2cpp instance
@property (nonatomic, strong) NSValue *methodKey;      // NSValue wrapping MethodInfo pointer
@end

@implementation I2FPendingRefresh
@end

static NSMutableDictionary<NSValue *, NSString *> *gMethodToNameMap = nil;              // methodInfo -> name
static NSMutableDictionary<NSValue *, NSValue *> *gMethodToOriginalMap = nil;          // methodInfo -> original function ptr
static NSMutableDictionary<NSString *, NSValue *> *gNameToMethodMap = nil;             // name -> methodInfo
static NSMutableSet<NSString *> *gInstalledNames = nil;
static NSMutableDictionary<NSString *, I2FPendingRefresh *> *gPendingRefreshMap = nil; // original text -> pending refresh info
static NSMutableDictionary<NSValue *, NSValue *> *gSlotToOriginalMap = nil;            // slot ptr -> original function ptr
static NSMutableDictionary<NSString *, NSValue *> *gNameToSlotMap = nil;               // name -> slot ptr
static NSMutableDictionary<NSValue *, NSString *> *gOriginalPointerToNameMap = nil;    // original function ptr -> name

static NSString *I2FShortenTextForLog(NSString *text) {
    if (text.length <= 64) {
        return text;
    }
    return [[text substringToIndex:64] stringByAppendingString:@"..."];
}

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

static BOOL I2FShouldLogText(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        // 常用中日韩表意文字区和兼容/扩展块（简易过滤，仅关心是否含中文）
        if ((c >= 0x4E00 && c <= 0x9FFF) ||    // CJK Unified Ideographs
            (c >= 0x3400 && c <= 0x4DBF) ||    // CJK Extension A
            (c >= 0xF900 && c <= 0xFAFF) ||    // CJK Compatibility Ideographs
            (c >= 0x20000 && c <= 0x2A6DF)) {  // CJK Extension B（高位代理区，粗略判断）
            return YES;
        }
    }
    return NO;
}

static void *I2FCreateIl2CppStringFromNSString(NSString *string) {
    if (string.length == 0 || !Variables::IL2CPP::il2cpp_string_new) {
        return nullptr;
    }
    const char *utf8 = [string UTF8String];
    if (!utf8) {
        return nullptr;
    }
    return Variables::IL2CPP::il2cpp_string_new(utf8);
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

static BOOL I2FParseOffsetValue(id value, uint64_t *outValue) {
    if (!outValue || !value) {
        return NO;
    }
    uint64_t parsed = 0;
    if ([value isKindOfClass:[NSNumber class]]) {
        parsed = [(NSNumber *)value unsignedLongLongValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)value lowercaseString];
        const char *cstr = [lower UTF8String];
        if (!cstr) {
            return NO;
        }
        char *end = NULL;
        if ([lower hasPrefix:@"0x"]) {
            parsed = strtoull(cstr + 2, &end, 16);
        } else {
            parsed = strtoull(cstr, &end, 10);
        }
        if (end == cstr) {
            parsed = 0;
        }
    }
    if (parsed == 0) {
        return NO;
    }
    *outValue = parsed;
    return YES;
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

static BOOL I2FResolveMethodByPointer(void *targetPointer, I2FResolvedMethod *outResolved) {
    if (!outResolved || !targetPointer) {
        return NO;
    }
    if (!I2FApiReady()) {
        return NO;
    }
    void *domain = Variables::IL2CPP::il2cpp_domain_get ? Variables::IL2CPP::il2cpp_domain_get() : nullptr;
    if (!domain) {
        return NO;
    }
    size_t assemblyCount = 0;
    void **assemblies = Variables::IL2CPP::il2cpp_domain_get_assemblies(domain, &assemblyCount);
    if (!assemblies || assemblyCount == 0) {
        return NO;
    }
    for (size_t i = 0; i < assemblyCount; i++) {
        const void *image = Variables::IL2CPP::il2cpp_assembly_get_image(assemblies[i]);
        if (!image) {
            continue;
        }
        if (!Variables::IL2CPP::il2cpp_image_get_class_count || !Variables::IL2CPP::il2cpp_image_get_class) {
            continue;
        }
        size_t classCount = Variables::IL2CPP::il2cpp_image_get_class_count((const Variables::Il2CppImage *)image);
        for (size_t c = 0; c < classCount; c++) {
            void *klassPtr = Variables::IL2CPP::il2cpp_image_get_class((const Variables::Il2CppImage *)image, c);
            if (!klassPtr) {
                continue;
            }
            if (!Variables::IL2CPP::il2cpp_class_get_methods) {
                continue;
            }
            void *iter = nullptr;
            void *method = nullptr;
            while ((method = Variables::IL2CPP::il2cpp_class_get_methods(klassPtr, &iter))) {
                void *methodPointer = *(void **)method;
                if (methodPointer == targetPointer) {
                    outResolved->methodInfo = method;
                    outResolved->methodPointer = methodPointer;
                    return YES;
                }
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
        if (!origPtrValue) {
            void *origFromMethod = method ? *((void **)method) : nullptr;
            if (origFromMethod) {
                NSValue *origKey = [NSValue valueWithPointer:origFromMethod];
                NSString *cachedName = nil;
                @synchronized (gOriginalPointerToNameMap) {
                    cachedName = gOriginalPointerToNameMap[origKey];
                }
                if (cachedName) {
                    origPtrValue = origKey;
                    if (!nameString) {
                        nameString = cachedName;
                    }
                    @synchronized (gMethodToOriginalMap) {
                        gMethodToOriginalMap[key] = origPtrValue;
                    }
                    if (nameString) {
                        @synchronized (gMethodToNameMap) {
                            gMethodToNameMap[key] = nameString;
                        }
                        @synchronized (gNameToMethodMap) {
                            gNameToMethodMap[nameString] = key;
                        }
                    }
                }
            }
        }

        NSString *text = I2FConvertIl2CppStringToNSString(il2cppString);
        void *targetString = il2cppString;

        if (text.length > 0 && I2FShouldLogText(text)) {
            [[I2FTextLogManager sharedManager] appendText:text rvaString:(nameString ?: @"")];
            NSLog(@"[I2FTrans] set_text hit %@ len=%lu", I2FShortenTextForLog(text), (unsigned long)text.length);

            BOOL enqueued = NO;
            NSString *translated = [[I2FTranslationManager sharedManager] translationForOriginal:text
                                                                                        context:nameString
                                                                                     didEnqueue:&enqueued];
            if (translated.length > 0) {
                NSLog(@"[I2FTrans] set_text replace %@ -> %@", I2FShortenTextForLog(text), I2FShortenTextForLog(translated));
                void *newString = I2FCreateIl2CppStringFromNSString(translated);
                if (newString) {
                    targetString = newString;
                }
            } else if (enqueued) {
                NSLog(@"[I2FTrans] set_text enqueued for translation %@", I2FShortenTextForLog(text));
                I2FPendingRefresh *refresh = [[I2FPendingRefresh alloc] init];
                refresh.targetPointer = [NSValue valueWithPointer:self];
                refresh.methodKey = key;
                @synchronized (gPendingRefreshMap) {
                    gPendingRefreshMap[text] = refresh;
                }
            }
        }

        I2FSetTextOriginalFunc orig = (I2FSetTextOriginalFunc)(origPtrValue.pointerValue);
        if (orig) {
            NSLog(@"[I2FTrans] set_text orig");
            orig(self, targetString, method);
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
        gPendingRefreshMap = [NSMutableDictionary dictionary];
        gSlotToOriginalMap = [NSMutableDictionary dictionary];
        gNameToSlotMap = [NSMutableDictionary dictionary];
        gOriginalPointerToNameMap = [NSMutableDictionary dictionary];

        __weak typeof(self) weakSelf = self;
        [I2FTranslationManager sharedManager].translationDidUpdate = ^(I2FTranslationRecord *record) {
            (void)weakSelf;
            if (record.original.length == 0 || record.translated.length == 0) {
                return;
            }
            I2FPendingRefresh *refresh = nil;
            @synchronized (gPendingRefreshMap) {
                refresh = gPendingRefreshMap[record.original];
                if (refresh) {
                    [gPendingRefreshMap removeObjectForKey:record.original];
                }
            }
            if (!refresh) {
                return;
            }
            void *target = refresh.targetPointer.pointerValue;
            NSValue *methodKey = refresh.methodKey;
            if (!target || !methodKey) {
                return;
            }

            NSValue *origPtrValue = nil;
            @synchronized (gMethodToOriginalMap) {
                origPtrValue = gMethodToOriginalMap[methodKey];
            }
            if (!origPtrValue) {
                return;
            }

            void *newString = I2FCreateIl2CppStringFromNSString(record.translated);
            if (!newString) {
                return;
            }

            I2FSetTextOriginalFunc orig = (I2FSetTextOriginalFunc)(origPtrValue.pointerValue);
            if (!orig) {
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                orig(target, newString, methodKey.pointerValue);
            });
        };
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
        BOOL hasName = (fullName.length > 0);

        I2FTargetSpec spec;
        BOOL parsedName = hasName ? I2FParseTarget(fullName, &spec) : NO;

        uint64_t slotOffset = 0;
        uint64_t origOffset = 0;
        uint64_t rvaOffset = 0;
        BOOL hasSlotOffset = I2FParseOffsetValue(entry[@"slot_offset"] ?: entry[@"slotOffset"] ?: entry[@"set_text_new_offset"] ?: entry[@"new_offset"], &slotOffset);
        BOOL hasOrigOffset = I2FParseOffsetValue(entry[@"orig_offset"] ?: entry[@"origOffset"] ?: entry[@"set_text_orig_offset"] ?: entry[@"impl_offset"], &origOffset);
        BOOL hasRvaOffset = I2FParseOffsetValue(entry[@"rva"], &rvaOffset);
        if (!hasName && !hasSlotOffset && !hasRvaOffset) {
            NSLog(@"[I2FIl2CppTextHookManager] skip entry missing name/rva/slot %@", entry);
            continue;
        }

        if (hasName) {
            @synchronized (gNameToMethodMap) {
                if (gNameToMethodMap[fullName] != nil) {
                    continue;
                }
            }
            NSValue *existingSlot = nil;
            @synchronized (gNameToSlotMap) {
                existingSlot = gNameToSlotMap[fullName];
            }
            if (existingSlot) {
                continue;
            }
        }

        [I2FConfigManager setLastInstallingHookEntry:entry];

        if (hasSlotOffset) {
            uintptr_t base = (uintptr_t)Variables::info.address;
            if (base == 0) {
                NSLog(@"[I2FIl2CppTextHookManager] base not ready for %@", fullName);
                [I2FConfigManager setLastInstallingHookEntry:nil];
                continue;
            }
            void **slotPtr = (void **)(base + slotOffset);
            if (!slotPtr) {
                NSLog(@"[I2FIl2CppTextHookManager] invalid slot pointer for %@", fullName);
                [I2FConfigManager setLastInstallingHookEntry:nil];
                continue;
            }
            void *origPtr = hasOrigOffset ? (void *)(base + origOffset) : *slotPtr;
            if (!origPtr) {
                NSLog(@"[I2FIl2CppTextHookManager] missing original pointer for %@", fullName);
                [I2FConfigManager setLastInstallingHookEntry:nil];
                continue;
            }

            void *expected = origPtr;
            BOOL swapped = __sync_bool_compare_and_swap(slotPtr, expected, (void *)&I2FSetterReplacement);
            if (!swapped) {
                if (*slotPtr != (void *)&I2FSetterReplacement) {
                    NSLog(@"[I2FIl2CppTextHookManager] Offset hook failed %@, pointer write rejected", fullName);
                    [I2FConfigManager setLastInstallingHookEntry:nil];
                    continue;
                }
            }

            NSValue *slotKey = [NSValue valueWithPointer:slotPtr];
            NSValue *origValue = [NSValue valueWithPointer:origPtr];
            @synchronized (gSlotToOriginalMap) {
                gSlotToOriginalMap[slotKey] = origValue;
            }
            @synchronized (gNameToSlotMap) {
                if (hasName) {
                    gNameToSlotMap[fullName] = slotKey;
                }
            }
            @synchronized (gOriginalPointerToNameMap) {
                if (hasName) {
                    gOriginalPointerToNameMap[origValue] = fullName;
                }
            }

            I2FResolvedMethod resolvedForOffset = {0};
            if (parsedName && I2FResolveMethod(spec, &resolvedForOffset)) {
                NSValue *methodKey = [NSValue valueWithPointer:resolvedForOffset.methodInfo];
                @synchronized (gMethodToOriginalMap) {
                    gMethodToOriginalMap[methodKey] = origValue;
                }
                @synchronized (gMethodToNameMap) {
                    if (hasName) {
                        gMethodToNameMap[methodKey] = fullName;
                    }
                }
                @synchronized (gNameToMethodMap) {
                    if (hasName) {
                        gNameToMethodMap[fullName] = methodKey;
                    }
                }
            } else {
                NSLog(@"[I2FIl2CppTextHookManager] resolve failed for %@ (offset hook still installed)", fullName);
            }

            @synchronized (gInstalledNames) {
                if (hasName) {
                    [gInstalledNames addObject:fullName];
                }
            }

            NSLog(@"[I2FIl2CppTextHookManager] Offset hook success %@ slot=%p -> orig=%p", hasName ? fullName : @"(anonymous)", slotPtr, origPtr);
            [I2FConfigManager setLastInstallingHookEntry:nil];
            continue;
        }

        I2FResolvedMethod resolved = {0};
        BOOL resolvedOK = NO;
        if (hasRvaOffset) {
            uintptr_t base = (uintptr_t)Variables::info.address;
            if (base != 0) {
                void *targetPointer = (void *)(base + rvaOffset);
                resolvedOK = I2FResolveMethodByPointer(targetPointer, &resolved);
            }
        }
        if (!resolvedOK && parsedName) {
            resolvedOK = I2FResolveMethod(spec, &resolved);
        }
        if (!resolvedOK) {
            NSLog(@"[I2FIl2CppTextHookManager] resolve failed for %@", hasName ? fullName : @"(anonymous entry)");
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
        if (hasRvaOffset) {
            uintptr_t base = (uintptr_t)Variables::info.address;
            if (base != 0) {
                expected = (void *)(base + rvaOffset);
            }
        }
        BOOL swapped = __sync_bool_compare_and_swap(methodPointerField, expected, (void *)&I2FSetterReplacement);
        if (!swapped) {
            // 如果已经被替换成我们的函数，视为成功；否则失败。
            if (*methodPointerField != (void *)&I2FSetterReplacement) {
                NSLog(@"[I2FIl2CppTextHookManager] Hook failed %@, pointer write rejected", fullName);
                [I2FConfigManager setLastInstallingHookEntry:nil];
                continue;
            }
        }

        NSValue *expectedValue = [NSValue valueWithPointer:expected];
        @synchronized (gMethodToOriginalMap) {
            gMethodToOriginalMap[methodKey] = expectedValue;
        }
        @synchronized (gMethodToNameMap) {
            if (hasName) {
                gMethodToNameMap[methodKey] = fullName;
            }
        }
        @synchronized (gNameToMethodMap) {
            if (hasName) {
                gNameToMethodMap[fullName] = methodKey;
            }
        }
        @synchronized (gOriginalPointerToNameMap) {
            if (hasName) {
                gOriginalPointerToNameMap[expectedValue] = fullName;
            }
        }
        @synchronized (gInstalledNames) {
            if (hasName) {
                [gInstalledNames addObject:fullName];
            }
        }

        NSLog(@"[I2FIl2CppTextHookManager] Hook success %@ @ %p -> %p", hasName ? fullName : @"(anonymous)", resolved.methodPointer, methodPointerField);
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

        NSValue *slotValue = nil;
        @synchronized (gNameToSlotMap) {
            slotValue = gNameToSlotMap[fullName];
        }
        if (slotValue) {
            NSValue *origSlotValue = nil;
            @synchronized (gSlotToOriginalMap) {
                origSlotValue = gSlotToOriginalMap[slotValue];
            }
            void **slotPtr = (void **)slotValue.pointerValue;
            if (slotPtr && origSlotValue) {
                if (*slotPtr == (void *)&I2FSetterReplacement) {
                    *slotPtr = origSlotValue.pointerValue;
                    NSLog(@"[I2FIl2CppTextHookManager] Offset unhook success %@ @ %p", fullName, slotPtr);
                } else {
                    NSLog(@"[I2FIl2CppTextHookManager] Offset unhook skipped %@ (pointer already changed)", fullName);
                }
            }
            @synchronized (gSlotToOriginalMap) {
                [gSlotToOriginalMap removeObjectForKey:slotValue];
            }
            @synchronized (gNameToSlotMap) {
                [gNameToSlotMap removeObjectForKey:fullName];
            }
            if (origSlotValue) {
                @synchronized (gOriginalPointerToNameMap) {
                    [gOriginalPointerToNameMap removeObjectForKey:origSlotValue];
                }
            }
        }

        NSValue *methodKey = nil;
        @synchronized (gNameToMethodMap) {
            methodKey = gNameToMethodMap[fullName];
        }
        if (methodKey) {
            NSValue *origPtrValue = nil;
            @synchronized (gMethodToOriginalMap) {
                origPtrValue = gMethodToOriginalMap[methodKey];
            }
            if (origPtrValue) {
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
                @synchronized (gOriginalPointerToNameMap) {
                    [gOriginalPointerToNameMap removeObjectForKey:origPtrValue];
                }
            }
        }
        @synchronized (gInstalledNames) {
            [gInstalledNames removeObject:fullName];
        }
    }
}

@end
