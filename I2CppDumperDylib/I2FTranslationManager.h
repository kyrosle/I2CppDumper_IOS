#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface I2FTranslationRecord : NSObject

@property (nonatomic, copy) NSString *original;
@property (nonatomic, copy, nullable) NSString *translated;
@property (nonatomic, copy, nullable) NSString *context;          // 例如 name/rva，便于去重和溯源。
@property (nonatomic, copy, nullable) NSString *targetLanguage;   // 预留给多语言。
@property (nonatomic, strong, nullable) NSDate *timestamp;

@end

/// 管理翻译查找、批量入库、缓存命中。
/// 仅设计 API 和调用位，具体实现留作 TODO。
@interface I2FTranslationManager : NSObject

/// 翻译结果写库后回调，可用于触发 UI 刷新。
@property (nonatomic, copy, nullable) void (^translationDidUpdate)(I2FTranslationRecord *record);

+ (instancetype)sharedManager;

/// set_text hook 入口：快速查缓存/数据库，缺失时入队等待批量翻译和写库。
/// 返回非空翻译时可直接替换界面文案。
- (nullable NSString *)translationForOriginal:(NSString *)original
                                      context:(nullable NSString *)context
                                   didEnqueue:(BOOL * _Nullable)didEnqueue;

/// 拉取一批待翻译文本，供后台翻译任务批量处理。
- (NSArray<I2FTranslationRecord *> *)drainPendingOriginalsWithLimit:(NSUInteger)limit;

/// 写入翻译结果（可批量），并刷新内存缓存。
- (void)storeTranslatedRecords:(NSArray<I2FTranslationRecord *> *)records;

/// 将尚未翻译的原文批量落盘（sqlite），避免进程退出丢失。
- (void)flushPendingOriginals;

/// 预热或重置缓存。
- (void)prewarmCacheWithRecords:(NSArray<I2FTranslationRecord *> *)records;
- (void)clearCaches;

@end

NS_ASSUME_NONNULL_END
