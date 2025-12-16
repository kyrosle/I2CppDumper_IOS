#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^I2FGGTranslationCompletion)(NSString * _Nullable translation);

/// 轻量封装 Google/MLKit 离线翻译。
/// 内部自动下载所需模型（若缺失），并串行处理翻译请求。
@interface I2FGGTranslationClient : NSObject

/// 当前目标语言 BCP-47 标记（示例：@"en"）。
@property (nonatomic, copy, readonly) NSString *targetLanguageTag;

/// 是否可用（编译时存在 MLKitTranslate 头文件且初始化成功）。
+ (BOOL)isAvailable;

/// 初始化默认中->英离线翻译。
- (instancetype)init;

/// 翻译文本，完成回调在任意队列触发，调用方自行回到需要的线程。
- (void)translateText:(NSString *)text completion:(I2FGGTranslationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
