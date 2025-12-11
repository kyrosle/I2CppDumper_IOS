#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单条文本记录模型的简单封装。
@interface I2FTextLogEntry : NSObject

@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *rvaString;
@property (nonatomic, strong) NSDate *timestamp;

@end

/// 有新文案追加时发送的通知，object 为 I2FTextLogEntry。
FOUNDATION_EXTERN NSString * const I2FTextLogManagerDidAppendEntryNotification;

/// 日志被清空时发送的通知，object 为空。
FOUNDATION_EXTERN NSString * const I2FTextLogManagerDidClearNotification;

/// 管理通过 set_text hook 捕获到的所有文案。
@interface I2FTextLogManager : NSObject

+ (instancetype)sharedManager;

/// 追加一条记录。
- (void)appendText:(NSString *)text rvaString:(NSString *)rvaString;

/// 当前所有记录（按时间倒序）。
- (NSArray<I2FTextLogEntry *> *)allEntries;

/// 清空所有记录。
- (void)clear;

@end

NS_ASSUME_NONNULL_END
