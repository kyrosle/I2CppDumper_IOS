#import "I2FIl2CppTextHookState.h"

@interface I2FIl2CppTextHookState ()

@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSString *> *methodToName;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *methodToOriginal;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *nameToMethod;
@property (nonatomic, strong) NSMutableSet<NSString *> *installedNames;
@property (nonatomic, strong) NSMutableDictionary<NSString *, I2FPendingRefresh *> *pendingRefresh;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *slotToOriginal;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *nameToSlot;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSString *> *originalPointerToName;
@property (nonatomic, strong) dispatch_queue_t stateQueue;

@end

@implementation I2FIl2CppTextHookState

+ (instancetype)shared {
    static I2FIl2CppTextHookState *state = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        state = [[I2FIl2CppTextHookState alloc] init];
    });
    return state;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _methodToName = [NSMutableDictionary dictionary];
        _methodToOriginal = [NSMutableDictionary dictionary];
        _nameToMethod = [NSMutableDictionary dictionary];
        _installedNames = [NSMutableSet set];
        _pendingRefresh = [NSMutableDictionary dictionary];
        _slotToOriginal = [NSMutableDictionary dictionary];
        _nameToSlot = [NSMutableDictionary dictionary];
        _originalPointerToName = [NSMutableDictionary dictionary];
        _stateQueue = dispatch_queue_create("i2f.text.hook.state", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSString *)nameForMethodKey:(NSValue *)methodKey {
    if (!methodKey) {
        return nil;
    }
    __block NSString *value = nil;
    dispatch_sync(self.stateQueue, ^{
        value = self.methodToName[methodKey];
    });
    return value;
}

- (void)setName:(NSString *)name forMethodKey:(NSValue *)methodKey {
    if (!methodKey) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        if (name) {
            self.methodToName[methodKey] = name;
        } else {
            [self.methodToName removeObjectForKey:methodKey];
        }
    });
}

- (NSValue *)originalPointerForMethodKey:(NSValue *)methodKey {
    if (!methodKey) {
        return nil;
    }
    __block NSValue *value = nil;
    dispatch_sync(self.stateQueue, ^{
        value = self.methodToOriginal[methodKey];
    });
    return value;
}

- (void)setOriginalPointer:(NSValue *)pointer forMethodKey:(NSValue *)methodKey {
    if (!methodKey) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        if (pointer) {
            self.methodToOriginal[methodKey] = pointer;
        } else {
            [self.methodToOriginal removeObjectForKey:methodKey];
        }
    });
}

- (NSValue *)methodKeyForName:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    __block NSValue *value = nil;
    dispatch_sync(self.stateQueue, ^{
        value = self.nameToMethod[name];
    });
    return value;
}

- (void)setMethodKey:(NSValue *)methodKey forName:(NSString *)name {
    if (name.length == 0) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        if (methodKey) {
            self.nameToMethod[name] = methodKey;
        } else {
            [self.nameToMethod removeObjectForKey:name];
        }
    });
}

- (void)recordInstalledName:(NSString *)name {
    if (name.length == 0) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        [self.installedNames addObject:name];
    });
}

- (void)removeInstalledName:(NSString *)name {
    if (name.length == 0) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        [self.installedNames removeObject:name];
    });
}

- (BOOL)hasInstalledName:(NSString *)name {
    if (name.length == 0) {
        return NO;
    }
    __block BOOL contains = NO;
    dispatch_sync(self.stateQueue, ^{
        contains = [self.installedNames containsObject:name];
    });
    return contains;
}

- (void)setPendingRefresh:(I2FPendingRefresh *)refresh forOriginal:(NSString *)original {
    if (original.length == 0) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        if (refresh) {
            self.pendingRefresh[original] = refresh;
        } else {
            [self.pendingRefresh removeObjectForKey:original];
        }
    });
}

- (I2FPendingRefresh *)consumePendingRefreshForOriginal:(NSString *)original {
    if (original.length == 0) {
        return nil;
    }
    __block I2FPendingRefresh *refresh = nil;
    dispatch_barrier_sync(self.stateQueue, ^{
        refresh = self.pendingRefresh[original];
        if (refresh) {
            [self.pendingRefresh removeObjectForKey:original];
        }
    });
    return refresh;
}

- (void)setSlot:(NSValue *)slotKey original:(NSValue *)origPointer forName:(NSString *)name {
    if (!slotKey) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        if (origPointer) {
            self.slotToOriginal[slotKey] = origPointer;
        } else {
            [self.slotToOriginal removeObjectForKey:slotKey];
        }
        if (name.length > 0) {
            self.nameToSlot[name] = slotKey;
        } else {
            [self.nameToSlot removeObjectForKey:name];
        }
    });
}

- (NSValue *)slotForName:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    __block NSValue *value = nil;
    dispatch_sync(self.stateQueue, ^{
        value = self.nameToSlot[name];
    });
    return value;
}

- (NSValue *)originalForSlot:(NSValue *)slotKey {
    if (!slotKey) {
        return nil;
    }
    __block NSValue *value = nil;
    dispatch_sync(self.stateQueue, ^{
        value = self.slotToOriginal[slotKey];
    });
    return value;
}

- (void)removeSlotForName:(NSString *)name {
    if (name.length == 0) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        NSValue *slotKey = self.nameToSlot[name];
        if (slotKey) {
            [self.slotToOriginal removeObjectForKey:slotKey];
        }
        [self.nameToSlot removeObjectForKey:name];
    });
}

- (NSString *)nameForOriginalPointer:(NSValue *)pointer {
    if (!pointer) {
        return nil;
    }
    __block NSString *value = nil;
    dispatch_sync(self.stateQueue, ^{
        value = self.originalPointerToName[pointer];
    });
    return value;
}

- (void)setName:(NSString *)name forOriginalPointer:(NSValue *)pointer {
    if (!pointer) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        if (name) {
            self.originalPointerToName[pointer] = name;
        } else {
            [self.originalPointerToName removeObjectForKey:pointer];
        }
    });
}

- (void)removeNameForOriginalPointer:(NSValue *)pointer {
    if (!pointer) {
        return;
    }
    dispatch_barrier_sync(self.stateQueue, ^{
        [self.originalPointerToName removeObjectForKey:pointer];
    });
}

@end
