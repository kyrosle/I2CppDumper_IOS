#import <UIKit/UIKit.h>

__attribute__((constructor))
static void il2cppdumper_init() {
    NSLog(@"[MDTest] constructor in, bundle = %@", [[NSBundle mainBundle] bundleIdentifier]);

    dispatch_async(dispatch_get_main_queue(), ^{
        // 稍微等一等，让 Unity / SDK 把根 VC 搞出来
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{

            UIWindow *targetWindow = nil;

            // iOS 13+ UIScene 方式获取 window
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive &&
                        [scene isKindOfClass:[UIWindowScene class]]) {

                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *w in ws.windows) {
                            if (w.isKeyWindow) {
                                targetWindow = w;
                                break;
                            }
                        }
                    }
                    if (targetWindow) break;
                }
            }

            // 旧系统兜底
            if (!targetWindow) {
                targetWindow = [UIApplication sharedApplication].keyWindow;
            }

            if (!targetWindow) {
                NSLog(@"[MDTest] 没找到 window，先只打 log，不弹窗");
                return;
            }

            UIViewController *rootVC = targetWindow.rootViewController;
            while (rootVC.presentedViewController) {
                rootVC = rootVC.presentedViewController;
            }

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Il2cppDumper"
                                                                           message:@"MonkeyDev 注入 & UI 测试 OK"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];

            [rootVC presentViewController:alert animated:YES completion:nil];
        });
    });
}
