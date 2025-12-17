#import "I2FIl2CppTextHookManager.h"

#import "Il2cpp.hpp"
#import "I2FConfigManager.h"
#import "I2FIl2CppHookRuntime.h"
#import "I2FIl2CppSetTextInterceptor.h"
#import "I2FIl2CppTextHookState.h"
#import "I2FTransFontPatcher.h"

typedef struct {
    NSString *fullName;
    BOOL hasName;
    BOOL parsedName;
    I2FTargetSpec spec;
    BOOL hasSlotOffset;
    uint64_t slotOffset;
    BOOL hasOrigOffset;
    uint64_t origOffset;
    BOOL hasRvaOffset;
    uint64_t rvaOffset;
} I2FHookEntry;

static I2FHookEntry I2FHookEntryFromDictionary(NSDictionary *entry) {
    I2FHookEntry hook = {0};
    hook.fullName = entry[@"name"];
    hook.hasName = hook.fullName.length > 0;
    hook.parsedName = hook.hasName ? [I2FIl2CppHookRuntime parseTarget:hook.fullName intoSpec:&hook.spec] : NO;
    hook.hasSlotOffset = [I2FIl2CppHookRuntime parseOffsetValue:(entry[@"slot_offset"] ?: entry[@"slotOffset"] ?: entry[@"set_text_new_offset"] ?: entry[@"new_offset"])
                                                       outValue:&hook.slotOffset];
    hook.hasOrigOffset = [I2FIl2CppHookRuntime parseOffsetValue:(entry[@"orig_offset"] ?: entry[@"origOffset"] ?: entry[@"set_text_orig_offset"] ?: entry[@"impl_offset"])
                                                       outValue:&hook.origOffset];
    hook.hasRvaOffset = [I2FIl2CppHookRuntime parseOffsetValue:entry[@"rva"] outValue:&hook.rvaOffset];
    return hook;
}

static NSArray<NSDictionary *> *I2FUniqueEntries(NSArray<NSDictionary *> *entries) {
    NSMutableArray<NSDictionary *> *unique = [NSMutableArray array];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
    for (NSDictionary *entry in entries) {
        NSString *name = entry[@"name"];
        if (name.length > 0) {
            if ([seenNames containsObject:name]) {
                continue;
            }
            [seenNames addObject:name];
        }
        [unique addObject:entry];
    }
    return unique;
}

static BOOL I2FInstallOffsetHook(const I2FHookEntry &hook, I2FIl2CppTextHookState *state) {
    uintptr_t base = (uintptr_t)Variables::info.address;
    if (base == 0) {
        NSLog(@"[I2FIl2CppTextHookManager] base not ready for %@", hook.fullName ?: @"(anonymous)");
        return NO;
    }

    void **slotPtr = (void **)(base + hook.slotOffset);
    if (!slotPtr) {
        NSLog(@"[I2FIl2CppTextHookManager] invalid slot pointer for %@", hook.fullName ?: @"(anonymous)");
        return NO;
    }

    void *origPtr = hook.hasOrigOffset ? (void *)(base + hook.origOffset) : *slotPtr;
    if (!origPtr) {
        NSLog(@"[I2FIl2CppTextHookManager] missing original pointer for %@", hook.fullName ?: @"(anonymous)");
        return NO;
    }

    void *expected = origPtr;
    BOOL swapped = __sync_bool_compare_and_swap(slotPtr, expected, (void *)&I2FSetterReplacement);
    if (!swapped && *slotPtr != (void *)&I2FSetterReplacement) {
        NSLog(@"[I2FIl2CppTextHookManager] Offset hook failed %@, pointer write rejected", hook.fullName ?: @"(anonymous)");
        return NO;
    }

    NSValue *slotKey = [NSValue valueWithPointer:slotPtr];
    NSValue *origValue = [NSValue valueWithPointer:origPtr];
    [state setSlot:slotKey original:origValue forName:hook.hasName ? hook.fullName : nil];
    if (hook.hasName) {
        [state setName:hook.fullName forOriginalPointer:origValue];
    }

    if (hook.parsedName) {
        I2FResolvedMethod resolved = {0};
        if ([I2FIl2CppHookRuntime resolveMethodForSpec:hook.spec result:&resolved]) {
            NSValue *methodKey = [NSValue valueWithPointer:resolved.methodInfo];
            [state setOriginalPointer:origValue forMethodKey:methodKey];
            if (hook.hasName) {
                [state setName:hook.fullName forMethodKey:methodKey];
                [state setMethodKey:methodKey forName:hook.fullName];
            }
        } else {
            NSLog(@"[I2FIl2CppTextHookManager] resolve failed for %@ (offset hook still installed)", hook.hasName ? hook.fullName : @"(anonymous)");
        }
    }

    if (hook.hasName) {
        [state recordInstalledName:hook.fullName];
    }

    NSLog(@"[I2FIl2CppTextHookManager] Offset hook success %@ slot=%p -> orig=%p", hook.hasName ? hook.fullName : @"(anonymous)", slotPtr, origPtr);
    return YES;
}

static BOOL I2FInstallResolvedHook(const I2FHookEntry &hook, I2FIl2CppTextHookState *state) {
    I2FResolvedMethod resolved = {0};
    BOOL resolvedOK = NO;

    if (hook.hasRvaOffset) {
        uintptr_t base = (uintptr_t)Variables::info.address;
        if (base != 0) {
            void *targetPointer = (void *)(base + hook.rvaOffset);
            resolvedOK = [I2FIl2CppHookRuntime resolveMethodByPointer:targetPointer result:&resolved];
        }
    }

    if (!resolvedOK && hook.parsedName) {
        resolvedOK = [I2FIl2CppHookRuntime resolveMethodForSpec:hook.spec result:&resolved];
    }

    if (!resolvedOK) {
        NSLog(@"[I2FIl2CppTextHookManager] resolve failed for %@", hook.hasName ? hook.fullName : @"(anonymous entry)");
        return NO;
    }

    NSValue *methodKey = [NSValue valueWithPointer:resolved.methodInfo];
    if ([state originalPointerForMethodKey:methodKey]) {
        if (hook.hasName) {
            [state setMethodKey:methodKey forName:hook.fullName];
        }
        return YES;
    }

    void **methodPointerField = (void **)resolved.methodInfo;
    void *expected = resolved.methodPointer;
    if (hook.hasRvaOffset) {
        uintptr_t base = (uintptr_t)Variables::info.address;
        if (base != 0) {
            expected = (void *)(base + hook.rvaOffset);
        }
    }

    BOOL swapped = __sync_bool_compare_and_swap(methodPointerField, expected, (void *)&I2FSetterReplacement);
    if (!swapped && *methodPointerField != (void *)&I2FSetterReplacement) {
        NSLog(@"[I2FIl2CppTextHookManager] Hook failed %@, pointer write rejected", hook.hasName ? hook.fullName : @"(anonymous)");
        return NO;
    }

    NSValue *expectedValue = [NSValue valueWithPointer:expected];
    [state setOriginalPointer:expectedValue forMethodKey:methodKey];
    if (hook.hasName) {
        [state setName:hook.fullName forMethodKey:methodKey];
        [state setMethodKey:methodKey forName:hook.fullName];
        [state setName:hook.fullName forOriginalPointer:expectedValue];
        [state recordInstalledName:hook.fullName];
    }

    NSLog(@"[I2FIl2CppTextHookManager] Hook success %@ @ %p -> %p", hook.hasName ? hook.fullName : @"(anonymous)", resolved.methodPointer, methodPointerField);
    return YES;
}

@implementation I2FIl2CppTextHookManager

+ (void)initialize {
    if (self == [I2FIl2CppTextHookManager class]) {
        (void)[I2FIl2CppTextHookState shared];
        (void)[I2FTransFontPatcher shared];
        [I2FIl2CppSetTextInterceptor installTranslationCallback];
        [I2FIl2CppSetTextInterceptor setPipelineOptions:I2FDefaultTextHookPipelineOptions()];
    }
}

+ (void)setPipelineOptions:(I2FTextHookPipelineOptions)options {
    [I2FIl2CppSetTextInterceptor setPipelineOptions:options];
}

+ (I2FTextHookPipelineOptions)pipelineOptions {
    return [I2FIl2CppSetTextInterceptor pipelineOptions];
}

+ (void)installHooksWithEntries:(NSArray<NSDictionary *> *)entries {
    if (entries.count == 0) {
        return;
    }

    [I2FIl2CppHookRuntime attachThreadIfNeeded];

    NSArray<NSDictionary *> *uniqueEntries = I2FUniqueEntries(entries);
    NSLog(@"[I2FIl2CppTextHookManager] installHooks count=%lu, entries=%@", (unsigned long)uniqueEntries.count, uniqueEntries);

    I2FIl2CppTextHookState *state = [I2FIl2CppTextHookState shared];

    for (NSDictionary *entry in uniqueEntries) {
        I2FHookEntry hook = I2FHookEntryFromDictionary(entry);
        if (!hook.hasName && !hook.hasSlotOffset && !hook.hasRvaOffset) {
            NSLog(@"[I2FIl2CppTextHookManager] skip entry missing name/rva/slot %@", entry);
            continue;
        }

        if (hook.hasName) {
            if ([state methodKeyForName:hook.fullName] || [state slotForName:hook.fullName]) {
                continue;
            }
        }

        [I2FConfigManager setLastInstallingHookEntry:entry];

        BOOL installed = NO;
        if (hook.hasSlotOffset) {
            installed = I2FInstallOffsetHook(hook, state);
        } else {
            installed = I2FInstallResolvedHook(hook, state);
        }

        if (!installed && hook.hasName) {
            [state removeInstalledName:hook.fullName];
        }

        [I2FConfigManager setLastInstallingHookEntry:nil];
    }
}

+ (void)uninstallHooksWithEntries:(NSArray<NSDictionary *> *)entries {
    if (entries.count == 0) {
        return;
    }

    I2FIl2CppTextHookState *state = [I2FIl2CppTextHookState shared];

    for (NSDictionary *entry in entries) {
        NSString *fullName = entry[@"name"];
        if (fullName.length == 0) {
            continue;
        }

        NSValue *slotValue = [state slotForName:fullName];
        if (slotValue) {
            NSValue *origSlotValue = [state originalForSlot:slotValue];
            void **slotPtr = (void **)slotValue.pointerValue;
            if (slotPtr && origSlotValue) {
                if (*slotPtr == (void *)&I2FSetterReplacement) {
                    *slotPtr = origSlotValue.pointerValue;
                    NSLog(@"[I2FIl2CppTextHookManager] Offset unhook success %@ @ %p", fullName, slotPtr);
                } else {
                    NSLog(@"[I2FIl2CppTextHookManager] Offset unhook skipped %@ (pointer already changed)", fullName);
                }
            }

            [state removeSlotForName:fullName];
            if (origSlotValue) {
                [state removeNameForOriginalPointer:origSlotValue];
            }
        }

        NSValue *methodKey = [state methodKeyForName:fullName];
        if (methodKey) {
            NSValue *origPtrValue = [state originalPointerForMethodKey:methodKey];
            if (origPtrValue) {
                void **methodPointerField = (void **)methodKey.pointerValue;
                if (methodPointerField && *methodPointerField == (void *)&I2FSetterReplacement) {
                    *methodPointerField = origPtrValue.pointerValue;
                    NSLog(@"[I2FIl2CppTextHookManager] Unhook success %@ @ %p", fullName, methodPointerField);
                } else {
                    NSLog(@"[I2FIl2CppTextHookManager] Unhook skipped %@ (pointer already changed)", fullName);
                }

                [state setOriginalPointer:nil forMethodKey:methodKey];
                [state setName:nil forMethodKey:methodKey];
                [state removeNameForOriginalPointer:origPtrValue];
            }

            [state setMethodKey:nil forName:fullName];
        }

        [state removeInstalledName:fullName];
    }
}

@end
