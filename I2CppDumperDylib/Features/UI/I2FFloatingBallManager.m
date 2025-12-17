#import "I2FFloatingBallManager.h"

#import <UIKit/UIKit.h>

#import "MISFloatingBall.h"
#import "I2FControlPanelViewController.h"

@interface I2FFloatingBallManager ()

@property (nonatomic, strong) MISFloatingBall *floatingBall;
@property (nonatomic, strong) NSTimer *frontTimer;
@property (nonatomic, strong) I2FControlPanelViewController *panelViewController;

@end

@implementation I2FFloatingBallManager

+ (instancetype)sharedManager {
    static I2FFloatingBallManager *manager = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        manager = [[I2FFloatingBallManager alloc] init];
    });
    return manager;
}

- (void)showBall {
    if (self.floatingBall) {
        [self.floatingBall show];
        return;
    }

    UIWindow *window = [UIApplication sharedApplication].keyWindow;

    if (!window) {
        return;
    }

    CGFloat size = 48.0;
    CGRect frame = CGRectMake(window.bounds.size.width - size - 20.0,
                              window.bounds.size.height * 0.4,
                              size,
                              size);
    MISFloatingBall *ball = [[MISFloatingBall alloc] initWithFrame:frame inSpecifiedView:nil];
    ball.edgePolicy = MISFloatingBallEdgePolicyAllEdge;
    ball.autoCloseEdge = YES;
    [ball setContent:@"I2F" contentType:MISFloatingBallContentTypeText];
    ball.textTypeTextColor = [UIColor whiteColor];

    __weak typeof(self) weakSelf = self;
    ball.clickHandler = ^(MISFloatingBall *floatingBall) {
        [weakSelf togglePanel];
    };

    [ball show];
    self.floatingBall = ball;

    self.frontTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                       target:self
                                                     selector:@selector(bringBallToFront)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)hideBall {
    [self.frontTimer invalidate];
    self.frontTimer = nil;
    [self.floatingBall hide];
    self.floatingBall = nil;
}

- (void)bringBallToFront {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;

    if (!window || !self.floatingBall.superview) {
        return;
    }

    [window bringSubviewToFront:self.floatingBall];
}

- (void)togglePanel {
    UIWindow *targetWindow = nil;
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        // 避免使用 MISFloatingBall 自己的窗口，否则其 pointInside 会吞掉 panel 的触摸事件
        if (![win isKindOfClass:NSClassFromString(@"MISFloatingBallWindow")] &&
            win.hidden == NO &&
            win.alpha > 0.0) {
            targetWindow = win;
            break;
        }
    }

    if (!targetWindow) {
        targetWindow = [UIApplication sharedApplication].keyWindow;
    }

    UIViewController *root = targetWindow.rootViewController;
    if (!root) {
        return;
    }

    if (self.panelViewController && self.panelViewController.presentingViewController) {
        [self.panelViewController dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    self.panelViewController = [[I2FControlPanelViewController alloc] init];
    self.panelViewController.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [root presentViewController:self.panelViewController animated:YES completion:nil];
}

@end
