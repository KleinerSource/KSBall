#import "SystemApplicationBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

@implementation KSBallApplication

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName icon:(UIImage *)icon {
    return [self initWithBundleIdentifier:bundleIdentifier displayName:displayName icon:icon category:KSBallApplicationCategoryUser];
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName icon:(UIImage *)icon category:(KSBallApplicationCategory)category {
    self = [super init];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy];
        _icon = icon;
        _category = category;
    }
    return self;
}

@end

UIImage *KSBallListIconImage(UIImage *icon) {
    if (!icon) {
        return [UIImage systemImageNamed:@"app.fill"];
    }
    CGRect iconRect = CGRectMake(0.0, 0.0, 29.0, 29.0);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:iconRect.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIBezierPath bezierPathWithOvalInRect:iconRect] addClip];
        [icon drawInRect:iconRect];
    }];
}

@interface SystemApplicationBridge ()
@property (nonatomic, copy, nullable) KSBallApplicationProvider applicationProvider;
@property (nonatomic, copy, nullable) KSBallApplicationLauncher launcher;
@end

@implementation SystemApplicationBridge

- (instancetype)init {
    return [self initWithApplicationProvider:nil launcher:nil];
}

- (instancetype)initWithApplicationProvider:(KSBallApplicationProvider)applicationProvider launcher:(KSBallApplicationLauncher)launcher {
    self = [super init];
    if (self) {
        _applicationProvider = [applicationProvider copy];
        _launcher = [launcher copy];
        dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
    }
    return self;
}

- (BOOL)isAvailable {
    if (self.applicationProvider || self.launcher) {
        return YES;
    }
    return [self workspace] != nil;
}

- (NSString *)unavailabilityReason {
    return self.isAvailable ? @"" : @"当前系统未暴露 LaunchServices 工作区接口，无法读取或启动已安装应用。";
}

- (NSArray<KSBallApplication *> *)availableApplications {
    if (self.applicationProvider) {
        return self.applicationProvider();
    }

    id workspace = [self workspace];
    if (!workspace) {
        return @[];
    }

    // TrollStore 应用在 iOS 15-17 上可靠地公开于 allApplications；
    // allInstalledApplications 在部分版本会返回空数组。
    NSArray *proxies = [self applicationProxiesFromWorkspace:workspace];
    if (proxies.count == 0) {
        proxies = [self enumeratedApplicationProxiesFromWorkspace:workspace];
    }
    if (proxies.count == 0) {
        return @[];
    }
    NSMutableArray<KSBallApplication *> *applications = [NSMutableArray array];
    NSString *ownIdentifier = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
    for (id proxy in proxies) {
        NSString *bundleIdentifier = [self stringValueForObject:proxy selectors:@[@"applicationIdentifier", @"bundleIdentifier"]];
        if (bundleIdentifier.length == 0 || [bundleIdentifier.lowercaseString isEqualToString:ownIdentifier]) {
            continue;
        }
        if ([self isHiddenApplicationProxy:proxy]) {
            continue;
        }

        NSString *displayName = [self stringValueForObject:proxy selectors:@[@"localizedName", @"localizedShortName", @"itemName"]];
        if (displayName.length == 0) {
            displayName = bundleIdentifier;
        }
        [applications addObject:[[KSBallApplication alloc] initWithBundleIdentifier:bundleIdentifier displayName:displayName icon:[self iconForProxy:proxy] category:[self categoryForProxy:proxy]]];
    }

    return [applications sortedArrayUsingComparator:^NSComparisonResult(KSBallApplication *left, KSBallApplication *right) {
        return [left.displayName localizedCaseInsensitiveCompare:right.displayName];
    }];
}

- (NSArray *)applicationProxiesFromWorkspace:(id)workspace {
    SEL selector = NSSelectorFromString(@"allApplications");
    if ([workspace respondsToSelector:selector]) {
        id proxies = ((id (*)(id, SEL))objc_msgSend)(workspace, selector);
        if ([proxies isKindOfClass:NSArray.class]) {
            return proxies;
        }
    }

    selector = NSSelectorFromString(@"allInstalledApplications");
    if ([workspace respondsToSelector:selector]) {
        id proxies = ((id (*)(id, SEL))objc_msgSend)(workspace, selector);
        if ([proxies isKindOfClass:NSArray.class]) {
            return proxies;
        }
    }
    return @[];
}

- (NSArray *)enumeratedApplicationProxiesFromWorkspace:(id)workspace {
    SEL selector = NSSelectorFromString(@"enumerateApplicationsOfType:block:");
    if (![workspace respondsToSelector:selector]) {
        return @[];
    }

    NSMutableArray *proxies = [NSMutableArray array];
    void (^collector)(id, BOOL *) = ^(id proxy, BOOL *stop) {
        if (proxy) {
            [proxies addObject:proxy];
        }
    };
    ((void (*)(id, SEL, NSInteger, id))objc_msgSend)(workspace, selector, 0, collector);
    return proxies;
}

- (BOOL)launchBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return NO;
    }
    if (self.launcher) {
        return self.launcher(bundleIdentifier);
    }

    id workspace = [self workspace];
    SEL selector = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (![workspace respondsToSelector:selector]) {
        selector = NSSelectorFromString(@"openApplication:");
    }
    if (![workspace respondsToSelector:selector]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, selector, bundleIdentifier);
}

- (id)workspace {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL selector = NSSelectorFromString(@"defaultWorkspace");
    if (![workspaceClass respondsToSelector:selector]) {
        selector = NSSelectorFromString(@"sharedWorkspace");
    }
    if (![workspaceClass respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(workspaceClass, selector);
}

- (NSString *)stringValueForObject:(id)object selectors:(NSArray<NSString *> *)selectorNames {
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([object respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
            if ([value isKindOfClass:NSString.class] && [value length] > 0) {
                return value;
            }
        }
    }
    return nil;
}

// 系统应用也可以加入快捷列表；只排除主屏上本来就看不到或无法启动的应用（隐藏标签、禁止启动、占位符）。
- (BOOL)isHiddenApplicationProxy:(id)proxy {
    SEL selector = NSSelectorFromString(@"appTags");
    if ([proxy respondsToSelector:selector]) {
        id tags = ((id (*)(id, SEL))objc_msgSend)(proxy, selector);
        if ([tags isKindOfClass:NSArray.class] && [tags containsObject:@"hidden"]) {
            return YES;
        }
    }
    for (NSString *selectorName in @[@"isLaunchProhibited", @"isPlaceholder"]) {
        selector = NSSelectorFromString(selectorName);
        if ([proxy respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(proxy, selector)) {
            return YES;
        }
    }
    return NO;
}

// TrollStore 会在应用容器里（与 .app 同级）放置 _TrollStore 标记文件，并把应用注册为 System 类型，
// 所以必须先检查标记，再按系统类型区分。
- (KSBallApplicationCategory)categoryForProxy:(id)proxy {
    SEL bundleURLSelector = NSSelectorFromString(@"bundleURL");
    if ([proxy respondsToSelector:bundleURLSelector]) {
        NSURL *bundleURL = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleURLSelector);
        if ([bundleURL isKindOfClass:NSURL.class]) {
            NSString *markerPath = [bundleURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"_TrollStore"].path;
            if ([NSFileManager.defaultManager fileExistsAtPath:markerPath]) {
                return KSBallApplicationCategoryTrollStore;
            }
        }
    }
    SEL selector = NSSelectorFromString(@"isSystemOrInternalApp");
    if ([proxy respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(proxy, selector)) {
        return KSBallApplicationCategorySystem;
    }
    NSString *applicationType = [self stringValueForObject:proxy selectors:@[@"applicationType"]];
    return [applicationType caseInsensitiveCompare:@"System"] == NSOrderedSame ? KSBallApplicationCategorySystem : KSBallApplicationCategoryUser;
}

- (UIImage *)iconForProxy:(id)proxy {
    NSString *bundleIdentifier = [self stringValueForObject:proxy selectors:@[@"applicationIdentifier", @"bundleIdentifier"]];
    return bundleIdentifier ? [self iconForBundleIdentifier:bundleIdentifier] : nil;
}

- (UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) {
        return nil;
    }
    if (self.applicationProvider) {
        for (KSBallApplication *application in self.applicationProvider()) {
            if ([application.bundleIdentifier caseInsensitiveCompare:bundleIdentifier] == NSOrderedSame) {
                return application.icon;
            }
        }
        return nil;
    }

    // UIKit 私有接口直接返回已渲染好的主屏图标，格式 2 对应 60pt 主屏图标。
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:selector]) {
        return nil;
    }
    id icon = ((id (*)(id, SEL, id, int, CGFloat))objc_msgSend)(UIImage.class, selector, bundleIdentifier, 2, UIScreen.mainScreen.scale);
    return [icon isKindOfClass:UIImage.class] ? icon : nil;
}

@end
