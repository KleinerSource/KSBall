#import "SystemApplicationBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

@implementation KSBallApplication

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName icon:(UIImage *)icon {
    self = [super init];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy];
        _icon = icon;
    }
    return self;
}

@end

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
        if ([self isSystemApplicationProxy:proxy]) {
            continue;
        }

        NSString *displayName = [self stringValueForObject:proxy selectors:@[@"localizedName", @"localizedShortName", @"itemName"]];
        if (displayName.length == 0) {
            displayName = bundleIdentifier;
        }
        [applications addObject:[[KSBallApplication alloc] initWithBundleIdentifier:bundleIdentifier displayName:displayName icon:[self iconForProxy:proxy]]];
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

- (BOOL)isSystemApplicationProxy:(id)proxy {
    SEL selector = NSSelectorFromString(@"isSystemOrInternalApp");
    if ([proxy respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(proxy, selector)) {
        return YES;
    }

    NSString *applicationType = [self stringValueForObject:proxy selectors:@[@"applicationType"]];
    if ([applicationType caseInsensitiveCompare:@"System"] == NSOrderedSame) {
        return YES;
    }
    selector = NSSelectorFromString(@"isLaunchProhibited");
    return [proxy respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(proxy, selector);
}

- (UIImage *)iconForProxy:(id)proxy {
    SEL selector = NSSelectorFromString(@"iconDataForVariant:");
    if (![proxy respondsToSelector:selector]) {
        selector = NSSelectorFromString(@"_iconDataForVariant:");
    }
    if (![proxy respondsToSelector:selector]) {
        return nil;
    }
    id iconData = ((id (*)(id, SEL, NSInteger))objc_msgSend)(proxy, selector, 2);
    return [iconData isKindOfClass:NSData.class] ? [UIImage imageWithData:iconData] : nil;
}

@end
