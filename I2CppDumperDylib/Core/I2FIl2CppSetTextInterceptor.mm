#import "I2FIl2CppSetTextInterceptor.h"

#import "I2FIl2CppHookRuntime.h"
#import "I2FIl2CppTextHookState.h"
#import "I2FTransFontPatcher.h"
#import "I2FTextLogManager.h"
#import "I2FTranslationManager.h"

typedef void (*I2FSetTextOriginalFunc)(void *self, void *il2cppString, const void *method);

static I2FTextHookPipelineOptions gPipelineOptions = {0};

static NSString *I2FExtractColorWrapped(NSString *text, NSString **outPrefix, NSString **outSuffix) {
    if (!text) {
        return nil;
    }

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\[color=[^\\]]+\\])(.+)(\\[/color\\])$"
                                                          options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                            error:nil];
    });
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges < 4) {
        return nil;
    }

    NSString *prefix = [text substringWithRange:[match rangeAtIndex:1]];
    NSString *inner = [text substringWithRange:[match rangeAtIndex:2]];
    NSString *suffix = [text substringWithRange:[match rangeAtIndex:3]];

    if (outPrefix) {
        *outPrefix = prefix;
    }
    if (outSuffix) {
        *outSuffix = suffix;
    }
    return inner;
}

static NSString *I2FEffectiveName(NSString *name) {
    return name.length > 0 ? name : @"";
}

static void I2FHandleTranslationUpdate(I2FTranslationRecord *record) {
    if (record.original.length == 0 || record.translated.length == 0) {
        return;
    }

    I2FIl2CppTextHookState *state = [I2FIl2CppTextHookState shared];
    I2FPendingRefresh *refresh = [state consumePendingRefreshForOriginal:record.original];
    if (!refresh) {
        return;
    }

    void *target = refresh.targetPointer.pointerValue;
    NSValue *methodKey = refresh.methodKey;
    NSString *prefix = refresh.prefix;
    NSString *suffix = refresh.suffix;
    if (!target || !methodKey) {
        return;
    }

    NSValue *origPtrValue = [state originalPointerForMethodKey:methodKey];
    if (!origPtrValue) {
        return;
    }

    NSString *finalTranslated = record.translated;
    if (prefix.length > 0 && suffix.length > 0) {
        finalTranslated = [NSString stringWithFormat:@"%@%@%@", prefix, record.translated, suffix];
    }

    void *newString = [I2FIl2CppHookRuntime createIl2CppStringFromNSString:finalTranslated];
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
}

void I2FSetterReplacement(void *self, void *il2cppString, const void *method) {
    @autoreleasepool {
        I2FIl2CppTextHookState *state = [I2FIl2CppTextHookState shared];
        NSValue *methodKey = [NSValue valueWithPointer:method];

        NSString *nameString = [state nameForMethodKey:methodKey];
        NSValue *origPtrValue = [state originalPointerForMethodKey:methodKey];

        if (!origPtrValue) {
            void *origFromMethod = method ? *((void **)method) : nullptr;
            if (origFromMethod) {
                NSValue *origKey = [NSValue valueWithPointer:origFromMethod];
                NSString *cachedName = [state nameForOriginalPointer:origKey];
                if (cachedName) {
                    origPtrValue = origKey;
                    if (!nameString) {
                        nameString = cachedName;
                    }
                    [state setOriginalPointer:origPtrValue forMethodKey:methodKey];
                    if (nameString) {
                        [state setName:nameString forMethodKey:methodKey];
                        [state setMethodKey:methodKey forName:nameString];
                    }
                }
            }
        }

        NSString *text = [I2FIl2CppHookRuntime convertIl2CppString:il2cppString];
        void *targetString = il2cppString;
        I2FTextHookPipelineOptions options = [I2FIl2CppSetTextInterceptor pipelineOptions];

        if (text.length > 0 && (options.logHits || options.translateText || options.applyFonts) && [I2FIl2CppHookRuntime shouldLogText:text]) {
            NSString *colorPrefix = nil;
            NSString *colorSuffix = nil;
            NSString *innerText = I2FExtractColorWrapped(text, &colorPrefix, &colorSuffix);
            NSString *effectiveOriginal = innerText.length > 0 ? innerText : text;

            if (options.applyFonts) {
                NSString *safeName = I2FEffectiveName(nameString);
                if (![[I2FTransFontPatcher shared] applyTMPFontIfNeededForInstance:self name:safeName]) {
                    if (![safeName containsString:@"FairyGUI"]) {
                        [[I2FTransFontPatcher shared] applyGenericSetFontIfAvailableForInstance:self name:safeName];
                    } else {
                        [[I2FTransFontPatcher shared] applyFairyGUIFontIfNeededForInstance:self name:safeName];
                    }
                }
            }

            if (options.logHits) {
                [[I2FTextLogManager sharedManager] appendText:text rvaString:(nameString ? : @"")];
                NSLog(@"[I2FTrans] set_text hit %@ len=%lu", [I2FIl2CppHookRuntime shortenTextForLog:text], (unsigned long)text.length);
            }

            if (options.translateText) {
                BOOL enqueued = NO;
                NSString *translated = [[I2FTranslationManager sharedManager] translationForOriginal:effectiveOriginal
                                                                                            context:nameString
                                                                                         didEnqueue:&enqueued];
                if (translated.length > 0) {
                    NSString *finalTranslated = translated;
                    if (colorPrefix.length > 0 && colorSuffix.length > 0) {
                        finalTranslated = [NSString stringWithFormat:@"%@%@%@", colorPrefix, translated, colorSuffix];
                    }
                    NSLog(@"[I2FTrans] set_text replace %@ -> %@", [I2FIl2CppHookRuntime shortenTextForLog:text], [I2FIl2CppHookRuntime shortenTextForLog:finalTranslated]);
                    void *newString = [I2FIl2CppHookRuntime createIl2CppStringFromNSString:finalTranslated];
                    if (newString) {
                        targetString = newString;
                    }
                } else if (enqueued) {
                    NSLog(@"[I2FTrans] set_text enqueued for translation %@", [I2FIl2CppHookRuntime shortenTextForLog:text]);
                    I2FPendingRefresh *refresh = [[I2FPendingRefresh alloc] init];
                    refresh.targetPointer = [NSValue valueWithPointer:self];
                    refresh.methodKey = methodKey;
                    refresh.prefix = colorPrefix;
                    refresh.suffix = colorSuffix;
                    [state setPendingRefresh:refresh forOriginal:effectiveOriginal];
                }
            }
        }

        I2FSetTextOriginalFunc orig = (I2FSetTextOriginalFunc)(origPtrValue.pointerValue);
        if (orig) {
            orig(self, targetString, method);
        }
    }
}

@implementation I2FIl2CppSetTextInterceptor

+ (void)initialize {
    if (self == [I2FIl2CppSetTextInterceptor class]) {
        gPipelineOptions = I2FDefaultTextHookPipelineOptions();
    }
}

+ (void)setPipelineOptions:(I2FTextHookPipelineOptions)options {
    gPipelineOptions = options;
}

+ (I2FTextHookPipelineOptions)pipelineOptions {
    return gPipelineOptions;
}

+ (void)installTranslationCallback {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __weak typeof(self) weakSelf = self;
        [I2FTranslationManager sharedManager].translationDidUpdate = ^(I2FTranslationRecord *record) {
            (void)weakSelf;
            I2FHandleTranslationUpdate(record);
        };
    });
}

@end
