#import <Foundation/Foundation.h>

#import "I2FIl2CppTextHookTypes.h"

NS_ASSUME_NONNULL_BEGIN

/// 统一管理 hook 安装时的映射关系，保持线程安全。
@interface I2FIl2CppTextHookState : NSObject

+ (instancetype)shared;

- (NSString * _Nullable)nameForMethodKey:(NSValue *)methodKey;
- (void)setName:(NSString * _Nullable)name forMethodKey:(NSValue *)methodKey;

- (NSValue * _Nullable)originalPointerForMethodKey:(NSValue *)methodKey;
- (void)setOriginalPointer:(NSValue * _Nullable)pointer forMethodKey:(NSValue *)methodKey;

- (NSValue * _Nullable)methodKeyForName:(NSString *)name;
- (void)setMethodKey:(NSValue * _Nullable)methodKey forName:(NSString *)name;

- (void)recordInstalledName:(NSString *)name;
- (void)removeInstalledName:(NSString *)name;
- (BOOL)hasInstalledName:(NSString *)name;

- (void)setPendingRefresh:(I2FPendingRefresh *)refresh forOriginal:(NSString *)original;
- (I2FPendingRefresh * _Nullable)consumePendingRefreshForOriginal:(NSString *)original;

- (void)setSlot:(NSValue *)slotKey original:(NSValue *)origPointer forName:(NSString * _Nullable)name;
- (NSValue * _Nullable)slotForName:(NSString *)name;
- (NSValue * _Nullable)originalForSlot:(NSValue *)slotKey;
- (void)removeSlotForName:(NSString *)name;

- (NSString * _Nullable)nameForOriginalPointer:(NSValue *)pointer;
- (void)setName:(NSString *)name forOriginalPointer:(NSValue *)pointer;
- (void)removeNameForOriginalPointer:(NSValue *)pointer;

@end

NS_ASSUME_NONNULL_END
