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
const CGFloat KSBallMinimumBackdropBlur = 0.1;
const CGFloat KSBallDefaultBackdropBlur = 1.0;
const CGFloat KSBallMinimumHandleTouchRadius = 4.0;
const CGFloat KSBallMaximumHandleTouchRadius = 60.0;
const CGFloat KSBallDefaultHandleTouchRadius = 38.0;
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
    copy.opensInFloatingWindow = self.opensInFloatingWindow;
    return copy;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
    return @{
        @"id": self.identifier.UUIDString,
        @"bundleIdentifier": self.bundleIdentifier ?: @"",
        @"displayName": self.displayName ?: @"",
        @"floatingWindow": @(self.opensInFloatingWindow),
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
    // 旧设置没有这一项，默认全屏启动。
    NSNumber *floatingWindow = [dictionary[@"floatingWindow"] isKindOfClass:NSNumber.class] ? dictionary[@"floatingWindow"] : nil;
    shortcut.opensInFloatingWindow = floatingWindow.boolValue;
    return shortcut;
}

@end

@implementation KSBallSettings

+ (instancetype)defaultSettings {
    KSBallSettings *settings = [self new];
    settings.enabled = YES;
    settings.floatingSplitEnabled = YES;
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
        _handleStyle = KSBallHandleStyleAutomatic;
        _handleTouchRadius = KSBallDefaultHandleTouchRadius;
        _backdropStyle = KSBallBackdropStyleAutomatic;
        _keyboardPresentationMode = KSBallKeyboardPresentationModeGlobal;
        _backdropBlur = KSBallDefaultBackdropBlur;
        _shortcuts = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KSBallSettings *copy = [[[self class] allocWithZone:zone] init];
    copy.enabled = self.enabled;
    copy.floatingSplitEnabled = self.floatingSplitEnabled;
    copy.edge = self.edge;
    copy.normalizedVerticalPosition = self.normalizedVerticalPosition;
    copy.iconSize = self.iconSize;
    copy.iconSpacing = self.iconSpacing;
    copy.ringSpacing = self.ringSpacing;
    copy.handleStyle = self.handleStyle;
    copy.handleTouchRadius = self.handleTouchRadius;
    copy.backdropStyle = self.backdropStyle;
    copy.keyboardPresentationMode = self.keyboardPresentationMode;
    copy.backdropBlur = self.backdropBlur;
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
    self.backdropBlur = isfinite(self.backdropBlur) ? MIN(MAX(self.backdropBlur, KSBallMinimumBackdropBlur), 1.0) : KSBallDefaultBackdropBlur;
    self.handleTouchRadius = isfinite(self.handleTouchRadius) ? MIN(MAX(self.handleTouchRadius, KSBallMinimumHandleTouchRadius), KSBallMaximumHandleTouchRadius) : KSBallDefaultHandleTouchRadius;
    if (self.handleStyle < KSBallHandleStyleLight || self.handleStyle > KSBallHandleStyleAutomatic) {
        self.handleStyle = KSBallHandleStyleAutomatic;
    }
    if (self.backdropStyle < KSBallBackdropStyleLight || self.backdropStyle > KSBallBackdropStyleAutomatic) {
        self.backdropStyle = KSBallBackdropStyleAutomatic;
    }
    if (self.keyboardPresentationMode != KSBallKeyboardPresentationModeFloatingWindow && self.keyboardPresentationMode != KSBallKeyboardPresentationModeGlobal) {
        self.keyboardPresentationMode = KSBallKeyboardPresentationModeGlobal;
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

- (BOOL)hasFloatingWindowShortcuts {
    for (KSBallShortcut *shortcut in self.shortcuts) {
        if (shortcut.opensInFloatingWindow) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)shouldEnableFloatingAppHosting {
    return self.floatingSplitEnabled && self.hasFloatingWindowShortcuts;
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
        @"floatingSplitEnabled": @(self.floatingSplitEnabled),
        @"edge": @(self.edge),
        @"normalizedVerticalPosition": @(self.normalizedVerticalPosition),
        @"iconSize": @(self.iconSize),
        @"iconSpacing": @(self.iconSpacing),
        @"ringSpacing": @(self.ringSpacing),
        @"handleStyle": @(self.handleStyle),
        @"handleTouchRadius": @(self.handleTouchRadius),
        @"backdropStyle": @(self.backdropStyle),
        @"keyboardPresentationMode": @(self.keyboardPresentationMode),
        @"backdropBlur": @(self.backdropBlur),
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
    NSNumber *floatingSplitEnabled = number(@"floatingSplitEnabled");
    NSNumber *edge = number(@"edge");
    NSNumber *verticalPosition = number(@"normalizedVerticalPosition");
    NSNumber *iconSize = number(@"iconSize");
    NSNumber *iconSpacing = number(@"iconSpacing");
    // 圈间距是独立的布局配置；旧设置中没有这一项时使用它自己的默认值。
    NSNumber *ringSpacing = number(@"ringSpacing");
    NSNumber *handleStyle = number(@"handleStyle");
    NSNumber *handleTouchRadius = number(@"handleTouchRadius");
    NSNumber *backdropStyle = number(@"backdropStyle");
    NSNumber *keyboardPresentationMode = number(@"keyboardPresentationMode");
    NSNumber *backdropBlur = number(@"backdropBlur");
    if (enabled) settings.enabled = enabled.boolValue;
    if (floatingSplitEnabled) settings.floatingSplitEnabled = floatingSplitEnabled.boolValue;
    if (edge) settings.edge = edge.integerValue;
    if (verticalPosition) settings.normalizedVerticalPosition = verticalPosition.doubleValue;
    if (iconSize) settings.iconSize = iconSize.doubleValue;
    if (iconSpacing) settings.iconSpacing = iconSpacing.doubleValue;
    if (ringSpacing) settings.ringSpacing = ringSpacing.doubleValue;
    if (handleStyle) settings.handleStyle = handleStyle.integerValue;
    if (handleTouchRadius) settings.handleTouchRadius = handleTouchRadius.doubleValue;
    if (backdropStyle) settings.backdropStyle = backdropStyle.integerValue;
    if (keyboardPresentationMode) settings.keyboardPresentationMode = keyboardPresentationMode.integerValue;
    if (backdropBlur) settings.backdropBlur = backdropBlur.doubleValue;

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
