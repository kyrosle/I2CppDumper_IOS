#import <Foundation/Foundation.h>
#include <vector>

#import "I2FIl2CppTextHookTypes.h"

NS_ASSUME_NONNULL_BEGIN

/// 负责 IL2CPP 相关的解析、线程附加与字符串桥接。
@interface I2FIl2CppHookRuntime : NSObject

+ (BOOL)apiReady;
+ (void)attachThreadIfNeeded;
+ (BOOL)parseTarget:(NSString *)fullName intoSpec:(I2FTargetSpec *)outSpec;
+ (BOOL)parseOffsetValue:(id)value outValue:(uint64_t *)outValue;
+ (BOOL)resolveMethodForSpec:(const I2FTargetSpec &)spec result:(I2FResolvedMethod *)outResolved;
+ (BOOL)resolveMethodByPointer:(void *)targetPointer result:(I2FResolvedMethod *)outResolved;
+ (NSString *)convertIl2CppString:(void *)il2cppString;
+ (void *)createIl2CppStringFromNSString:(NSString *)string;
+ (NSString *)shortenTextForLog:(NSString *)text;
+ (BOOL)shouldLogText:(NSString *)text;
+ (const void *)findImageNamed:(const std::vector<std::string> &)candidates;

@end

NS_ASSUME_NONNULL_END
