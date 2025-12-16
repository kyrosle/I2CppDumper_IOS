#import "I2FTranslationManager.h"
#import <sqlite3.h>
#import "I2FGGTranslationClient.h"

static NSString * const kI2FTranslationDBName = @"I2FTranslation.sqlite";
static const NSUInteger kI2FMaxCacheCount = 500;
static const NSUInteger kI2FMaxPendingInMemory = 500;
static const NSUInteger kI2FTranslateBatchSize = 1; // MLKit 翻译逐条处理，保留接口便于后续批量。

@interface I2FTranslationManager ()

@property (nonatomic, strong) NSCache<NSString *, NSString *> *memoryCache;                  // 读缓存（LRU）。
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *pendingOriginals;             // 待翻译/入库队列。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *pendingContextMap;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, assign) sqlite3 *db;
@property (nonatomic, strong) I2FGGTranslationClient *ggTranslator;
@property (nonatomic, assign) BOOL autoTranslating;

@end

@implementation I2FTranslationRecord
@end

@implementation I2FTranslationManager

+ (instancetype)sharedManager {
    static I2FTranslationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[I2FTranslationManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = kI2FMaxCacheCount;
        _pendingOriginals = [NSMutableOrderedSet orderedSet];
        _pendingContextMap = [NSMutableDictionary dictionary];
        _workerQueue = dispatch_queue_create("i2f.translation.manager", DISPATCH_QUEUE_SERIAL);
        dispatch_async(_workerQueue, ^{
            [self ensureDatabaseOpenOnQueue];
            [self loadPendingFromDBOnQueueWithLimit:kI2FMaxPendingInMemory];
            if ([I2FGGTranslationClient isAvailable]) {
                self.ggTranslator = [[I2FGGTranslationClient alloc] init];
            }
        });
    }
    return self;
}

- (void)dealloc {
    if (self.db) {
        sqlite3_close(self.db);
        self.db = nil;
    }
}

- (nullable NSString *)translationForOriginal:(NSString *)original
                                      context:(nullable NSString *)context
                                   didEnqueue:(BOOL * _Nullable)didEnqueue {
    if (didEnqueue) {
        *didEnqueue = NO;
    }
    if (original.length == 0) {
        return nil;
    }

    NSString *cached = [self.memoryCache objectForKey:original];
    if (cached.length > 0) {
        NSLog(@"[I2FTrans] cache hit len=%lu", (unsigned long)original.length);
        return cached;
    }

    __block NSString *dbValue = nil;
    dispatch_sync(self.workerQueue, ^{
        [self ensureDatabaseOpenOnQueue];
        dbValue = [self translationFromDBOnQueue:original];
    });
    if (dbValue.length > 0) {
        [self.memoryCache setObject:dbValue forKey:original];
        NSLog(@"[I2FTrans] db hit len=%lu", (unsigned long)original.length);
        return dbValue;
    }

    dispatch_async(self.workerQueue, ^{
        [self ensureDatabaseOpenOnQueue];
        [self insertPendingOnQueueWithOriginal:original context:context];
        [self startAutoTranslateOnQueueIfNeeded];
    });
    if (didEnqueue) {
        *didEnqueue = YES;
    }
    NSLog(@"[I2FTrans] miss enqueue len=%lu", (unsigned long)original.length);
    return nil;
}

- (NSArray<I2FTranslationRecord *> *)drainPendingOriginalsWithLimit:(NSUInteger)limit {
    if (limit == 0) {
        return @[];
    }
    __block NSArray<NSString *> *batch = nil;
    __block NSArray<NSString *> *contexts = nil;
    dispatch_sync(self.workerQueue, ^{
        if (self.pendingOriginals.count < limit) {
            [self loadPendingFromDBOnQueueWithLimit:(limit - self.pendingOriginals.count)];
        }
        NSUInteger count = MIN(limit, self.pendingOriginals.count);
        NSRange range = NSMakeRange(0, count);
        batch = [[self.pendingOriginals objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range]] copy];
        [self.pendingOriginals removeObjectsInRange:range];
        NSMutableArray<NSString *> *ctxArr = [NSMutableArray arrayWithCapacity:batch.count];
        for (NSString *text in batch) {
            NSString *ctx = self.pendingContextMap[text];
            [ctxArr addObject:(ctx ?: @"")];
            [self.pendingContextMap removeObjectForKey:text];
        }
        contexts = [ctxArr copy];
        [self removePendingOnQueueForOriginals:batch];
    });

    NSMutableArray<I2FTranslationRecord *> *records = [NSMutableArray arrayWithCapacity:batch.count];
    [batch enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
        I2FTranslationRecord *record = [[I2FTranslationRecord alloc] init];
        record.original = obj;
        record.context = idx < contexts.count ? contexts[idx] : nil;
        [records addObject:record];
    }];
    return records;
}

- (void)storeTranslatedRecords:(NSArray<I2FTranslationRecord *> *)records {
    if (records.count == 0) {
        return;
    }
    dispatch_async(self.workerQueue, ^{
        [self ensureDatabaseOpenOnQueue];
        [self storeTranslatedRecordsOnQueue:records];
    });
}

- (void)flushPendingOriginals {
    dispatch_async(self.workerQueue, ^{
        [self ensureDatabaseOpenOnQueue];
        for (NSString *text in self.pendingOriginals) {
            NSString *ctx = self.pendingContextMap[text];
            [self insertPendingOnQueueWithOriginal:text context:ctx];
        }
    });
}

- (void)prewarmCacheWithRecords:(NSArray<I2FTranslationRecord *> *)records {
    if (records.count == 0) {
        return;
    }
    for (I2FTranslationRecord *record in records) {
        if (record.original.length > 0 && record.translated.length > 0) {
            [self.memoryCache setObject:record.translated forKey:record.original];
        }
    }
}

- (void)clearCaches {
    [self.memoryCache removeAllObjects];
}

#pragma mark - Private (DB)

- (NSString *)databasePath {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        path = [documentsPath stringByAppendingPathComponent:kI2FTranslationDBName];
    });
    return path;
}

- (void)ensureDatabaseOpenOnQueue {
    if (self.db) {
        return;
    }
    NSString *dbPath = [self databasePath];
    int rc = sqlite3_open([dbPath UTF8String], &_db);
    if (rc != SQLITE_OK) {
        sqlite3_close(_db);
        _db = nil;
        return;
    }
    const char *createSql =
    "CREATE TABLE IF NOT EXISTS translations ("
    " original TEXT PRIMARY KEY,"
    " translated TEXT,"
    " context TEXT,"
    " lang TEXT,"
    " updated_at REAL"
    ");"
    "CREATE TABLE IF NOT EXISTS pending_originals ("
    " original TEXT PRIMARY KEY,"
    " context TEXT,"
    " created_at REAL"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_translations_original ON translations(original);";
    sqlite3_exec(self.db, createSql, NULL, NULL, NULL);
}

- (void)loadPendingFromDBOnQueueWithLimit:(NSUInteger)limit {
    if (limit == 0 || !self.db) {
        return;
    }
    NSString *sql = [NSString stringWithFormat:@"SELECT original, context FROM pending_originals ORDER BY created_at ASC LIMIT %lu", (unsigned long)limit];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(self.db, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        return;
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *origC = sqlite3_column_text(stmt, 0);
        const unsigned char *ctxC = sqlite3_column_text(stmt, 1);
        if (!origC) {
            continue;
        }
        NSString *orig = [NSString stringWithUTF8String:(const char *)origC];
        if (orig.length == 0) {
            continue;
        }
        if ([self.pendingOriginals containsObject:orig]) {
            continue;
        }
        if (self.pendingOriginals.count >= kI2FMaxPendingInMemory) {
            break;
        }
        [self.pendingOriginals addObject:orig];
        if (ctxC) {
            NSString *ctx = [NSString stringWithUTF8String:(const char *)ctxC];
            if (ctx.length > 0) {
                self.pendingContextMap[orig] = ctx;
            }
        }
    }
    sqlite3_finalize(stmt);
}

- (nullable NSString *)translationFromDBOnQueue:(NSString *)original {
    if (!self.db || original.length == 0) {
        return nil;
    }
    static sqlite3_stmt *stmt = NULL;
    if (!stmt) {
        const char *sql = "SELECT translated FROM translations WHERE original = ? LIMIT 1";
        if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            stmt = NULL;
            return nil;
        }
    }
    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    sqlite3_bind_text(stmt, 1, [original UTF8String], -1, SQLITE_TRANSIENT);

    NSString *result = nil;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);
        if (text) {
            result = [NSString stringWithUTF8String:(const char *)text];
        }
    }
    return result;
}

- (void)insertPendingOnQueueWithOriginal:(NSString *)original context:(nullable NSString *)context {
    if (original.length == 0 || !self.db) {
        return;
    }
    if ([self.pendingOriginals containsObject:original]) {
        return;
    }
    if (self.pendingOriginals.count >= kI2FMaxPendingInMemory) {
        [self.pendingOriginals removeObjectAtIndex:0];
    }
    [self.pendingOriginals addObject:original];
    if (context.length > 0) {
        self.pendingContextMap[original] = context;
    }

    const char *sql = "INSERT OR IGNORE INTO pending_originals (original, context, created_at) VALUES (?, ?, ?)";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return;
    }
    sqlite3_bind_text(stmt, 1, [original UTF8String], -1, SQLITE_TRANSIENT);
    if (context.length > 0) {
        sqlite3_bind_text(stmt, 2, [context UTF8String], -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    sqlite3_bind_double(stmt, 3, [[NSDate date] timeIntervalSince1970]);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
}

- (void)removePendingOnQueueForOriginals:(NSArray<NSString *> *)originals {
    if (originals.count == 0 || !self.db) {
        return;
    }
    sqlite3_exec(self.db, "BEGIN EXCLUSIVE TRANSACTION", NULL, NULL, NULL);
    const char *sql = "DELETE FROM pending_originals WHERE original = ?";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        for (NSString *orig in originals) {
            sqlite3_reset(stmt);
            sqlite3_clear_bindings(stmt);
            sqlite3_bind_text(stmt, 1, [orig UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
        }
    }
    sqlite3_finalize(stmt);
    sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL);
}

- (void)storeTranslatedRecordsOnQueue:(NSArray<I2FTranslationRecord *> *)records {
    if (!self.db) {
        return;
    }
    sqlite3_exec(self.db, "BEGIN EXCLUSIVE TRANSACTION", NULL, NULL, NULL);
    const char *sql = "INSERT OR REPLACE INTO translations (original, translated, context, lang, updated_at) VALUES (?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt = NULL;
    sqlite3_prepare_v2(self.db, sql, -1, &stmt, NULL);

    for (I2FTranslationRecord *record in records) {
        if (record.original.length == 0 || record.translated.length == 0) {
            continue;
        }
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
        sqlite3_bind_text(stmt, 1, [record.original UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [record.translated UTF8String], -1, SQLITE_TRANSIENT);
        if (record.context.length > 0) {
            sqlite3_bind_text(stmt, 3, [record.context UTF8String], -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_null(stmt, 3);
        }
        if (record.targetLanguage.length > 0) {
            sqlite3_bind_text(stmt, 4, [record.targetLanguage UTF8String], -1, SQLITE_TRANSIENT);
        } else {
            sqlite3_bind_text(stmt, 4, "auto", -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_double(stmt, 5, record.timestamp ? [record.timestamp timeIntervalSince1970] : [[NSDate date] timeIntervalSince1970]);
        sqlite3_step(stmt);
        [self.memoryCache setObject:record.translated forKey:record.original];
    }
    sqlite3_finalize(stmt);
    sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL);
}

- (void)startAutoTranslateOnQueueIfNeeded {
    if (!self.ggTranslator || self.autoTranslating) {
        return;
    }
    NSLog(@"[I2FTrans] auto translate start");
    self.autoTranslating = YES;
    [self processNextPendingOnQueue];
}

- (void)processNextPendingOnQueue {
    if (!self.ggTranslator) {
        self.autoTranslating = NO;
        return;
    }
    if (self.pendingOriginals.count == 0) {
        [self loadPendingFromDBOnQueueWithLimit:kI2FTranslateBatchSize];
    }
    NSString *next = self.pendingOriginals.firstObject;
    if (next.length == 0) {
        self.autoTranslating = NO;
        return;
    }
    NSString *ctx = self.pendingContextMap[next];
    [self.pendingOriginals removeObjectAtIndex:0];
    [self.pendingContextMap removeObjectForKey:next];
    [self removePendingOnQueueForOriginals:@[next]];

    __weak typeof(self) weakSelf = self;
    NSLog(@"[I2FTrans] translating len=%lu", (unsigned long)next.length);
    [self.ggTranslator translateText:next completion:^(NSString * _Nullable translation) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        dispatch_async(strongSelf.workerQueue, ^{
            if (translation.length > 0) {
                I2FTranslationRecord *record = [[I2FTranslationRecord alloc] init];
                record.original = next;
                record.translated = translation;
                record.context = ctx;
                record.targetLanguage = strongSelf.ggTranslator.targetLanguageTag;
                record.timestamp = [NSDate date];
                [strongSelf storeTranslatedRecordsOnQueue:@[record]];
                void (^callback)(I2FTranslationRecord *) = strongSelf.translationDidUpdate;
                if (callback) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        callback(record);
                    });
                }
                NSLog(@"[I2FTrans] translate success len=%lu", (unsigned long)next.length);
            } else {
                // 翻译失败则回滚到待翻译队列，等待后续重试。
                [strongSelf insertPendingOnQueueWithOriginal:next context:ctx];
                strongSelf.autoTranslating = NO;
                NSLog(@"[I2FTrans] translate failed len=%lu", (unsigned long)next.length);
                return;
            }
            [strongSelf processNextPendingOnQueue];
        });
    }];
}

@end
