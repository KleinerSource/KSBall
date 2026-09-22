#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import "FloatingHUDViewController.h"
#import "PassthroughHUDWindow.h"
#import <dlfcn.h>
#import <objc/message.h>

NSString * const KSBallHUDActivityType = @"com.kleinersource.ksball.hud";
static NSString * const KSBallHUDSceneIdentifier = @"HUDScene";
static NSInteger const KSBallHUDSceneLevel = 100;

BOOL KSBallPrepareFrontBoardSystemShell(void) {
    static dispatch_once_t onceToken;
    static BOOL ready;
    dispatch_once(&onceToken, ^{
        void *frontBoardServices = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_GLOBAL);
        dlopen("/System/Library/PrivateFrameworks/FrontBoardHUD.framework/FrontBoardHUD", RTLD_LAZY | RTLD_GLOBAL);
        typedef void (*FBSystemShellInitializeFunction)(id);
        FBSystemShellInitializeFunction initializer = (FBSystemShellInitializeFunction)dlsym(frontBoardServices, "FBSystemShellInitialize");
        if (frontBoardServices && initializer) {
            initializer(^{});
            ready = YES;
        }
    });
    return ready;
}

@interface HUDSceneCoordinator ()
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong, nullable) UIWindow *hudWindow;
@property (nonatomic, strong, nullable) UISceneSession *hudSession;
@property (nonatomic, strong, nullable) id frontBoardHUDScene;
@property (nonatomic, strong, nullable) id presentationBinder;
@property (nonatomic) BOOL frontBoardReady;
@property (nonatomic) BOOL hudActivationRequested;
@property (nonatomic) BOOL ownsFrontBoardHUDScene;
@property (nonatomic, copy) NSString *frontBoardStatusDescription;

- (BOOL)attachWindowSceneToFrontBoard:(UIWindowScene *)windowScene;
- (id)frontBoardSceneForWindowScene:(UIWindowScene *)windowScene;
- (BOOL)createFrontBoardHUDScene;
@end

@implementation HUDSceneCoordinator

+ (instancetype)sharedCoordinator {
    static HUDSceneCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[self alloc] initWithSettingsStore:KSBallSettingsStore.sharedStore applicationBridge:SystemApplicationBridge.new];
    });
    return coordinator;
}

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super init];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _frontBoardStatusDescription = @"尚未请求 HUD 场景。";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:KSBallSettingsDidChangeNotification object:settingsStore];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isHUDActive {
    return self.hudWindow != nil && !self.hudWindow.hidden;
}

- (void)activateHUD {
    if (!self.settingsStore.settings.enabled) {
        return;
    }
    [self prepareFrontBoardSystemShell];

    if (self.hudWindow) {
        self.hudWindow.hidden = NO;
        [(FloatingHUDViewController *)self.hudWindow.rootViewController reloadFromSettings];
        return;
    }
    if (self.hudActivationRequested) {
        return;
    }

    self.hudActivationRequested = YES;
    self.frontBoardStatusDescription = self.frontBoardReady ? @"正在请求 UIKit HUD 窗口。" : @"FrontBoard 未就绪，正在请求 UIKit HUD 窗口。";
    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:KSBallHUDActivityType];
    activity.title = @"KSBall HUD";
    [[UIApplication sharedApplication] requestSceneSessionActivation:nil userActivity:activity options:nil errorHandler:^(NSError * _Nonnull error) {
        self.hudActivationRequested = NO;
        self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 窗口请求失败：%@", error.localizedDescription];
        NSLog(@"KSBall HUD scene activation failed: %@", error.localizedDescription);
    }];
}

- (void)rebuildHUD {
    [self deactivateHUD];
    if (self.settingsStore.settings.enabled) {
        [self activateHUD];
    }
}

- (void)deactivateHUD {
    self.hudWindow.hidden = YES;
    self.hudWindow.rootViewController = nil;
    self.hudWindow = nil;

    UISceneSession *session = self.hudSession;
    self.hudSession = nil;
    self.hudActivationRequested = NO;
    if (session) {
        [[UIApplication sharedApplication] requestSceneSessionDestruction:session options:nil errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"KSBall HUD scene destruction failed: %@", error.localizedDescription);
        }];
    }

    [self destroyFrontBoardHUDScene];
}

- (void)connectHUDWindow:(UIWindow *)window session:(UISceneSession *)session {
    self.hudWindow = window;
    self.hudSession = session;
    self.hudActivationRequested = NO;
    FloatingHUDViewController *controller = [[FloatingHUDViewController alloc] initWithSettingsStore:self.settingsStore applicationBridge:self.applicationBridge];
    __weak typeof(self) weakSelf = self;
    controller.openConfigurationHandler = ^{
        [weakSelf openConfiguration];
    };
    window.rootViewController = controller;
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = UIWindowLevelAlert + 2.0;
    [window makeKeyAndVisible];
    window.hidden = !self.settingsStore.settings.enabled;
    if (window.hidden) {
        self.frontBoardStatusDescription = @"HUD 场景已连接，但当前已停用。";
        return;
    }

    if ([self attachWindowSceneToFrontBoard:window.windowScene]) {
        self.frontBoardStatusDescription = @"FrontBoard HUD 已显示。";
    } else if ([self createFrontBoardHUDScene]) {
        self.frontBoardStatusDescription = @"HUD 窗口已连接，FrontBoard 回退场景已创建。";
    }
}

- (void)disconnectHUDSession:(UISceneSession *)session {
    if ([session.persistentIdentifier isEqualToString:self.hudSession.persistentIdentifier]) {
        self.hudWindow = nil;
        self.hudSession = nil;
        self.hudActivationRequested = NO;
    }
}

- (void)openConfiguration {
    [(FloatingHUDViewController *)self.hudWindow.rootViewController dismissMenuAnimated:YES];
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (![self.applicationBridge launchBundleIdentifier:bundleIdentifier]) {
        NSURL *url = [NSURL URLWithString:@"ksball://settings"];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)settingsDidChange:(NSNotification *)notification {
    FloatingHUDViewController *controller = (FloatingHUDViewController *)self.hudWindow.rootViewController;
    [controller reloadFromSettings];
    if (self.settingsStore.settings.enabled) {
        [self activateHUD];
    } else {
        [self deactivateHUD];
    }
}

- (void)prepareFrontBoardSystemShell {
    self.frontBoardReady = KSBallPrepareFrontBoardSystemShell();
    if (!self.frontBoardReady) {
        self.frontBoardStatusDescription = @"未找到 FrontBoard 系统壳接口。请确认通过 TrollStore 安装且权限已嵌入。";
    }
}

- (BOOL)attachWindowSceneToFrontBoard:(UIWindowScene *)windowScene {
    if (!self.frontBoardReady) {
        return NO;
    }

    id scene = [self frontBoardSceneForWindowScene:windowScene];
    if (!scene) {
        self.frontBoardStatusDescription = @"HUD 窗口已连接，但无法取得其 FrontBoard 场景。";
        return NO;
    }

    if (!self.presentationBinder) {
        Class binderClass = NSClassFromString(@"UIRootWindowScenePresentationBinder");
        id displayConfiguration = [self objectFromObject:UIScreen.mainScreen selector:@"displayConfiguration" argument:nil];
        id binder = [self objectFromClass:binderClass selector:@"alloc" argument:nil];
        binder = [self objectFromObject:binder selector:@"initWithPriority:displayConfiguration:" integerArgument:0 objectArgument:displayConfiguration];
        if (!binder) {
            self.frontBoardStatusDescription = @"无法创建 FrontBoard HUD 展示绑定器。";
            return NO;
        }
        self.presentationBinder = binder;
    }

    [self sendObject:scene toObject:self.presentationBinder selector:@"addScene:"];
    self.frontBoardHUDScene = scene;
    self.ownsFrontBoardHUDScene = NO;
    return YES;
}

- (id)frontBoardSceneForWindowScene:(UIWindowScene *)windowScene {
    for (NSString *selectorName in @[@"_fbsScene", @"fbsScene", @"_scene"]) {
        id scene = [self objectFromObject:windowScene selector:selectorName argument:nil];
        NSString *className = scene ? NSStringFromClass([scene class]) : @"";
        if ([className containsString:@"FBScene"] || [className containsString:@"FBSScene"]) {
            return scene;
        }
    }
    return nil;
}

- (BOOL)createFrontBoardHUDScene {
    if (self.frontBoardHUDScene) {
        self.frontBoardStatusDescription = @"FrontBoard HUD 场景已创建。";
        return YES;
    }
    if (!self.frontBoardReady || ![self hasFrontBoardSceneRuntime]) {
        return NO;
    }

    Class definitionClass = NSClassFromString(@"FBSMutableSceneDefinition");
    Class identityClass = NSClassFromString(@"FBSSceneIdentity");
    Class clientIdentityClass = NSClassFromString(@"FBSSceneClientIdentity");
    Class parametersClass = NSClassFromString(@"FBSMutableSceneParameters");
    Class settingsClass = NSClassFromString(@"UIMutableApplicationSceneSettings");
    Class clientSettingsClass = NSClassFromString(@"UIMutableApplicationSceneClientSettings");
    Class managerClass = NSClassFromString(@"FBSceneManager");
    Class binderClass = NSClassFromString(@"UIRootWindowScenePresentationBinder");

    id definition = [definitionClass new];
    id identity = [self objectFromClass:identityClass selector:@"identityForIdentifier:" argument:KSBallHUDSceneIdentifier];
    id clientIdentity = [self objectFromClass:clientIdentityClass selector:@"localIdentity" argument:nil];
    [self sendObject:identity toObject:definition selector:@"setIdentity:"];
    [self sendObject:clientIdentity toObject:definition selector:@"setClientIdentity:"];

    id specification = [self objectFromObject:definition selector:@"specification" argument:nil];
    id parameters = [self objectFromClass:parametersClass selector:@"parametersForSpecification:" argument:specification];
    if (!definition || !identity || !clientIdentity || !parameters) {
        self.frontBoardStatusDescription = @"FrontBoard HUD 参数初始化失败。";
        return NO;
    }

    UIScreen *screen = UIScreen.mainScreen;
    id settings = [settingsClass new];
    id displayConfiguration = [self objectFromObject:screen selector:@"displayConfiguration" argument:nil];
    if (displayConfiguration) {
        [self sendObject:displayConfiguration toObject:settings selector:@"setDisplayConfiguration:"];
    }
    [self sendFrame:screen.bounds toObject:settings selector:@"setFrame:"];
    [self sendInteger:KSBallHUDSceneLevel toObject:settings selector:@"setLevel:"];
    [self sendInteger:YES toObject:settings selector:@"setForeground:"];
    [self sendInteger:UIInterfaceOrientationPortrait toObject:settings selector:@"setInterfaceOrientation:"];
    [self sendInteger:YES toObject:settings selector:@"setDeviceOrientationEventsEnabled:"];
    id ignoredOcclusionReasons = [self objectFromObject:settings selector:@"ignoreOcclusionReasons" argument:nil];
    [self sendObject:@"SystemApp" toObject:ignoredOcclusionReasons selector:@"addObject:"];
    [self sendObject:settings toObject:parameters selector:@"setSettings:"];

    id clientSettings = [clientSettingsClass new];
    [self sendInteger:YES toObject:clientSettings selector:@"setForeground:"];
    [self sendInteger:UIInterfaceOrientationPortrait toObject:clientSettings selector:@"setInterfaceOrientation:"];
    [self sendObject:clientSettings toObject:parameters selector:@"setClientSettings:"];

    id manager = [self objectFromClass:managerClass selector:@"sharedInstance" argument:nil];
    id scene = [self objectFromObject:manager selector:@"createSceneWithDefinition:initialParameters:" firstArgument:definition secondArgument:parameters];
    if (!scene) {
        self.frontBoardStatusDescription = @"FBSceneManager 未能创建 HUD 场景。";
        return NO;
    }

    if (!self.presentationBinder) {
        self.presentationBinder = [self objectFromClass:binderClass selector:@"alloc" argument:nil];
        self.presentationBinder = [self objectFromObject:self.presentationBinder selector:@"initWithPriority:displayConfiguration:" integerArgument:0 objectArgument:displayConfiguration];
    }
    [self sendObject:scene toObject:self.presentationBinder selector:@"addScene:"];
    self.frontBoardHUDScene = scene;
    self.ownsFrontBoardHUDScene = YES;
    self.frontBoardStatusDescription = @"FrontBoard HUD 场景已创建，等待 HUD 窗口连接。";
    return YES;
}

- (void)destroyFrontBoardHUDScene {
    if (!self.frontBoardHUDScene) {
        return;
    }
    [self sendObject:self.frontBoardHUDScene toObject:self.presentationBinder selector:@"removeScene:"];
    if (self.ownsFrontBoardHUDScene) {
        id manager = [self objectFromClass:NSClassFromString(@"FBSceneManager") selector:@"sharedInstance" argument:nil];
        [self sendObject:self.frontBoardHUDScene toObject:manager selector:@"destroyScene:"];
    }
    self.frontBoardHUDScene = nil;
    self.ownsFrontBoardHUDScene = NO;
}

- (BOOL)hasFrontBoardSceneRuntime {
    NSArray<NSString *> *classNames = @[
        @"FBSMutableSceneDefinition", @"FBSSceneIdentity", @"FBSSceneClientIdentity",
        @"FBSMutableSceneParameters", @"UIMutableApplicationSceneSettings",
        @"UIMutableApplicationSceneClientSettings", @"FBSceneManager",
        @"UIRootWindowScenePresentationBinder"
    ];
    for (NSString *className in classNames) {
        if (!NSClassFromString(className)) {
            self.frontBoardStatusDescription = [NSString stringWithFormat:@"缺少 %@，无法创建全局 HUD。", className];
            return NO;
        }
    }
    return YES;
}

- (id)objectFromClass:(Class)class selector:(NSString *)selectorName argument:(id)argument {
    if (!class) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (![class respondsToSelector:selector]) {
        return nil;
    }
    return argument ? ((id (*)(id, SEL, id))objc_msgSend)(class, selector, argument) : ((id (*)(id, SEL))objc_msgSend)(class, selector);
}

- (id)objectFromObject:(id)object selector:(NSString *)selectorName argument:(id)argument {
    if (!object) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }
    return argument ? ((id (*)(id, SEL, id))objc_msgSend)(object, selector, argument) : ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

- (id)objectFromObject:(id)object selector:(NSString *)selectorName firstArgument:(id)firstArgument secondArgument:(id)secondArgument {
    if (!object) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL, id, id))objc_msgSend)(object, selector, firstArgument, secondArgument);
}

- (id)objectFromObject:(id)object selector:(NSString *)selectorName integerArgument:(NSInteger)integerArgument objectArgument:(id)objectArgument {
    if (!object) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(object, selector, integerArgument, objectArgument);
}

- (void)sendObject:(id)argument toObject:(id)object selector:(NSString *)selectorName {
    SEL selector = NSSelectorFromString(selectorName);
    if (object && [object respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
    }
}

- (void)sendInteger:(NSInteger)argument toObject:(id)object selector:(NSString *)selectorName {
    SEL selector = NSSelectorFromString(selectorName);
    if (object && [object respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, argument);
    }
}

- (void)sendFrame:(CGRect)frame toObject:(id)object selector:(NSString *)selectorName {
    SEL selector = NSSelectorFromString(selectorName);
    if (object && [object respondsToSelector:selector]) {
        ((void (*)(id, SEL, CGRect))objc_msgSend)(object, selector, frame);
    }
}

@end
