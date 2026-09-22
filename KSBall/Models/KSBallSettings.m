#import "KSBallSettings.h"

const NSUInteger KSBallMaximumShortcuts = 16;
static NSInteger const KSBallSettingsSchemaVersion = 1;

@implementation KSBallShortcut

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName {
    self = [super init];
    if (self) {
        _identifier = [NSUUID UUID];
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KSBallShortcut *copy = [[[self class] allocWithZone:zone] initWithBundleIdentifier:self.bundleIdentifier displayName:self.displayName];
    [copy setValue:self.identifier forKey:@"_identifier"];
    return copy;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"id": self.identifier.UUIDString,
        @"bundleIdentifier": self.bundleIdentifier ?: @"",
        @"displayName": self.displayName ?: @"",
    };
}

+ (instancetype)shortcutFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    NSString *bundleIdentifier = [dictionary[@"bundleIdentifier"] isKindOfClass:NSString.class] ? dictionary[@"bundleIdentifier"] : nil;
    NSString *displayName = [dictionary[@"displayName"] isKindOfClass:NSString.class] ? dictionary[@"displayName"] : bundleIdentifier;
    if (bundleIdentifier.length == 0 || displayName.length == 0) {
        return nil;
    }

    KSBallShortcut *shortcut = [[self alloc] initWithBundleIdentifier:bundleIdentifier displayName:displayName];
    NSString *identifier = [dictionary[@"id"] isKindOfClass:NSString.class] ? dictionary[@"id"] : nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
    if (uuid) {
        [shortcut setValue:uuid forKey:@"_identifier"];
    }
    return shortcut;
}

@end

@implementation KSBallSettings

+ (instancetype)defaultSettings {
    KSBallSettings *settings = [self new];
    settings.enabled = YES;
    settings.edge = KSBallEdgeRight;
    settings.normalizedVerticalPosition = 0.5;
    settings.fanBias = KSBallFanBiasCenter;
    settings.shortcuts = [NSMutableArray array];
    return settings;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _shortcuts = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KSBallSettings *copy = [[[self class] allocWithZone:zone] init];
    copy.enabled = self.enabled;
    copy.edge = self.edge;
    copy.normalizedVerticalPosition = self.normalizedVerticalPosition;
    copy.fanBias = self.fanBias;
    for (KSBallShortcut *shortcut in self.shortcuts) {
        [copy.shortcuts addObject:[shortcut copy]];
    }
    return copy;
}

- (void)normalize {
    self.normalizedVerticalPosition = MIN(MAX(self.normalizedVerticalPosition, 0.0), 1.0);
    self.edge = self.edge == KSBallEdgeLeft ? KSBallEdgeLeft : KSBallEdgeRight;
    if (self.fanBias < KSBallFanBiasUpper || self.fanBias > KSBallFanBiasLower) {
        self.fanBias = KSBallFanBiasCenter;
    }

    NSMutableArray<KSBallShortcut *> *validShortcuts = [NSMutableArray array];
    NSMutableSet<NSString *> *bundleIdentifiers = [NSMutableSet set];
    for (KSBallShortcut *shortcut in self.shortcuts) {
        NSString *identifier = shortcut.bundleIdentifier.lowercaseString;
        if (identifier.length == 0 || [bundleIdentifiers containsObject:identifier]) {
            continue;
        }
        [bundleIdentifiers addObject:identifier];
        [validShortcuts addObject:shortcut];
        if (validShortcuts.count == KSBallMaximumShortcuts) {
            break;
        }
    }
    self.shortcuts = validShortcuts;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    [self normalize];
    NSMutableArray<NSDictionary<NSString *, id> *> *shortcuts = [NSMutableArray arrayWithCapacity:self.shortcuts.count];
    for (KSBallShortcut *shortcut in self.shortcuts) {
        [shortcuts addObject:shortcut.dictionaryRepresentation];
    }
    return @{
        @"schemaVersion": @(KSBallSettingsSchemaVersion),
        @"enabled": @(self.enabled),
        @"edge": @(self.edge),
        @"normalizedVerticalPosition": @(self.normalizedVerticalPosition),
        @"fanBias": @(self.fanBias),
        @"shortcuts": shortcuts,
    };
}

+ (instancetype)settingsFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return [self defaultSettings];
    }

    KSBallSettings *settings = [self defaultSettings];
    NSNumber *enabled = [dictionary[@"enabled"] isKindOfClass:NSNumber.class] ? dictionary[@"enabled"] : nil;
    NSNumber *edge = [dictionary[@"edge"] isKindOfClass:NSNumber.class] ? dictionary[@"edge"] : nil;
    NSNumber *verticalPosition = [dictionary[@"normalizedVerticalPosition"] isKindOfClass:NSNumber.class] ? dictionary[@"normalizedVerticalPosition"] : nil;
    NSNumber *fanBias = [dictionary[@"fanBias"] isKindOfClass:NSNumber.class] ? dictionary[@"fanBias"] : nil;
    if (enabled) settings.enabled = enabled.boolValue;
    if (edge) settings.edge = edge.integerValue;
    if (verticalPosition) settings.normalizedVerticalPosition = verticalPosition.doubleValue;
    if (fanBias) settings.fanBias = fanBias.integerValue;

    NSArray *shortcutDictionaries = [dictionary[@"shortcuts"] isKindOfClass:NSArray.class] ? dictionary[@"shortcuts"] : @[];
    for (id item in shortcutDictionaries) {
        if (![item isKindOfClass:NSDictionary.class]) {
            continue;
        }
        KSBallShortcut *shortcut = [KSBallShortcut shortcutFromDictionary:item];
        if (shortcut) {
            [settings.shortcuts addObject:shortcut];
        }
    }
    [settings normalize];
    return settings;
}

@end
