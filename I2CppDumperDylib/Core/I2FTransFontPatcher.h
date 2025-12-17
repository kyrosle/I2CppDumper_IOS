#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 将 Unity UI / TMP / FairyGUI 的字体替换为系统字体，避免乱码。
@interface I2FTransFontPatcher : NSObject

+ (instancetype)shared;

- (BOOL)applyTMPFontIfNeededForInstance:(void *)instance name:(NSString *)nameString;
- (BOOL)applyGenericSetFontIfAvailableForInstance:(void *)instance name:(NSString *)fullName;
- (void)applyFairyGUIFontIfNeededForInstance:(void *)instance name:(NSString *)nameString;

@end

NS_ASSUME_NONNULL_END
