#import "KSBallSettings.h"
#import <math.h>

const NSUInteger KSBallMaximumShortcuts = 48;
const CGFloat KSBallMinimumIconSize = 32.0;
const CGFloat KSBallMaximumIconSize = 64.0;
const CGFloat KSBallDefaultIconSize = 50.0;
const CGFloat KSBallMinimumIconSpacing = 0.0;
const CGFloat KSBallMaximumIconSpacing = 32.0;
const CGFloat KSBallDefaultIconSpacing = 12.0;
const CGFloat KSBallMinimumRingSpacing = 0.0;
const CGFloat KSBallMaximumRingSpacing = 32.0;
const CGFloat KSBallDefaultRingSpacing = 12.0;
const CGFloat KSBallMinimumBackdropOpacity = 0.1;
const CGFloat KSBallDefaultBackdropOpacity = 1.0;
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
    settings.shortcuts = [NSMutableArray array];
    return settings;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconSize = KSBallDefaultIconSize;
        _iconSpacing = KSBallDefaultIconSpacing;
        _ringSpacing = KSBallDefaultRingSpacing;
        _handleStyle = KSBallHandleStyleLight;
        _backdropStyle = KSBallBackdropStyleDark;
        _backdropOpacity = KSBallDefaultBackdropOpacity;
        _shortcuts = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KSBallSettings *copy = [[[self class] allocWithZone:zone] init];
    copy.enabled = self.enabled;
    copy.edge = self.edge;
    copy.normalizedVerticalPosition = self.normalizedVerticalPosition;
    copy.iconSize = self.iconSize;
    copy.iconSpacing = self.iconSpacing;
    copy.ringSpacing = self.ringSpacing;
    copy.handleStyle = self.handleStyle;
    copy.backdropStyle = self.backdropStyle;
    copy.backdropOpacity = self.backdropOpacity;
    for (KSBallShortcut *shortcut in self.shortcuts) {
        [copy.shortcuts addObject:[shortcut copy]];
    }
    return copy;
}

- (void)normalize {
    self.normalizedVerticalPosition = MIN(MAX(self.normalizedVerticalPosition, 0.0), 1.0);
    self.edge = self.edge == KSBallEdgeLeft ? KSBallEdgeLeft : KSBallEdgeRight;
    self.iconSize = isfinite(self.iconSize) ? MIN(MAX(self.iconSize, KSBallMinimumIconSize), KSBallMaximumIconSize) : KSBallDefaultIconSize;
    self.iconSpacing = isfinite(self.iconSpacing) ? MIN(MAX(self.iconSpacing, KSBallMinimumIconSpacing), KSBallMaximumIconSpacing) : KSBallDefaultIconSpacing;
    self.ringSpacing = isfinite(self.ringSpacing) ? MIN(MAX(self.ringSpacing, KSBallMinimumRingSpacing), KSBallMaximumRingSpacing) : KSBallDefaultRingSpacing;
    self.backdropOpacity = isfinite(self.backdropOpacity) ? MIN(MAX(self.backdropOpacity, KSBallMinimumBackdropOpacity), 1.0) : KSBallDefaultBackdropOpacity;
    if (self.handleStyle < KSBallHandleStyleLight || self.handleStyle > KSBallHandleStyleHidden) {
        self.handleStyle = KSBallHandleStyleLight;
    }
    if (self.backdropStyle < KSBallBackdropStyleLight || self.backdropStyle > KSBallBackdropStyleNone) {
        self.backdropStyle = KSBallBackdropStyleDark;
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
        @"iconSize": @(self.iconSize),
        @"iconSpacing": @(self.iconSpacing),
        @"ringSpacing": @(self.ringSpacing),
        @"handleStyle": @(self.handleStyle),
        @"backdropStyle": @(self.backdropStyle),
        @"backdropOpacity": @(self.backdropOpacity),
        @"shortcuts": shortcuts,
    };
}

+ (instancetype)settingsFromDictionary:(NSDictionary<NSString *,id> *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        return [self defaultSettings];
    }

    KSBallSettings *settings = [self defaultSettings];
    NSNumber *(^number)(NSString *) = ^NSNumber *(NSString *key) {
        return [dictionary[key] isKindOfClass:NSNumber.class] ? dictionary[key] : nil;
    };
    NSNumber *enabled = number(@"enabled");
    NSNumber *edge = number(@"edge");
    NSNumber *verticalPosition = number(@"normalizedVerticalPosition");
    NSNumber *iconSize = number(@"iconSize");
    NSNumber *iconSpacing = number(@"iconSpacing");
    // 圈间距是独立的布局配置；旧设置中没有这一项时使用它自己的默认值。
    NSNumber *ringSpacing = number(@"ringSpacing");
    NSNumber *handleStyle = number(@"handleStyle");
    NSNumber *backdropStyle = number(@"backdropStyle");
    NSNumber *backdropOpacity = number(@"backdropOpacity");
    if (enabled) settings.enabled = enabled.boolValue;
    if (edge) settings.edge = edge.integerValue;
    if (verticalPosition) settings.normalizedVerticalPosition = verticalPosition.doubleValue;
    if (iconSize) settings.iconSize = iconSize.doubleValue;
    if (iconSpacing) settings.iconSpacing = iconSpacing.doubleValue;
    if (ringSpacing) settings.ringSpacing = ringSpacing.doubleValue;
    if (handleStyle) settings.handleStyle = handleStyle.integerValue;
    if (backdropStyle) settings.backdropStyle = backdropStyle.integerValue;
    if (backdropOpacity) settings.backdropOpacity = backdropOpacity.doubleValue;

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
