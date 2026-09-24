#import "KSBallSettingsStore.h"
#import "KSBallSharedStorage.h"
#import <notify.h>

NSNotificationName const KSBallSettingsDidChangeNotification = @"KSBallSettingsDidChangeNotification";
static NSString * const KSBallSettingsDefaultsKey = @"KSBall.Settings";
// 主程序与 HUD 子进程通过共享文件保存设置，用 Darwin 通知互相告知变更。
static const char * const KSBallSettingsDarwinNotification = "com.kleinersource.ksball.settings-changed";

@interface KSBallSettingsStore ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, copy) NSString *defaultsKey;
@property (nonatomic, copy, nullable) NSString *sharedStorageKey;
@property (nonatomic, copy, readwrite) KSBallSettings *settings;
@property (nonatomic, copy, nullable) NSData *lastSyncedData;
@property (nonatomic) int externalChangeToken;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key sharedStorageKey:(nullable NSString *)sharedStorageKey;
@end

@implementation KSBallSettingsStore

+ (instancetype)sharedStore {
    static KSBallSettingsStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] initWithUserDefaults:NSUserDefaults.standardUserDefaults key:KSBallSettingsDefaultsKey sharedStorageKey:@"settings.json"];
    });
    return store;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key {
    return [self initWithUserDefaults:userDefaults key:key sharedStorageKey:nil];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key sharedStorageKey:(NSString *)sharedStorageKey {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        _defaultsKey = [key copy];
        _sharedStorageKey = [sharedStorageKey copy];
        _externalChangeToken = NOTIFY_TOKEN_INVALID;
        [self reload];
        if (_sharedStorageKey) {
            __weak typeof(self) weakSelf = self;
            notify_register_dispatch(KSBallSettingsDarwinNotification, &_externalChangeToken, dispatch_get_main_queue(), ^(int token) {
                [weakSelf handleExternalChange];
            });
        }
    }
    return self;
}

- (void)dealloc {
    if (_externalChangeToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_externalChangeToken);
    }
}

- (void)handleExternalChange {
    NSData *data = [KSBallSharedStorage dataForKey:self.sharedStorageKey];
    // 自己写入后也会收到通知；内容未变化时忽略，避免重复刷新界面。
    if (!data || [data isEqualToData:self.lastSyncedData]) {
        return;
    }
    [self reload];
    [[NSNotificationCenter defaultCenter] postNotificationName:KSBallSettingsDidChangeNotification object:self];
}

- (void)reload {
    NSData *data = self.sharedStorageKey ? [KSBallSharedStorage dataForKey:self.sharedStorageKey] : nil;
    BOOL hasSharedData = data != nil;
    if (!data) {
        data = [self.userDefaults dataForKey:self.defaultsKey];
    }
    NSDictionary *dictionary = nil;
    if (data) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) {
            dictionary = value;
        }
    }
    self.settings = [KSBallSettings settingsFromDictionary:dictionary];
    if (hasSharedData) {
        self.lastSyncedData = data;
    } else if (self.sharedStorageKey) {
        NSData *sharedData = [NSJSONSerialization dataWithJSONObject:self.settings.dictionaryRepresentation options:0 error:nil];
        if (sharedData) {
            [KSBallSharedStorage setData:sharedData forKey:self.sharedStorageKey];
            self.lastSyncedData = sharedData;
        }
    }
}

- (void)mutateSettings:(void (NS_NOESCAPE ^)(KSBallSettings *settings))mutation {
    [self reload];
    mutation(self.settings);
    [self.settings normalize];
    NSDictionary *dictionary = self.settings.dictionaryRepresentation;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    if (data) {
        [self.userDefaults setObject:data forKey:self.defaultsKey];
        if (self.sharedStorageKey && [KSBallSharedStorage setData:data forKey:self.sharedStorageKey]) {
            self.lastSyncedData = data;
            notify_post(KSBallSettingsDarwinNotification);
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KSBallSettingsDidChangeNotification object:self];
}

- (BOOL)addShortcut:(KSBallShortcut *)shortcut {
    return [self addShortcuts:@[shortcut]] == 1;
}

- (NSUInteger)addShortcuts:(NSArray<KSBallShortcut *> *)shortcuts {
    // 先在当前设置上筛出可添加的项，再一次性写入，只触发一次同步和一次悬浮条预览。
    [self reload];
    NSMutableSet<NSString *> *bundleIdentifiers = [NSMutableSet set];
    for (KSBallShortcut *existingShortcut in self.settings.shortcuts) {
        [bundleIdentifiers addObject:existingShortcut.bundleIdentifier.lowercaseString];
    }
    NSMutableArray<KSBallShortcut *> *acceptedShortcuts = [NSMutableArray array];
    for (KSBallShortcut *shortcut in shortcuts) {
        NSString *identifier = shortcut.bundleIdentifier.lowercaseString;
        if (identifier.length == 0 || [bundleIdentifiers containsObject:identifier]) {
            continue;
        }
        if (self.settings.shortcuts.count + acceptedShortcuts.count >= KSBallMaximumShortcuts) {
            break;
        }
        [bundleIdentifiers addObject:identifier];
        [acceptedShortcuts addObject:shortcut];
    }
    if (acceptedShortcuts.count == 0) {
        return 0;
    }
    [self mutateSettings:^(KSBallSettings *settings) {
        [settings.shortcuts addObjectsFromArray:acceptedShortcuts];
    }];
    return acceptedShortcuts.count;
}

- (void)removeShortcutAtIndex:(NSUInteger)index {
    if (index >= self.settings.shortcuts.count) {
        return;
    }
    [self mutateSettings:^(KSBallSettings *settings) {
        [settings.shortcuts removeObjectAtIndex:index];
    }];
}

- (void)moveShortcutFromIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex {
    if (fromIndex >= self.settings.shortcuts.count || toIndex >= self.settings.shortcuts.count || fromIndex == toIndex) {
        return;
    }
    [self mutateSettings:^(KSBallSettings *settings) {
        KSBallShortcut *shortcut = settings.shortcuts[fromIndex];
        [settings.shortcuts removeObjectAtIndex:fromIndex];
        [settings.shortcuts insertObject:shortcut atIndex:toIndex];
    }];
}

@end
