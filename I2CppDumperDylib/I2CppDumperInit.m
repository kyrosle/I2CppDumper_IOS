//
//  I2CppDumperInit.m
//  I2CppDumperDylib
//

#import "I2CppDumperInit.h"
#import <UIKit/UIKit.h>

void I2CppDumperShowInjectedAlert(void) {
    NSLog(@"[I2CppDumper] init, bundle = %@", [[NSBundle mainBundle] bundleIdentifier]);

    dispatch_async(dispatch_get_main_queue(), ^{
        // 等待 Unity / SDK 初始化完根视图控制器
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{

            UIWindow *targetWindow = nil;

            // iOS 13+ 通过 UIScene 获取 window
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive &&
                        [scene isKindOfClass:[UIWindowScene class]]) {

                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *window in ws.windows) {
                            if (window.isKeyWindow) {
                                targetWindow = window;
                                break;
                            }
                        }
                    }
                    if (targetWindow) {
                        break;
                    }
                }
            }

            // 旧系统兜底
            if (!targetWindow) {
                targetWindow = [UIApplication sharedApplication].keyWindow;
            }

            if (!targetWindow) {
                NSLog(@"[I2CppDumper] No key window found, skip alert.");
                return;
            }

            UIViewController *rootViewController = targetWindow.rootViewController;
            while (rootViewController.presentedViewController) {
                rootViewController = rootViewController.presentedViewController;
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Il2CppDumper"
                                                                           message:@"MonkeyDev 注入 & UI 测试 OK"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];

            [rootViewController presentViewController:alert animated:YES completion:nil];
        });
    });
}

