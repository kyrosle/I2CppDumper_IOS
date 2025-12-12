//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  I2CppDumperDylib.m
//  I2CppDumperDylib
//
//  Created by kyros He on 2025/12/10.
//  Copyright (c) 2025 ___ORGANIZATIONNAME___. All rights reserved.
//

#import "I2CppDumperDylib.h"
#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Cycript/Cycript.h>
#import <MDCycriptManager.h>

#import "I2FConfigManager.h"
#import "I2FFloatingBallManager.h"

// Il2Cpp dumper entry (ported from IOS-Il2CppDumper)
void StartIl2CppDumpThread(void);

CHConstructor{
    printf(INSERT_SUCCESS_WELCOME);

    // 根据配置决定是否需要启动线程：自动 dump、启动时安装 hook 或 dump 后自动安装 hook 三者有其一即启动。
    BOOL hasEnabledHooks = NO;
    for (NSDictionary *entry in [I2FConfigManager setTextHookEntries]) {
        BOOL enabled = YES;
        id enabledObj = entry[@"enabled"];
        if ([enabledObj respondsToSelector:@selector(boolValue)]) {
            enabled = [enabledObj boolValue];
        }
        if (enabled) {
            hasEnabledHooks = YES;
            break;
        }
    }
    BOOL needThread = [I2FConfigManager autoDumpEnabled]
                   || [I2FConfigManager autoInstallHookOnLaunch]
                   || [I2FConfigManager autoInstallHookAfterDump]
                   || hasEnabledHooks;
    if (needThread) {
        StartIl2CppDumpThread();
    }
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        
#ifndef __OPTIMIZE__
        CYListenServer(6666);

        MDCycriptManager* manager = [MDCycriptManager sharedInstance];
        [manager loadCycript:NO];

        NSError* error;
        NSString* result = [manager evaluateCycript:@"UIApp" error:&error];
        NSLog(@"result: %@", result);
        if(error.code != 0){
            NSLog(@"error: %@", error.localizedDescription);
        }
#endif
        
    }];
}

CHDeclareClass(ChameleonSDK)

CHOptimizedMethod3(self, void, ChameleonSDK, initWithConfig, id, config, application, UIApplication*, application, didFinishLaunchingWithOptions, NSDictionary*, options){
    CHSuper3(ChameleonSDK, initWithConfig, config, application, application, didFinishLaunchingWithOptions, options);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[I2FFloatingBallManager sharedManager] showBall];
    });
}

CHConstructor{
    CHLoadLateClass(ChameleonSDK);
    CHHook3(ChameleonSDK, initWithConfig, application, didFinishLaunchingWithOptions);
}


CHDeclareClass(CustomViewController)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"

//add new method
CHDeclareMethod1(void, CustomViewController, newMethod, NSString*, output){
    NSLog(@"This is a new method : %@", output);
}

#pragma clang diagnostic pop

CHOptimizedClassMethod0(self, void, CustomViewController, classMethod){
    NSLog(@"hook class method");
    CHSuper0(CustomViewController, classMethod);
}

CHOptimizedMethod0(self, NSString*, CustomViewController, getMyName){
    //get origin value
    NSString* originName = CHSuper(0, CustomViewController, getMyName);
    
    NSLog(@"origin name is:%@",originName);
    
    //get property
    NSString* password = CHIvar(self,_password,__strong NSString*);
    
    NSLog(@"password is %@",password);
    
    [self newMethod:@"output"];
    
    //set new property
    self.newProperty = @"newProperty";
    
    NSLog(@"newProperty : %@", self.newProperty);
    
    //change the value
    return @"kyros He";
    
}

//add new property
CHPropertyRetainNonatomic(CustomViewController, NSString*, newProperty, setNewProperty);

CHConstructor{
    CHLoadLateClass(CustomViewController);
    CHClassHook0(CustomViewController, getMyName);
    CHClassHook0(CustomViewController, classMethod);
    
    CHHook0(CustomViewController, newProperty);
    CHHook1(CustomViewController, setNewProperty);
}
