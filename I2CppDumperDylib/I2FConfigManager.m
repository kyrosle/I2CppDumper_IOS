#import "I2FConfigManager.h"

static NSString *const kI2FAutoDumpEnabledKey = @"I2F.AutoDumpEnabled";
static NSString *const kI2FHasDumpedOnceKey = @"I2F.HasDumpedOnce";
static NSString *const kI2FAutoInstallHookOnLaunchKey = @"I2F.AutoInstallHookOnLaunch";
static NSString *const kI2FAutoInstallHookAfterDumpKey = @"I2F.AutoInstallHookAfterDump";
static NSString *const kI2FLastDumpDirectoryKey = @"I2F.LastDumpDirectory";
static NSString *const kI2FSetTextRvaStringsKey = @"I2F.SetTextRvaStrings";
static NSString *const kI2FPrimarySetTextRvaStringKey = @"I2F.SetTextRvaString";
static NSString *const kI2FSetTextHookEntriesKey = @"I2F.SetTextHookEntries";
static NSString *const kI2FLastInstallingHookEntryKey = @"I2F.LastInstallingHookEntry";

static NSArray<NSDictionary *> *I2FNormalizeHookEntries(NSArray<NSDictionary *> *entries) {
    if (entries.count == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in entries) {
        NSString *rva = entry[@"rva"];
        if (rva.length == 0) {
            continue;
        }
        if ([seen containsObject:rva]) {
            continue;
        }
        [seen addObject:rva];
        BOOL enabled = YES;
        id enabledObj = entry[@"enabled"];
        if ([enabledObj respondsToSelector:@selector(boolValue)]) {
            enabled = [enabledObj boolValue];
        }
        NSString *name = entry[@"name"];
        NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
        normalized[@"rva"] = rva;
        if (name.length > 0) {
            normalized[@"name"] = name;
        }
        normalized[@"enabled"] = @(enabled);
        [result addObject:normalized];
    }
    return result;
}

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

+ (BOOL)autoInstallHookOnLaunch {
    NSUserDefaults *defaults = [self defaults];
    if ([defaults objectForKey:kI2FAutoInstallHookOnLaunchKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kI2FAutoInstallHookOnLaunchKey];
}

+ (void)setAutoInstallHookOnLaunch:(BOOL)enabled {
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:enabled forKey:kI2FAutoInstallHookOnLaunchKey];
    [defaults synchronize];
}

+ (BOOL)autoInstallHookAfterDump {
    NSUserDefaults *defaults = [self defaults];
    if ([defaults objectForKey:kI2FAutoInstallHookAfterDumpKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kI2FAutoInstallHookAfterDumpKey];
}

+ (void)setAutoInstallHookAfterDump:(BOOL)enabled {
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:enabled forKey:kI2FAutoInstallHookAfterDumpKey];
    [defaults synchronize];
}

+ (nullable NSString *)lastDumpDirectory {
    return [[self defaults] stringForKey:kI2FLastDumpDirectoryKey];
}

+ (void)setLastDumpDirectory:(nullable NSString *)path {
    NSUserDefaults *defaults = [self defaults];
    if (path.length > 0) {
        [defaults setObject:path forKey:kI2FLastDumpDirectoryKey];
    } else {
        [defaults removeObjectForKey:kI2FLastDumpDirectoryKey];
    }
    [defaults synchronize];
}

+ (NSArray<NSString *> *)setTextRvaStrings {
    NSArray<NSString *> *value = [[self defaults] arrayForKey:kI2FSetTextRvaStringsKey];
    return value ?: @[];
}

+ (void)setSetTextRvaStrings:(NSArray<NSString *> *)rvas {
    NSUserDefaults *defaults = [self defaults];
    if (rvas.count > 0) {
        [defaults setObject:rvas forKey:kI2FSetTextRvaStringsKey];
    } else {
        [defaults removeObjectForKey:kI2FSetTextRvaStringsKey];
    }
    [defaults synchronize];
}

+ (nullable NSString *)primarySetTextRvaString {
    return [[self defaults] stringForKey:kI2FPrimarySetTextRvaStringKey];
}

+ (void)setPrimarySetTextRvaString:(nullable NSString *)rva {
    NSUserDefaults *defaults = [self defaults];
    if (rva.length > 0) {
        [defaults setObject:rva forKey:kI2FPrimarySetTextRvaStringKey];
    } else {
        [defaults removeObjectForKey:kI2FPrimarySetTextRvaStringKey];
    }
    [defaults synchronize];
}

+ (NSArray<NSDictionary *> *)setTextHookEntries {
    NSArray<NSDictionary *> *value = [[self defaults] arrayForKey:kI2FSetTextHookEntriesKey];
    return I2FNormalizeHookEntries(value ?: @[]);
}

+ (void)setSetTextHookEntries:(NSArray<NSDictionary *> *)entries {
    NSArray<NSDictionary *> *deduped = I2FNormalizeHookEntries(entries);
    NSUserDefaults *defaults = [self defaults];
    if (deduped.count > 0) {
        [defaults setObject:deduped forKey:kI2FSetTextHookEntriesKey];
    } else {
        [defaults removeObjectForKey:kI2FSetTextHookEntriesKey];
    }
    [defaults synchronize];
}

+ (nullable NSDictionary *)lastInstallingHookEntry {
    NSDictionary *entry = [[self defaults] dictionaryForKey:kI2FLastInstallingHookEntryKey];
    return entry;
}

+ (void)setLastInstallingHookEntry:(nullable NSDictionary *)entry {
    NSUserDefaults *defaults = [self defaults];
    if (entry) {
        [defaults setObject:entry forKey:kI2FLastInstallingHookEntryKey];
    } else {
        [defaults removeObjectForKey:kI2FLastInstallingHookEntryKey];
    }
    [defaults synchronize];
}

@end
