#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

typedef struct {
    BOOL logHits;
    BOOL translateText;
    BOOL applyFonts;
} I2FTextHookPipelineOptions;

static inline I2FTextHookPipelineOptions I2FTextHookPipelineOptionsMake(BOOL logHits,
                                                                        BOOL translateText,
                                                                        BOOL applyFonts) {
    I2FTextHookPipelineOptions options;
    options.logHits = logHits;
    options.translateText = translateText;
    options.applyFonts = applyFonts;
    return options;
}

static inline I2FTextHookPipelineOptions I2FDefaultTextHookPipelineOptions(void) {
    return I2FTextHookPipelineOptionsMake(YES, YES, YES);
}

@interface I2FPendingRefresh : NSObject
@property (nonatomic, strong) NSValue *targetPointer;  // void * il2cpp instance
@property (nonatomic, strong) NSValue *methodKey;      // NSValue wrapping MethodInfo pointer
@property (nonatomic, copy) NSString *prefix;          // optional color/markup prefix
@property (nonatomic, copy) NSString *suffix;          // optional color/markup suffix
@end

NS_ASSUME_NONNULL_END
