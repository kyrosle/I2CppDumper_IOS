#import "I2FGGTranslationClient.h"

#if __has_include("MLKit.h")
#import "MLKit.h"
#define I2F_GG_TRANSLATION_AVAILABLE 1
#elif __has_include(<MLKitTranslate/MLKTranslator.h>)
#import <MLKitTranslate/MLKTranslator.h>
#define I2F_GG_TRANSLATION_AVAILABLE 1
#else
#define I2F_GG_TRANSLATION_AVAILABLE 0
#endif

#if I2F_GG_TRANSLATION_AVAILABLE
#import <objc/runtime.h>
#endif

#if I2F_GG_TRANSLATION_AVAILABLE
@interface I2FGGTranslationClient ()

@property (nonatomic, strong) MLKTranslator *translator;
@property (nonatomic, assign) BOOL modelReady;
@property (nonatomic, assign) BOOL preparing;
@property (nonatomic, strong) NSMutableArray<void (^)(BOOL)> *pendingReadyBlocks;
@property (nonatomic, copy, readwrite) NSString *targetLanguageTag;

@end
#endif

#if I2F_GG_TRANSLATION_AVAILABLE
static NSBundle *(*I2FOrigBundleForClass)(id, SEL, Class);

static NSBundle *I2FBundleForClassPatched(id self, SEL _cmd, Class aClass) {
    // MLKit classes live in our injected dylib (bundle path often /Frameworks),
    // but resources are in the main bundle. Redirect MLKit class lookups to main bundle.
    if (aClass) {
        NSString *clsName = NSStringFromClass(aClass);
        if ([clsName hasPrefix:@"MLK"] || [clsName containsString:@"MLKITx_"]) {
            NSBundle *main = [NSBundle mainBundle];
            return main;
        }
    }
    return I2FOrigBundleForClass(self, _cmd, aClass);
}

static void I2FInstallBundlePatch(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [NSBundle class];
        SEL sel = @selector(bundleForClass:);
        Method m = class_getClassMethod(cls, sel);
        if (!m) return;
        I2FOrigBundleForClass = (NSBundle *(*)(id, SEL, Class))method_getImplementation(m);
        method_setImplementation(m, (IMP)I2FBundleForClassPatched);
        NSLog(@"[I2FTrans] installed bundleForClass patch");
    });
}
#endif

@implementation I2FGGTranslationClient

+ (BOOL)isAvailable {
#if I2F_GG_TRANSLATION_AVAILABLE
    return YES;
#else
    return NO;
#endif
}

- (instancetype)init {
    self = [super init];
    if (self) {
#if I2F_GG_TRANSLATION_AVAILABLE
        I2FInstallBundlePatch();
        MLKTranslatorOptions *options = [[MLKTranslatorOptions alloc] initWithSourceLanguage:MLKTranslateLanguageChinese targetLanguage:MLKTranslateLanguageEnglish];
        _translator = [MLKTranslator translatorWithOptions:options];
        _targetLanguageTag = @"en";
        _pendingReadyBlocks = [NSMutableArray array];

        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"MLKitTranslate_resource" ofType:@"bundle"];
        if (bundlePath.length > 0) {
            NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
            NSLog(@"[I2FTrans] translate resource bundle main=%@ loaded=%d", bundlePath, bundle.loaded);
        } else {
            NSLog(@"[I2FTrans] translate resource bundle NOT found in main bundle");
        }
        NSBundle *classBundle = [NSBundle bundleForClass:[MLKTranslator class]];
        NSLog(@"[I2FTrans] bundleForClass(MLKTranslator)=%@", classBundle.bundlePath);
#endif
    }
    return self;
}

- (void)translateText:(NSString *)text completion:(I2FGGTranslationCompletion)completion {
    if (!completion || text.length == 0) {
        if (completion) {
            completion(nil);
        }
        return;
    }
#if I2F_GG_TRANSLATION_AVAILABLE
    NSLog(@"[I2FTrans] translateText request len=%lu", (unsigned long)text.length);
    [self prepareModelIfNeeded:^(BOOL ready) {
        if (!ready) {
            NSLog(@"[I2FTrans] model not ready");
            completion(nil);
            return;
        }
        [self.translator translateText:text completion:^(NSString * _Nullable translatedText, NSError * _Nullable error) {
            if (error || translatedText.length == 0) {
                NSLog(@"[I2FTrans] MLKit translate error=%@", error);
                completion(nil);
            } else {
                NSLog(@"[I2FTrans] MLKit translate ok len=%lu", (unsigned long)translatedText.length);
                completion(translatedText);
            }
        }];
    }];
#else
    completion(nil);
#endif
}

#if I2F_GG_TRANSLATION_AVAILABLE
- (void)prepareModelIfNeeded:(void (^)(BOOL ready))completion {
    if (!completion) {
        return;
    }
    if (self.modelReady) {
        completion(YES);
        return;
    }
    if (self.preparing) {
        [self.pendingReadyBlocks addObject:[completion copy]];
        return;
    }
    self.preparing = YES;
    [self.pendingReadyBlocks addObject:[completion copy]];

    MLKModelDownloadConditions *conditions = [[MLKModelDownloadConditions alloc] initWithAllowsCellularAccess:YES
                                                                       allowsBackgroundDownloading:YES];
    __weak typeof(self) weakSelf = self;
    NSLog(@"[I2FTrans] downloading model target=%@", self.targetLanguageTag);
//    [self.translator downloadModelIfNeededWithConditions:conditions
    [self.translator downloadModelIfNeededWithCompletion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        BOOL ready = (error == nil);
        strongSelf.modelReady = ready;
        strongSelf.preparing = NO;
        if (error) {
            NSLog(@"[I2FTrans] model download failed %@", error);
        } else {
            NSLog(@"[I2FTrans] model ready");
        }

        NSArray<void (^)(BOOL)> *blocks = [strongSelf.pendingReadyBlocks copy];
        [strongSelf.pendingReadyBlocks removeAllObjects];
        for (void (^block)(BOOL) in blocks) {
            block(ready);
        }
    }];
}
#endif

@end
