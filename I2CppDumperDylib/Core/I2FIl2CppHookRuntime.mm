#import "I2FIl2CppHookRuntime.h"

#import <stdlib.h>
#import <string.h>

#import "Il2cpp.hpp"

@implementation I2FIl2CppHookRuntime

+ (BOOL)apiReady {
    return Variables::IL2CPP::il2cpp_domain_get
           && Variables::IL2CPP::il2cpp_domain_get_assemblies
           && Variables::IL2CPP::il2cpp_assembly_get_image
           && Variables::IL2CPP::il2cpp_class_from_name
           && Variables::IL2CPP::il2cpp_class_get_methods
           && Variables::IL2CPP::il2cpp_method_get_name;
}

+ (void)attachThreadIfNeeded {
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

+ (BOOL)parseOffsetValue:(id)value outValue:(uint64_t *)outValue {
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

+ (BOOL)parseTarget:(NSString *)fullName intoSpec:(I2FTargetSpec *)outSpec {
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

+ (BOOL)resolveMethodForSpec:(const I2FTargetSpec &)spec result:(I2FResolvedMethod *)outResolved {
    if (!outResolved) {
        return NO;
    }
    if (![self apiReady]) {
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

+ (BOOL)resolveMethodByPointer:(void *)targetPointer result:(I2FResolvedMethod *)outResolved {
    if (!outResolved || !targetPointer) {
        return NO;
    }
    if (![self apiReady]) {
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

+ (NSString *)convertIl2CppString:(void *)il2cppString {
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

+ (void *)createIl2CppStringFromNSString:(NSString *)string {
    if (string.length == 0 || !Variables::IL2CPP::il2cpp_string_new) {
        return nullptr;
    }

    const char *utf8 = [string UTF8String];
    if (!utf8) {
        return nullptr;
    }

    return Variables::IL2CPP::il2cpp_string_new(utf8);
}

+ (NSString *)shortenTextForLog:(NSString *)text {
    if (text.length <= 64) {
        return text;
    }
    return [[text substringToIndex:64] stringByAppendingString:@"..."];
}

+ (BOOL)shouldLogText:(NSString *)text {
    if (text.length == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ((c >= 0x4E00 && c <= 0x9FFF) ||    // CJK Unified Ideographs
            (c >= 0x3400 && c <= 0x4DBF) ||    // CJK Extension A
            (c >= 0xF900 && c <= 0xFAFF) ||    // CJK Compatibility Ideographs
            (c >= 0x20000 && c <= 0x2A6DF)) {  // CJK Extension B
            return YES;
        }
    }
    return NO;
}

+ (const void *)findImageNamed:(const std::vector<std::string> &)candidates {
    if (!Variables::IL2CPP::il2cpp_domain_get || !Variables::IL2CPP::il2cpp_domain_get_assemblies || !Variables::IL2CPP::il2cpp_assembly_get_image || !Variables::IL2CPP::il2cpp_image_get_name) {
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

    for (size_t i = 0; i < assemblyCount; i++) {
        const void *image = Variables::IL2CPP::il2cpp_assembly_get_image(assemblies[i]);
        if (!image) {
            continue;
        }

        const char *imgName = Variables::IL2CPP::il2cpp_image_get_name((void *)image);
        if (!imgName) {
            continue;
        }

        for (const std::string &name : candidates) {
            if (name.empty()) {
                continue;
            }
            if (strstr(imgName, name.c_str()) != nullptr) {
                return image;
            }
        }
    }

    return nullptr;
}

@end
