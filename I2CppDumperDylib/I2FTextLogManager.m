#import "I2FTextLogManager.h"

@implementation I2FTextLogEntry
@end

NSString * const I2FTextLogManagerDidAppendEntryNotification = @"I2FTextLogManagerDidAppendEntryNotification";
NSString * const I2FTextLogManagerDidClearNotification = @"I2FTextLogManagerDidClearNotification";

@interface I2FTextLogManager ()

@property (nonatomic, strong) NSMutableArray<I2FTextLogEntry *> *entries;

@end

@implementation I2FTextLogManager

+ (instancetype)sharedManager {
    static I2FTextLogManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[I2FTextLogManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

- (void)appendText:(NSString *)text rvaString:(NSString *)rvaString {
    if (text.length == 0) {
        return;
    }
    I2FTextLogEntry *entry = [[I2FTextLogEntry alloc] init];
    entry.text = text;
    entry.rvaString = rvaString ?: @"";
    entry.timestamp = [NSDate date];
    @synchronized (self) {
        [self.entries insertObject:entry atIndex:0];
        // 限制最大条数，避免内存无限增长
        static const NSUInteger kI2FMaxLogEntries = 500;
        if (self.entries.count > kI2FMaxLogEntries) {
            NSRange range = NSMakeRange(kI2FMaxLogEntries, self.entries.count - kI2FMaxLogEntries);
            [self.entries removeObjectsInRange:range];
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:I2FTextLogManagerDidAppendEntryNotification object:entry];
}

- (NSArray<I2FTextLogEntry *> *)allEntries {
    @synchronized (self) {
        return [self.entries copy];
    }
}

- (void)clear {
    @synchronized (self) {
        [self.entries removeAllObjects];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:I2FTextLogManagerDidClearNotification object:nil];
}

@end
