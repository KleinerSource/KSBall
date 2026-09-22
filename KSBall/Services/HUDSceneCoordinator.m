#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import "FloatingHUDViewController.h"
#import "PassthroughHUDWindow.h"
#import <dlfcn.h>
#import <errno.h>
#import <objc/message.h>
#import <signal.h>
#import <spawn.h>
#import <string.h>
#import <unistd.h>

NSString * const KSBallHUDActivityType = @"com.kleinersource.ksball.hud";
static NSString * const KSBallHUDSceneIdentifier = @"KeepScene";
static NSInteger const KSBallHUDSceneLevel = 100;
static const char * const KSBallHUDProcessArgument = "-hud";
static NSString * const KSBallHUDProcessIdentifierDefaultsKey = @"KSBallHUDProcessIdentifier";
static const uid_t KSBallApplicationPersonaIdentifier = 99;
static const uint32_t KSBallApplicationPersonaFlags = 1;
static const short KSBallApplicationSpawnFlags = 2;

extern char **environ;

typedef int (*KSBallSetPersonaFunction)(const posix_spawnattr_t *attributes, uid_t personaIdentifier, uint32_t flags);
typedef int (*KSBallSetPersonaUIDFunction)(const posix_spawnattr_t *attributes, uid_t userIdentifier);
typedef int (*KSBallSetPersonaGIDFunction)(const posix_spawnattr_t *attributes, gid_t groupIdentifier);

static int KSBallConfigureBasicSpawnAttributes(posix_spawnattr_t *attributes) {
    int result = posix_spawnattr_setpgroup(attributes, 0);
    if (result != 0) {
        return result;
    }
    return posix_spawnattr_setflags(attributes, KSBallApplicationSpawnFlags);
}

static BOOL KSBallPrepareFrontBoardSystemShellWithBlock(dispatch_block_t block) {
    static dispatch_once_t onceToken;
    static BOOL ready;
    dispatch_once(&onceToken, ^{
        void *frontBoardServices = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_GLOBAL);
        dlopen("/System/Library/PrivateFrameworks/FrontBoardHUD.framework/FrontBoardHUD", RTLD_LAZY | RTLD_GLOBAL);
        typedef void (*FBSystemShellInitializeFunction)(dispatch_block_t);
        FBSystemShellInitializeFunction initializer = (FBSystemShellInitializeFunction)dlsym(frontBoardServices, "FBSystemShellInitialize");
        if (frontBoardServices && initializer) {
            initializer(block ?: ^{});
            ready = YES;
        }
    });
    return ready;
}

BOOL KSBallPrepareFrontBoardSystemShell(void) {
    return KSBallPrepareFrontBoardSystemShellWithBlock(nil);
}

BOOL KSBallIsHUDProcess(void) {
    NSString *argument = [NSString stringWithUTF8String:KSBallHUDProcessArgument];
    return [NSProcessInfo.processInfo.arguments containsObject:argument];
}

@interface HUDSceneCoordinator ()
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong, nullable) UIWindow *hudWindow;
@property (nonatomic, strong, nullable) UISceneSession *hudSession;
@property (nonatomic, strong, nullable) id frontBoardHUDScene;
@property (nonatomic, strong, nullable) id presentationBinder;
@property (nonatomic) BOOL frontBoardReady;
@property (nonatomic) BOOL ownsFrontBoardHUDScene;
@property (nonatomic, copy) NSString *frontBoardStatusDescription;

- (BOOL)createFrontBoardHUDScene;
- (BOOL)spawnHUDProcess;
- (BOOL)hasLiveHUDProcess;
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
    if (KSBallIsHUDProcess()) {
        return self.hudWindow != nil && !self.hudWindow.hidden;
    }
    return [self hasLiveHUDProcess];
}

- (void)activateHUD {
    if (!self.settingsStore.settings.enabled) {
        return;
    }

    if (KSBallIsHUDProcess()) {
        if (!self.hudWindow) {
            self.frontBoardStatusDescription = @"HUD 子进程正在等待窗口场景连接。";
            return;
        }
        self.hudWindow.hidden = NO;
        [(FloatingHUDViewController *)self.hudWindow.rootViewController reloadFromSettings];
        return;
    }

    if ([self hasLiveHUDProcess]) {
        self.frontBoardStatusDescription = @"HUD 子进程已在运行。";
        return;
    }
    [self spawnHUDProcess];
}

- (void)rebuildHUD {
    [self deactivateHUD];
    if (self.settingsStore.settings.enabled) {
        [self activateHUD];
    }
}

- (void)deactivateHUD {
    if (!KSBallIsHUDProcess()) {
        pid_t processIdentifier = (pid_t)[NSUserDefaults.standardUserDefaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
        if (processIdentifier > 0) {
            kill(processIdentifier, SIGTERM);
        }
        [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
        self.frontBoardStatusDescription = @"HUD 子进程已停止。";
        return;
    }

    self.hudWindow.hidden = YES;
    self.hudWindow.rootViewController = nil;
    self.hudWindow = nil;

    UISceneSession *session = self.hudSession;
    self.hudSession = nil;
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
    self.frontBoardStatusDescription = @"FrontBoard HUD 已显示。";
}

- (void)disconnectHUDSession:(UISceneSession *)session {
    if ([session.persistentIdentifier isEqualToString:self.hudSession.persistentIdentifier]) {
        self.hudWindow = nil;
        self.hudSession = nil;
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

    id definition = [self objectFromClass:definitionClass selector:@"definition" argument:nil];
    id identity = [self objectFromClass:identityClass selector:@"identityForIdentifier:" argument:KSBallHUDSceneIdentifier];
    id clientIdentity = [self objectFromClass:clientIdentityClass selector:@"localIdentity" argument:nil];
    [self sendObject:identity toObject:definition selector:@"setIdentity:"];
    [self sendObject:clientIdentity toObject:definition selector:@"setClientIdentity:"];

    Class specificationClass = NSClassFromString(@"UIApplicationSceneSpecification");
    id specification = [self objectFromClass:specificationClass selector:@"specification" argument:nil];
    id parameters = [self objectFromClass:parametersClass selector:@"parametersForSpecification:" argument:specification];
    [self sendObject:specification toObject:definition selector:@"setSpecification:"];
    if (!definition || !identity || !clientIdentity || !specification || !parameters) {
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
    if (!self.presentationBinder) {
        self.frontBoardStatusDescription = @"无法创建 FrontBoard HUD 展示绑定器。";
        return NO;
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
        @"FBSMutableSceneDefinition", @"FBSSceneIdentity", @"FBSSceneClientIdentity", @"UIApplicationSceneSpecification",
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

- (void)bootstrapHUDProcessIfNeeded {
    if (!KSBallIsHUDProcess()) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.frontBoardStatusDescription = @"HUD 子进程正在初始化 FrontBoard。";
    self.frontBoardReady = YES;
    BOOL initialized = KSBallPrepareFrontBoardSystemShellWithBlock(^{
        [weakSelf createFrontBoardHUDScene];
    });
    self.frontBoardReady = initialized;
    if (!initialized) {
        self.frontBoardStatusDescription = @"无法初始化 FrontBoard 系统壳。请确认 TrollStore 权限。";
    }
}

- (BOOL)spawnHUDProcess {
    NSString *executablePath = NSBundle.mainBundle.executablePath;
    if (executablePath.length == 0) {
        self.frontBoardStatusDescription = @"无法定位 HUD 子进程可执行文件。";
        return NO;
    }

    const char *executable = executablePath.fileSystemRepresentation;
    char *arguments[] = { (char *)executable, (char *)KSBallHUDProcessArgument, NULL };
    posix_spawnattr_t attributes;
    int result = posix_spawnattr_init(&attributes);
    if (result != 0) {
        self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程属性初始化失败：%s", strerror(result)];
        return NO;
    }
    BOOL attributesInitialized = YES;

    KSBallSetPersonaFunction setPersona = (KSBallSetPersonaFunction)dlsym(RTLD_DEFAULT, "posix_spawnattr_set_persona_np");
    KSBallSetPersonaUIDFunction setPersonaUID = (KSBallSetPersonaUIDFunction)dlsym(RTLD_DEFAULT, "posix_spawnattr_set_persona_uid_np");
    KSBallSetPersonaGIDFunction setPersonaGID = (KSBallSetPersonaGIDFunction)dlsym(RTLD_DEFAULT, "posix_spawnattr_set_persona_gid_np");
    BOOL usingPersona = NO;
    BOOL usedNormalFallback = NO;
    NSString *personaFailure = nil;

    // persona 是可选优化。缺少权限时会返回 EPERM，不能阻断普通子进程启动。
    if (setPersona && setPersonaUID && setPersonaGID) {
        result = setPersona(&attributes, KSBallApplicationPersonaIdentifier, KSBallApplicationPersonaFlags);
        if (result == 0) {
            result = setPersonaUID(&attributes, 0);
        }
        if (result == 0) {
            result = setPersonaGID(&attributes, 0);
        }
        if (result == 0) {
            usingPersona = YES;
        } else {
            personaFailure = [NSString stringWithUTF8String:strerror(result)];
            posix_spawnattr_destroy(&attributes);
            attributesInitialized = NO;
            result = posix_spawnattr_init(&attributes);
            if (result == 0) {
                attributesInitialized = YES;
                usedNormalFallback = YES;
            }
        }
    } else {
        personaFailure = @"persona 接口不可用";
        usedNormalFallback = YES;
    }

    if (result == 0) {
        result = KSBallConfigureBasicSpawnAttributes(&attributes);
    }
    if (result != 0) {
        if (attributesInitialized) {
            posix_spawnattr_destroy(&attributes);
        }
        if (personaFailure.length > 0) {
            self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD persona 属性失败（%@）；普通回退属性初始化失败：%s", personaFailure, strerror(result)];
        } else {
            self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程属性初始化失败：%s", strerror(result)];
        }
        return NO;
    }

    pid_t processIdentifier = 0;
    result = posix_spawn(&processIdentifier, executable, NULL, &attributes, arguments, environ);
    posix_spawnattr_destroy(&attributes);

    // 某些系统允许设置 persona 属性，但在真正 spawn 时才因权限返回 EPERM。
    if (result == EPERM && usingPersona) {
        personaFailure = @"Operation not permitted";
        usingPersona = NO;
        usedNormalFallback = YES;
        int fallbackInitializationResult = posix_spawnattr_init(&attributes);
        BOOL fallbackAttributesInitialized = fallbackInitializationResult == 0;
        result = fallbackInitializationResult;
        if (result == 0) {
            result = KSBallConfigureBasicSpawnAttributes(&attributes);
        }
        if (result == 0) {
            result = posix_spawn(&processIdentifier, executable, NULL, &attributes, arguments, environ);
        }
        if (fallbackAttributesInitialized) {
            posix_spawnattr_destroy(&attributes);
        }
    }

    if (result != 0) {
        if (personaFailure.length > 0) {
            self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程启动失败：persona %@；普通回退：%s", personaFailure, strerror(result)];
        } else {
            self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程启动失败：%s", strerror(result)];
        }
        return NO;
    }

    [NSUserDefaults.standardUserDefaults setInteger:processIdentifier forKey:KSBallHUDProcessIdentifierDefaultsKey];
    if (usedNormalFallback && personaFailure.length > 0) {
        self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程已启动（PID %d，普通模式；persona 不可用：%@）。", processIdentifier, personaFailure];
    } else if (usingPersona) {
        self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程已启动（PID %d，persona）。", processIdentifier];
    } else {
        self.frontBoardStatusDescription = [NSString stringWithFormat:@"HUD 子进程已启动（PID %d）。", processIdentifier];
    }
    return YES;
}

- (BOOL)hasLiveHUDProcess {
    pid_t processIdentifier = (pid_t)[NSUserDefaults.standardUserDefaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
    if (processIdentifier <= 0) {
        return NO;
    }
    if (kill(processIdentifier, 0) == 0 || errno == EPERM) {
        return YES;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
    return NO;
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
