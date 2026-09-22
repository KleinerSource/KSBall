#import "KSBallSettingsStore.h"

NSNotificationName const KSBallSettingsDidChangeNotification = @"KSBallSettingsDidChangeNotification";
static NSString * const KSBallSettingsDefaultsKey = @"KSBall.Settings";

@interface KSBallSettingsStore ()
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, copy) NSString *defaultsKey;
@property (nonatomic, copy, readwrite) KSBallSettings *settings;
@end

@implementation KSBallSettingsStore

+ (instancetype)sharedStore {
    static KSBallSettingsStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] initWithUserDefaults:NSUserDefaults.standardUserDefaults key:KSBallSettingsDefaultsKey];
    });
    return store;
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        _defaultsKey = [key copy];
        [self reload];
    }
    return self;
}

- (void)reload {
    NSData *data = [self.userDefaults dataForKey:self.defaultsKey];
    NSDictionary *dictionary = nil;
    if (data) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) {
            dictionary = value;
        }
    }
    self.settings = [KSBallSettings settingsFromDictionary:dictionary];
}

- (void)mutateSettings:(void (NS_NOESCAPE ^)(KSBallSettings *settings))mutation {
    mutation(self.settings);
    [self.settings normalize];
    NSDictionary *dictionary = self.settings.dictionaryRepresentation;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    if (data) {
        [self.userDefaults setObject:data forKey:self.defaultsKey];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KSBallSettingsDidChangeNotification object:self];
}

- (BOOL)addShortcut:(KSBallShortcut *)shortcut {
    if (shortcut.bundleIdentifier.length == 0 || self.settings.shortcuts.count >= KSBallMaximumShortcuts) {
        return NO;
    }

    for (KSBallShortcut *existingShortcut in self.settings.shortcuts) {
        if ([existingShortcut.bundleIdentifier caseInsensitiveCompare:shortcut.bundleIdentifier] == NSOrderedSame) {
            return NO;
        }
    }
    [self mutateSettings:^(KSBallSettings *settings) {
        [settings.shortcuts addObject:shortcut];
    }];
    return YES;
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
