#import "I2FTransFontPatcher.h"

#import "I2FIl2CppHookRuntime.h"
#import "Il2cpp.hpp"

@implementation I2FTransFontPatcher {
    dispatch_once_t _uiFontResolveOnce;
    dispatch_once_t _tmpFontResolveOnce;
    dispatch_once_t _fgUIFontInitOnce;
    dispatch_once_t _fgUIFontRegisterOnce;

    void *_uiFontObject;
    void *_uiFontSetMethodInfo;
    void *_uiFontSetMethodPtr;

    void *_tmpFontAssetObject;
    void *_tmpSetFontMethodInfo;
    void *_tmpSetFontMethodPtr;

    void *_fgUITextFormatGet;
    void *_fgUITextFormatSet;
    void *_fgUITextFormatFontField;

    NSString *_uiFontName;
    BOOL _loggedUIFontReady;
    BOOL _loggedTMPReady;
    BOOL _loggedGenericApply;
    BOOL _loggedFGUIFontInit;
    BOOL _loggedFGUITextFormat;
    BOOL _loggedFGUIFontRegister;

    NSMutableDictionary<NSString *, NSValue *> *_setFontMethodCache;
    NSMutableSet<NSString *> *_setFontFailureCache;
}

+ (instancetype)shared {
    static I2FTransFontPatcher *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[I2FTransFontPatcher alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _setFontMethodCache = [NSMutableDictionary dictionary];
        _setFontFailureCache = [NSMutableSet set];
    }
    return self;
}

- (void)ensureUIFont {
    dispatch_once(&_uiFontResolveOnce, ^{
        if (![I2FIl2CppHookRuntime apiReady]) {
            NSLog(@"[I2FTransFont] UIFont init skipped: IL2CPP API not ready");
            return;
        }

        std::vector<std::string> coreImages = { "UnityEngine.CoreModule", "UnityEngine", "UnityEngine.CoreModule.dll", "UnityEngine.dll" };
        const void *coreImage = [I2FIl2CppHookRuntime findImageNamed:coreImages];
        if (!coreImage) {
            NSLog(@"[I2FTransFont] UIFont init failed: UnityEngine image not found");
            return;
        }

        void *fontClass = Variables::IL2CPP::il2cpp_class_from_name(coreImage, "UnityEngine", "Font");
        if (!fontClass) {
            NSLog(@"[I2FTransFont] UIFont init failed: UnityEngine.Font not found");
            return;
        }

        void *createMethodInfo = nullptr;
        if (Variables::IL2CPP::il2cpp_class_get_method_from_name) {
            createMethodInfo = Variables::IL2CPP::il2cpp_class_get_method_from_name(fontClass, "CreateDynamicFontFromOSFont", 2);
            if (!createMethodInfo) {
                createMethodInfo = Variables::IL2CPP::il2cpp_class_get_method_from_name(fontClass, "CreateDynamicFontFromOSFont", 1);
            }
        }
        if (!createMethodInfo) {
            NSLog(@"[I2FTransFont] UIFont init failed: CreateDynamicFontFromOSFont not found");
            return;
        }

        void *createMethodPtr = *(void **)createMethodInfo;
        if (!createMethodPtr || !Variables::IL2CPP::il2cpp_string_new) {
            NSLog(@"[I2FTransFont] UIFont init failed: method ptr or string_new missing");
            return;
        }

        const char *fontNames[] = { "PingFang SC", "PingFangSC-Regular", "Arial Unicode MS", "ArialMT", "Helvetica" };
        for (size_t i = 0; i < sizeof(fontNames) / sizeof(fontNames[0]); i++) {
            void *nameStr = Variables::IL2CPP::il2cpp_string_new(fontNames[i]);
            if (!nameStr) {
                continue;
            }

            typedef void * (*CreateFontFunc2)(void *, int32_t, const void *);
            typedef void * (*CreateFontFunc1)(void *, const void *);
            void *fontObj = nullptr;

            if (Variables::IL2CPP::il2cpp_method_get_param_count && Variables::IL2CPP::il2cpp_method_get_param_count(createMethodInfo) == 2) {
                fontObj = ((CreateFontFunc2)createMethodPtr)(nameStr, 18, createMethodInfo);
            } else {
                fontObj = ((CreateFontFunc1)createMethodPtr)(nameStr, createMethodInfo);
            }

            if (fontObj) {
                _uiFontObject = fontObj;
                _uiFontName = [NSString stringWithUTF8String:fontNames[i]];
                NSLog(@"[I2FTransFont] UIFont created with name %@", _uiFontName);
                break;
            }
        }

        if (!_uiFontObject) {
            NSLog(@"[I2FTransFont] UIFont init failed: all font candidates rejected");
            return;
        }

        std::vector<std::string> uiImages = { "UnityEngine.UI", "UnityEngine.UI.dll" };
        const void *uiImage = [I2FIl2CppHookRuntime findImageNamed:uiImages];
        if (!uiImage) {
            NSLog(@"[I2FTransFont] UIFont init failed: UnityEngine.UI image not found");
            return;
        }

        void *textClass = Variables::IL2CPP::il2cpp_class_from_name(uiImage, "UnityEngine.UI", "Text");
        if (!textClass) {
            NSLog(@"[I2FTransFont] UIFont init failed: UnityEngine.UI.Text not found");
            return;
        }

        if (Variables::IL2CPP::il2cpp_class_get_method_from_name) {
            _uiFontSetMethodInfo = Variables::IL2CPP::il2cpp_class_get_method_from_name(textClass, "set_font", 1);
        }
        if (_uiFontSetMethodInfo) {
            _uiFontSetMethodPtr = *(void **)_uiFontSetMethodInfo;
        } else {
            NSLog(@"[I2FTransFont] UIFont init failed: Text.set_font not found");
        }

        if (_uiFontObject && _uiFontSetMethodPtr && !_loggedUIFontReady) {
            _loggedUIFontReady = YES;
            NSLog(@"[I2FTransFont] UIFont ready %@ set_font resolved", _uiFontName ?: @"(unknown)");
        }
    });
}

- (void)registerFairyGUIFontsIfNeeded {
    dispatch_once(&_fgUIFontRegisterOnce, ^{
        [self ensureUIFont];
        if (!_uiFontName || _uiFontName.length == 0 || ![I2FIl2CppHookRuntime apiReady]) {
            return;
        }

        std::vector<std::string> fgImages = { "FairyGUI", "FairyGUI.dll" };
        const void *fgImage = [I2FIl2CppHookRuntime findImageNamed:fgImages];
        if (!fgImage) {
            return;
        }

        if (!Variables::IL2CPP::il2cpp_class_from_name || !Variables::IL2CPP::il2cpp_class_get_method_from_name || !Variables::IL2CPP::il2cpp_string_new) {
            return;
        }

        void *fontManagerClass = Variables::IL2CPP::il2cpp_class_from_name(fgImage, "FairyGUI", "FontManager");
        if (!fontManagerClass) {
            return;
        }

        BOOL preferTwoArgs = YES;
        void *registerMethod = Variables::IL2CPP::il2cpp_class_get_method_from_name(fontManagerClass, "RegisterFont", 2);
        if (!registerMethod) {
            preferTwoArgs = NO;
            registerMethod = Variables::IL2CPP::il2cpp_class_get_method_from_name(fontManagerClass, "RegisterFont", 1);
        }
        if (!registerMethod) {
            return;
        }

        void *registerPtr = *(void **)registerMethod;
        if (!registerPtr) {
            return;
        }

        int paramCount = preferTwoArgs ? 2 : 1;
        if (Variables::IL2CPP::il2cpp_method_get_param_count) {
            paramCount = Variables::IL2CPP::il2cpp_method_get_param_count(registerMethod);
        }

        void *fontNameStr = Variables::IL2CPP::il2cpp_string_new([_uiFontName UTF8String]);
        if (!fontNameStr) {
            return;
        }

        if (paramCount <= 1) {
            typedef void (*RegisterFont1)(void *, const void *);
            ((RegisterFont1)registerPtr)(fontNameStr, registerMethod);
        } else {
            typedef void (*RegisterFont2)(void *, void *, const void *);
            ((RegisterFont2)registerPtr)(fontNameStr, nullptr, registerMethod);
        }

        if (!_loggedFGUIFontRegister) {
            _loggedFGUIFontRegister = YES;
            NSLog(@"[I2FTransFont] FairyGUI FontManager.RegisterFont %@", _uiFontName);
        }
    });
}

- (void)ensureTMPFontAsset {
    dispatch_once(&_tmpFontResolveOnce, ^{
        [self ensureUIFont];
        if (!_uiFontObject || ![I2FIl2CppHookRuntime apiReady]) {
            return;
        }

        dispatch_once(&_fgUIFontInitOnce, ^{
            std::vector<std::string> fgImages = { "FairyGUI", "FairyGUI.dll" };
            const void *fgImage = [I2FIl2CppHookRuntime findImageNamed:fgImages];
            if (fgImage && Variables::IL2CPP::il2cpp_class_from_name && Variables::IL2CPP::il2cpp_field_get_name) {
                void *uiConfigClass = Variables::IL2CPP::il2cpp_class_from_name(fgImage, "FairyGUI", "UIConfig");
                if (uiConfigClass && Variables::IL2CPP::il2cpp_field_static_set_value && Variables::IL2CPP::il2cpp_class_get_field_from_name) {
                    const char *fieldName = "defaultFont";
                    void *field = Variables::IL2CPP::il2cpp_class_get_field_from_name(uiConfigClass, fieldName);
                    if (field && Variables::IL2CPP::il2cpp_string_chars && Variables::IL2CPP::il2cpp_string_new) {
                        NSString *fallbackName = _uiFontName ?: @"Arial Unicode MS";
                        void *fontNameStr = Variables::IL2CPP::il2cpp_string_new([fallbackName UTF8String]);
                        Variables::IL2CPP::il2cpp_field_static_set_value(field, fontNameStr);
                        if (!_loggedFGUIFontInit) {
                            _loggedFGUIFontInit = YES;
                            NSLog(@"[I2FTransFont] FairyGUI UIConfig.defaultFont set to %@", fallbackName);
                        }
                    }
                }

                if (Variables::IL2CPP::il2cpp_class_get_method_from_name) {
                    void *textFieldClass = Variables::IL2CPP::il2cpp_class_from_name(fgImage, "FairyGUI", "TextField");
                    if (textFieldClass) {
                        _fgUITextFormatGet = Variables::IL2CPP::il2cpp_class_get_method_from_name(textFieldClass, "get_textFormat", 0);
                        _fgUITextFormatSet = Variables::IL2CPP::il2cpp_class_get_method_from_name(textFieldClass, "set_textFormat", 1);
                    }
                }

                if (Variables::IL2CPP::il2cpp_class_get_field_from_name) {
                    void *textFormatClass = Variables::IL2CPP::il2cpp_class_from_name(fgImage, "FairyGUI", "TextFormat");
                    if (textFormatClass) {
                        _fgUITextFormatFontField = Variables::IL2CPP::il2cpp_class_get_field_from_name(textFormatClass, "font");
                    }
                }
            }
        });

        [self registerFairyGUIFontsIfNeeded];

        std::vector<std::string> tmpImages = { "Unity.TextMeshPro", "Unity.TextMeshPro.dll", "Unity.TextMeshPro.fnm.dll", "Unity.TextMeshPro" };
        const void *tmpImage = [I2FIl2CppHookRuntime findImageNamed:tmpImages];
        if (!tmpImage) {
            return;
        }

        void *fontAssetClass = Variables::IL2CPP::il2cpp_class_from_name(tmpImage, "TMPro", "TMP_FontAsset");
        if (!fontAssetClass) {
            return;
        }

        void *createMethod = nullptr;
        if (Variables::IL2CPP::il2cpp_class_get_method_from_name) {
            createMethod = Variables::IL2CPP::il2cpp_class_get_method_from_name(fontAssetClass, "CreateFontAsset", 1);
        }
        if (!createMethod) {
            return;
        }

        void *createPtr = *(void **)createMethod;
        if (!createPtr) {
            return;
        }

        typedef void * (*CreateTmpAssetFunc)(void *, const void *);
        _tmpFontAssetObject = ((CreateTmpAssetFunc)createPtr)(_uiFontObject, createMethod);
        if (!_tmpFontAssetObject) {
            return;
        }

        void *tmpTextClass = Variables::IL2CPP::il2cpp_class_from_name(tmpImage, "TMPro", "TMP_Text");
        if (!tmpTextClass) {
            return;
        }

        if (Variables::IL2CPP::il2cpp_class_get_method_from_name) {
            _tmpSetFontMethodInfo = Variables::IL2CPP::il2cpp_class_get_method_from_name(tmpTextClass, "set_font", 1);
        }
        if (_tmpSetFontMethodInfo) {
            _tmpSetFontMethodPtr = *(void **)_tmpSetFontMethodInfo;
        }

        if (_tmpFontAssetObject && _tmpSetFontMethodPtr && !_loggedTMPReady) {
            _loggedTMPReady = YES;
            NSLog(@"[I2FTransFont] TMP fallback font asset ready");
        }
    });
}

- (BOOL)applyTMPFontIfNeededForInstance:(void *)instance name:(NSString *)nameString {
    NSLog(@"[I2FTransFont] TMP apply attempt name=%@", nameString);
    if (!instance || nameString.length == 0) {
        NSLog(@"[I2FTransFont] TMP skip: missing self/name");
        return NO;
    }
    if (![nameString containsString:@"TMPro"] && ![nameString containsString:@"TextMeshPro"]) {
        NSLog(@"[I2FTransFont] TMP skip: name not TMP");
        return NO;
    }

    [self ensureTMPFontAsset];
    if (!_tmpFontAssetObject || !_tmpSetFontMethodPtr || !_tmpSetFontMethodInfo) {
        NSLog(@"[I2FTransFont] TMP skip: asset/method not ready");
        return NO;
    }

    typedef void (*SetTMPFontFunc)(void *, void *, const void *);
    SetTMPFontFunc func = (SetTMPFontFunc)_tmpSetFontMethodPtr;
    func(instance, _tmpFontAssetObject, _tmpSetFontMethodInfo);
    NSLog(@"[I2FTransFont] TMP set_font applied %@", nameString);
    return YES;
}

- (BOOL)applyGenericSetFontIfAvailableForInstance:(void *)instance name:(NSString *)fullName {
    NSLog(@"[I2FTransFont] Generic set_font attempt name=%@", fullName);
    if (!instance || fullName.length == 0) {
        NSLog(@"[I2FTransFont] Generic skip: missing self/name");
        return NO;
    }
    if (![I2FIl2CppHookRuntime apiReady]) {
        NSLog(@"[I2FTransFont] Generic skip: API not ready");
        return NO;
    }

    if ([_setFontFailureCache containsObject:fullName]) {
        NSLog(@"[I2FTransFont] Generic skip: failure cached");
        return NO;
    }

    NSValue *cachedMethod = nil;
    @synchronized (_setFontMethodCache) {
        cachedMethod = _setFontMethodCache[fullName];
    }
    void *methodInfo = cachedMethod.pointerValue;

    if (!methodInfo) {
        I2FTargetSpec spec;
        if (![I2FIl2CppHookRuntime parseTarget:fullName intoSpec:&spec]) {
            NSLog(@"[I2FTransFont] Generic skip: parse target failed");
            return NO;
        }

        void *domain = Variables::IL2CPP::il2cpp_domain_get ? Variables::IL2CPP::il2cpp_domain_get() : nullptr;
        if (!domain || !Variables::IL2CPP::il2cpp_domain_get_assemblies || !Variables::IL2CPP::il2cpp_assembly_get_image || !Variables::IL2CPP::il2cpp_class_from_name) {
            NSLog(@"[I2FTransFont] Generic skip: missing domain APIs");
            return NO;
        }

        size_t assemblyCount = 0;
        void **assemblies = Variables::IL2CPP::il2cpp_domain_get_assemblies(domain, &assemblyCount);
        if (!assemblies || assemblyCount == 0) {
            NSLog(@"[I2FTransFont] Generic skip: no assemblies");
            return NO;
        }

        void *klassPtr = nullptr;
        const char *ns = spec.namespaceName.length > 0 ? [spec.namespaceName UTF8String] : "";
        const char *klassName = [spec.className UTF8String];

        for (size_t i = 0; i < assemblyCount; i++) {
            const void *image = Variables::IL2CPP::il2cpp_assembly_get_image(assemblies[i]);
            if (!image) {
                continue;
            }
            klassPtr = Variables::IL2CPP::il2cpp_class_from_name(image, ns, klassName);
            if (klassPtr) {
                break;
            }
        }

        if (!klassPtr || !Variables::IL2CPP::il2cpp_class_get_method_from_name) {
            @synchronized (_setFontFailureCache) {
                [_setFontFailureCache addObject:fullName];
            }
            NSLog(@"[I2FTransFont] Generic skip: class/method lookup failed");
            return NO;
        }

        methodInfo = Variables::IL2CPP::il2cpp_class_get_method_from_name(klassPtr, "set_font", 1);
        if (!methodInfo) {
            @synchronized (_setFontFailureCache) {
                [_setFontFailureCache addObject:fullName];
            }
            NSLog(@"[I2FTransFont] Generic skip: set_font not found");
            return NO;
        }

        @synchronized (_setFontMethodCache) {
            _setFontMethodCache[fullName] = [NSValue valueWithPointer:methodInfo];
        }
    }

    void *methodPtr = *(void **)methodInfo;
    if (!methodPtr) {
        NSLog(@"[I2FTransFont] Generic skip: method ptr null");
        return NO;
    }

    [self ensureUIFont];
    if (!_uiFontObject) {
        NSLog(@"[I2FTransFont] Generic skip: UIFont not ready");
        return NO;
    }

    typedef void (*SetFontFunc)(void *, void *, const void *);
    SetFontFunc func = (SetFontFunc)methodPtr;
    func(instance, _uiFontObject, methodInfo);
    NSLog(@"[I2FTransFont] set_font applied via reflection for %@", fullName);
    return YES;
}

- (void)applyFairyGUIFontIfNeededForInstance:(void *)instance name:(NSString *)nameString {
    NSLog(@"[I2FTransFont] FairyGUI apply attempt name=%@", nameString);
    if (!instance || nameString.length == 0) {
        NSLog(@"[I2FTransFont] FairyGUI skip: missing self/name");
        return;
    }

    BOOL isFairyTextField = ([nameString containsString:@"FairyGUI.TextField"] || [nameString containsString:@"FairyGUI.GTextField"] || [nameString containsString:@"FairyGUI"]);
    if (!isFairyTextField) {
        NSLog(@"[I2FTransFont] FairyGUI skip: not TextField");
        return;
    }

    if (!_fgUITextFormatGet || !_fgUITextFormatSet || !_fgUITextFormatFontField || ![I2FIl2CppHookRuntime apiReady]) {
        NSLog(@"[I2FTransFont] FairyGUI skip: accessors not ready or API not ready");
        return;
    }

    [self ensureUIFont];
    [self registerFairyGUIFontsIfNeeded];
    if (!_uiFontObject || !Variables::IL2CPP::il2cpp_string_new) {
        NSLog(@"[I2FTransFont] FairyGUI skip: UIFont not ready or string_new missing");
        return;
    }

    typedef void * (*GetFormatFunc)(void *, const void *);
    typedef void (*SetFormatFunc)(void *, void *, const void *);
    GetFormatFunc getFunc = (GetFormatFunc) * (void **)_fgUITextFormatGet;
    SetFormatFunc setFunc = (SetFormatFunc) * (void **)_fgUITextFormatSet;

    if (!getFunc || !setFunc) {
        NSLog(@"[I2FTransFont] FairyGUI skip: get/set textFormat ptr null");
        return;
    }

    void *format = getFunc(instance, _fgUITextFormatGet);
    if (!format) {
        NSLog(@"[I2FTransFont] FairyGUI skip: textFormat null");
        return;
    }

    void *fontField = _fgUITextFormatFontField;
    if (!fontField) {
        NSLog(@"[I2FTransFont] FairyGUI skip: font field null");
        return;
    }

    NSString *fallbackName = _uiFontName ?: @"Arial Unicode MS";
    void *fontNameStr = Variables::IL2CPP::il2cpp_string_new([fallbackName UTF8String]);
    if (fontNameStr && Variables::IL2CPP::il2cpp_field_get_offset) {
        size_t offset = Variables::IL2CPP::il2cpp_field_get_offset(fontField);
        void **fieldPtr = (void **)((uint8_t *)format + offset);
        if (fieldPtr) {
            *fieldPtr = fontNameStr;
        } else {
            NSLog(@"[I2FTransFont] FairyGUI warn: fieldPtr null");
        }
    } else {
        NSLog(@"[I2FTransFont] FairyGUI skip: fontNameStr/offset missing");
    }

    setFunc(instance, format, _fgUITextFormatSet);

    if (!_loggedFGUITextFormat) {
        _loggedFGUITextFormat = YES;
        NSLog(@"[I2FTransFont] FairyGUI TextFormat font patched");
    }
}

@end
