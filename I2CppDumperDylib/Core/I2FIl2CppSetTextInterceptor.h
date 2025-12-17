#import <Foundation/Foundation.h>

#import "I2FIl2CppTextHookTypes.h"

NS_ASSUME_NONNULL_BEGIN

void I2FSetterReplacement(void *self, void *il2cppString, const void *method);

/// 处理 set_text hook 的核心逻辑（翻译、日志、字体等）。
@interface I2FIl2CppSetTextInterceptor : NSObject

+ (void)setPipelineOptions:(I2FTextHookPipelineOptions)options;
+ (I2FTextHookPipelineOptions)pipelineOptions;
+ (void)installTranslationCallback;

@end

NS_ASSUME_NONNULL_END
