#import <Foundation/Foundation.h>

@class MISFloatingBall;

NS_ASSUME_NONNULL_BEGIN

/// 负责创建和管理 MISFloatingBall，并在点击时弹出控制面板。
@interface I2FFloatingBallManager : NSObject

+ (instancetype)sharedManager;

- (void)showBall;
- (void)hideBall;

@end

NS_ASSUME_NONNULL_END

