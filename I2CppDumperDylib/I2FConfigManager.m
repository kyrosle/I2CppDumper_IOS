#import "I2FConfigManager.h"

static NSString *const kI2FAutoDumpEnabledKey = @"I2F.AutoDumpEnabled";
static NSString *const kI2FHasDumpedOnceKey = @"I2F.HasDumpedOnce";

@implementation I2FConfigManager

+ (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

+ (BOOL)autoDumpEnabled {
    NSUserDefaults *defaults = [self defaults];
    if ([defaults objectForKey:kI2FAutoDumpEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kI2FAutoDumpEnabledKey];
}

+ (void)setAutoDumpEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:enabled forKey:kI2FAutoDumpEnabledKey];
    [defaults synchronize];
}

+ (BOOL)hasDumpedOnce {
    return [[self defaults] boolForKey:kI2FHasDumpedOnceKey];
}

+ (void)setHasDumpedOnce:(BOOL)done {
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:done forKey:kI2FHasDumpedOnceKey];
    [defaults synchronize];
}

+ (void)resetDumpFlags {
    NSUserDefaults *defaults = [self defaults];
    [defaults removeObjectForKey:kI2FHasDumpedOnceKey];
    [defaults synchronize];
}

@end

