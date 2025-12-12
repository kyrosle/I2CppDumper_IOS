#import "I2FConfigManager.h"

static NSString *const kI2FAutoDumpEnabledKey = @"I2F.AutoDumpEnabled";
static NSString *const kI2FHasDumpedOnceKey = @"I2F.HasDumpedOnce";
static NSString *const kI2FAutoInstallHookOnLaunchKey = @"I2F.AutoInstallHookOnLaunch";
static NSString *const kI2FAutoInstallHookAfterDumpKey = @"I2F.AutoInstallHookAfterDump";
static NSString *const kI2FLastDumpDirectoryKey = @"I2F.LastDumpDirectory";
static NSString *const kI2FSetTextHookEntriesKey = @"I2F.SetTextHookEntries";
static NSString *const kI2FLastInstallingHookEntryKey = @"I2F.LastInstallingHookEntry";

static NSArray<NSDictionary *> *I2FNormalizeHookEntries(NSArray<NSDictionary *> *entries) {
    if (entries.count == 0) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
    for (NSDictionary *entry in entries) {
        NSString *name = entry[@"name"];
        if (name.length == 0) {
            continue;
        }
        if ([seenNames containsObject:name]) {
            continue;
        }
        [seenNames addObject:name];
        BOOL enabled = YES;
        id enabledObj = entry[@"enabled"];
        if ([enabledObj respondsToSelector:@selector(boolValue)]) {
            enabled = [enabledObj boolValue];
        }
        NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
        normalized[@"name"] = name;
        NSString *rva = entry[@"rva"];
        if (rva.length > 0) {
            normalized[@"rva"] = rva;
        }
        NSString *signature = entry[@"signature"];
        if (signature.length > 0) {
            normalized[@"signature"] = signature;
        }
        NSString *ns = entry[@"namespace"];
        if (ns.length > 0) {
            normalized[@"namespace"] = ns;
        }
        NSString *klass = entry[@"class"];
        if (klass.length > 0) {
            normalized[@"class"] = klass;
        }
        NSString *method = entry[@"method"];
        if (method.length > 0) {
            normalized[@"method"] = method;
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
