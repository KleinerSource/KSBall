#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import "HUDTouchEventBridge.h"
#import "FloatingHUDViewController.h"
#import "PassthroughHUDWindow.h"
#import <dlfcn.h>
#import <errno.h>
#import <objc/message.h>
#import <signal.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/wait.h>
#import <unistd.h>

static const char * const KSBallHUDProcessArgument = "-hud";
static NSString * const KSBallHUDProcessIdentifierDefaultsKey = @"KSBallHUDProcessIdentifier";
static NSString * const KSBallHUDReadyProcessIdentifierDefaultsKey = @"KSBallHUDReadyProcessIdentifier";
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

static void *KSBallLookupSymbol(void *frameworkHandle, const char *symbolName) {
    void *symbol = dlsym(RTLD_DEFAULT, symbolName);
    return symbol ?: (frameworkHandle ? dlsym(frameworkHandle, symbolName) : NULL);
}

BOOL KSBallPrepareFrontBoardSystemShell(void) {
    static dispatch_once_t onceToken;
    static BOOL ready;
    dispatch_once(&onceToken, ^{
        void *frontBoardServices = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_GLOBAL);
        dlopen("/System/Library/PrivateFrameworks/FrontBoardHUD.framework/FrontBoardHUD", RTLD_LAZY | RTLD_GLOBAL);
        typedef void (*FBSystemShellInitializeFunction)(dispatch_block_t);
        FBSystemShellInitializeFunction initializer = (FBSystemShellInitializeFunction)dlsym(frontBoardServices, "FBSystemShellInitialize");
        if (frontBoardServices && initializer) {
            initializer(nil);
            ready = YES;
        }
    });
    return ready;
}

BOOL KSBallIsHUDProcess(void) {
    NSString *argument = [NSString stringWithUTF8String:KSBallHUDProcessArgument];
    return [NSProcessInfo.processInfo.arguments containsObject:argument];
}

@interface KSBallHUDApplication : UIApplication
@end

@implementation KSBallHUDApplication
@end

int KSBallRunHUDProcess(void) {
    void *graphicsServices = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_GLOBAL);
    void *backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    void *springBoardServices = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_GLOBAL);

    typedef void (*KSBallInitializeFunction)(void);
    typedef void (*KSBallInstantiateApplicationFunction)(id);
    KSBallInitializeFunction initializeGraphics = (KSBallInitializeFunction)KSBallLookupSymbol(graphicsServices, "GSInitialize");
    KSBallInitializeFunction startDisplayServices = (KSBallInitializeFunction)KSBallLookupSymbol(backBoardServices, "BKSDisplayServicesStart");
    KSBallInitializeFunction initializeApplication = (KSBallInitializeFunction)KSBallLookupSymbol(backBoardServices, "UIApplicationInitialize");
    KSBallInstantiateApplicationFunction instantiateApplication = (KSBallInstantiateApplicationFunction)KSBallLookupSymbol(backBoardServices, "UIApplicationInstantiateSingleton");
    if (!graphicsServices || !backBoardServices || !springBoardServices || !initializeGraphics || !startDisplayServices || !initializeApplication || !instantiateApplication) {
        NSLog(@"KSBall HUD plugin initialization symbols are unavailable.");
        return EXIT_FAILURE;
    }

    initializeGraphics();
    startDisplayServices();
    initializeApplication();
    instantiateApplication(KSBallHUDApplication.class);

    HUDSceneCoordinator *coordinator = HUDSceneCoordinator.sharedCoordinator;
    UIApplication *application = UIApplication.sharedApplication;
    application.delegate = (id<UIApplicationDelegate>)coordinator;
    SEL accessibilityInitSelector = NSSelectorFromString(@"_accessibilityInit");
    if ([application respondsToSelector:accessibilityInitSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(application, accessibilityInitSelector);
    }
    [NSRunLoop currentRunLoop];
    if (!KSBallRegisterHUDEventCallback()) {
        NSLog(@"KSBall HUD touch event callback registration failed.");
        return EXIT_FAILURE;
    }

    SEL completeAsPluginSelector = NSSelectorFromString(@"__completeAndRunAsPlugin");
    if (![application respondsToSelector:completeAsPluginSelector]) {
        NSLog(@"KSBall HUD plugin entry point is unavailable.");
        return EXIT_FAILURE;
    }
    ((void (*)(id, SEL))objc_msgSend)(application, completeAsPluginSelector);
    CFRunLoopRun();
    return EXIT_SUCCESS;
}

@interface HUDSceneCoordinator () <UIApplicationDelegate>
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong, nullable) UIWindow *hudWindow;
@property (nonatomic, strong, nullable) UIWindow *hudBootstrapWindow;
@property (nonatomic, strong, nullable) UISceneSession *hudSession;
@property (nonatomic, strong, nullable) id frontBoardHUDScene;
@property (nonatomic, strong, nullable) id presentationBinder;
@property (nonatomic, strong, nullable) id accessibilityWindowHostingController;
@property (nonatomic, strong, nullable) dispatch_source_t terminationSignalSource;
@property (nonatomic, copy, nullable) dispatch_block_t hudProcessStopCompletion;
@property (nonatomic) unsigned int accessibilityWindowContextIdentifier;
@property (nonatomic) BOOL accessibilityWindowRegistered;
@property (nonatomic) BOOL hudProcessStopping;
@property (nonatomic) BOOL frontBoardReady;
@property (nonatomic) BOOL ownsFrontBoardHUDScene;
@property (nonatomic, copy) NSString *frontBoardStatusDescription;

- (BOOL)createFrontBoardHUDSceneForWindowScene:(UIWindowScene *)windowScene;
- (void)configureHUDWindow:(UIWindow *)window windowLevel:(CGFloat)windowLevel;
- (BOOL)registerHUDWindowWithAccessibilityHost:(UIWindow *)window;
- (void)unregisterHUDWindowFromAccessibilityHost;
- (void)stopHUDProcessWithCompletion:(nullable dispatch_block_t)completion;
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

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    if (!KSBallIsHUDProcess()) {
        return YES;
    }

    signal(SIGTERM, SIG_IGN);
    dispatch_source_t terminationSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    if (terminationSource) {
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(terminationSource, ^{
            [weakSelf deactivateHUD];
            exit(EXIT_SUCCESS);
        });
        dispatch_resume(terminationSource);
        self.terminationSignalSource = terminationSource;
    } else {
        signal(SIGTERM, SIG_DFL);
    }

    UIWindow *window = [[PassthroughHUDWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self configureHUDWindow:window windowLevel:10000010.0];
    if (![self registerHUDWindowWithAccessibilityHost:window]) {
        NSLog(@"KSBall HUD window registration failed: %@", self.frontBoardStatusDescription);
        return NO;
    }
    self.hudBootstrapWindow = window;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:getpid() forKey:KSBallHUDReadyProcessIdentifierDefaultsKey];
    [defaults synchronize];
    self.frontBoardStatusDescription = @"HUD 窗口已注册到 SpringBoard。";
    return YES;
}

- (BOOL)isHUDActive {
    if (KSBallIsHUDProcess()) {
        return self.hudWindow != nil && !self.hudWindow.hidden && self.accessibilityWindowHostingController != nil;
    }
    if (![self hasLiveHUDProcess]) {
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    pid_t processIdentifier = (pid_t)[defaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
    BOOL ready = [defaults integerForKey:KSBallHUDReadyProcessIdentifierDefaultsKey] == processIdentifier;
    if (ready) {
        self.frontBoardStatusDescription = @"HUD 窗口已注册到 SpringBoard。";
    } else {
        self.frontBoardStatusDescription = @"HUD 子进程已启动，正在注册 SpringBoard 窗口。";
    }
    return ready;
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

    if (self.hudProcessStopping) {
        __weak typeof(self) weakSelf = self;
        self.hudProcessStopCompletion = ^{
            if (weakSelf.settingsStore.settings.enabled) {
                [weakSelf activateHUD];
            }
        };
        return;
    }

    if ([self hasLiveHUDProcess]) {
        self.frontBoardStatusDescription = @"HUD 子进程已在运行。";
        return;
    }
    [self spawnHUDProcess];
}

- (void)rebuildHUD {
    if (KSBallIsHUDProcess()) {
        [self activateHUD];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self stopHUDProcessWithCompletion:^{
        if (weakSelf.settingsStore.settings.enabled) {
            [weakSelf activateHUD];
        }
    }];
}

- (void)deactivateHUD {
    if (!KSBallIsHUDProcess()) {
        [self stopHUDProcessWithCompletion:nil];
        return;
    }

    [self unregisterHUDWindowFromAccessibilityHost];
    UIWindow *sceneWindow = self.hudWindow;
    UIWindow *bootstrapWindow = self.hudBootstrapWindow;
    sceneWindow.hidden = YES;
    sceneWindow.rootViewController = nil;
    if (bootstrapWindow != sceneWindow) {
        bootstrapWindow.hidden = YES;
        bootstrapWindow.rootViewController = nil;
    }
    self.hudWindow = nil;
    self.hudBootstrapWindow = nil;

    UISceneSession *session = self.hudSession;
    self.hudSession = nil;
    if (session) {
        [[UIApplication sharedApplication] requestSceneSessionDestruction:session options:nil errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"KSBall HUD scene destruction failed: %@", error.localizedDescription);
        }];
    }

    [self destroyFrontBoardHUDScene];
}

- (void)stopHUDProcessWithCompletion:(nullable dispatch_block_t)completion {
    if (self.hudProcessStopping) {
        self.hudProcessStopCompletion = completion;
        return;
    }

    pid_t processIdentifier = (pid_t)[NSUserDefaults.standardUserDefaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
    if (processIdentifier <= 0 || ![self hasLiveHUDProcess]) {
        self.frontBoardStatusDescription = @"HUD 子进程已停止。";
        if (completion) {
            completion();
        }
        return;
    }

    self.hudProcessStopping = YES;
    self.hudProcessStopCompletion = completion;
    kill(processIdentifier, SIGTERM);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int processStatus = 0;
        BOOL stopped = NO;
        for (NSUInteger attempt = 0; attempt < 75; attempt++) {
            if (waitpid(processIdentifier, &processStatus, WNOHANG) == processIdentifier) {
                stopped = YES;
                break;
            }
            if (kill(processIdentifier, 0) != 0 && errno == ESRCH) {
                stopped = YES;
                break;
            }
            usleep(20000);
        }

        if (!stopped) {
            kill(processIdentifier, SIGKILL);
            for (NSUInteger attempt = 0; attempt < 50; attempt++) {
                if (waitpid(processIdentifier, &processStatus, WNOHANG) == processIdentifier ||
                    (kill(processIdentifier, 0) != 0 && errno == ESRCH)) {
                    stopped = YES;
                    break;
                }
                usleep(20000);
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            if (stopped && [defaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey] == processIdentifier) {
                [defaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
                [defaults removeObjectForKey:KSBallHUDReadyProcessIdentifierDefaultsKey];
                [defaults synchronize];
            }
            self.hudProcessStopping = NO;
            dispatch_block_t stopCompletion = self.hudProcessStopCompletion;
            self.hudProcessStopCompletion = nil;
            self.frontBoardStatusDescription = stopped ? @"HUD 子进程已停止。" : @"HUD 子进程未能退出，已阻止重复启动。";
            if (stopped && stopCompletion) {
                stopCompletion();
            }
        });
    });
}

- (void)connectHUDWindow:(UIWindow *)window session:(UISceneSession *)session {
    self.hudWindow = window;
    self.hudSession = session;
    BOOL frontBoardSceneReady = YES;
    if (KSBallIsHUDProcess()) {
        self.frontBoardReady = KSBallPrepareFrontBoardSystemShell();
        frontBoardSceneReady = self.frontBoardReady && [self createFrontBoardHUDSceneForWindowScene:window.windowScene];
    }
    [self configureHUDWindow:window windowLevel:UIWindowLevelAlert + 2.0];
    if (window.hidden) {
        self.frontBoardStatusDescription = @"HUD 场景已连接，但当前已停用。";
        return;
    }
    if (frontBoardSceneReady) {
        self.frontBoardStatusDescription = @"FrontBoard HUD 已显示。";
    }
}

- (void)configureHUDWindow:(UIWindow *)window windowLevel:(CGFloat)windowLevel {
    self.hudWindow = window;
    FloatingHUDViewController *controller = [[FloatingHUDViewController alloc] initWithSettingsStore:self.settingsStore applicationBridge:self.applicationBridge];
    __weak typeof(self) weakSelf = self;
    controller.openConfigurationHandler = ^{
        [weakSelf openConfiguration];
    };
    window.rootViewController = controller;
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = windowLevel;
    [window makeKeyAndVisible];
    window.hidden = !self.settingsStore.settings.enabled;
}

- (BOOL)registerHUDWindowWithAccessibilityHost:(UIWindow *)window {
    SEL contextIdentifierSelector = NSSelectorFromString(@"_contextId");
    SEL registerWindowSelector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    Class hostingControllerClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    if (!hostingControllerClass || ![window respondsToSelector:contextIdentifierSelector]) {
        self.frontBoardStatusDescription = @"SpringBoard accessibility window host 不可用。";
        return NO;
    }

    [self unregisterHUDWindowFromAccessibilityHost];
    id hostingController = [hostingControllerClass new];
    if (![hostingController respondsToSelector:registerWindowSelector]) {
        self.frontBoardStatusDescription = @"SpringBoard accessibility window host 缺少注册接口。";
        return NO;
    }

    unsigned int contextIdentifier = ((unsigned int (*)(id, SEL))objc_msgSend)(window, contextIdentifierSelector);
    ((void (*)(id, SEL, unsigned int, double))objc_msgSend)(hostingController, registerWindowSelector, contextIdentifier, (double)window.windowLevel);
    self.accessibilityWindowHostingController = hostingController;
    self.accessibilityWindowContextIdentifier = contextIdentifier;
    self.accessibilityWindowRegistered = YES;
    return YES;
}

- (void)unregisterHUDWindowFromAccessibilityHost {
    id hostingController = self.accessibilityWindowHostingController;
    SEL unregisterWindowSelector = NSSelectorFromString(@"unregisterWindowWithContextID:");
    if (self.accessibilityWindowRegistered && [hostingController respondsToSelector:unregisterWindowSelector]) {
        ((void (*)(id, SEL, unsigned int))objc_msgSend)(hostingController, unregisterWindowSelector, self.accessibilityWindowContextIdentifier);
    }
    self.accessibilityWindowHostingController = nil;
    self.accessibilityWindowContextIdentifier = 0;
    self.accessibilityWindowRegistered = NO;
}

- (void)disconnectHUDSession:(UISceneSession *)session {
    if ([session.persistentIdentifier isEqualToString:self.hudSession.persistentIdentifier]) {
        [self unregisterHUDWindowFromAccessibilityHost];
        UIWindow *sceneWindow = self.hudWindow;
        UIWindow *bootstrapWindow = self.hudBootstrapWindow;
        sceneWindow.hidden = YES;
        sceneWindow.rootViewController = nil;
        if (bootstrapWindow != sceneWindow) {
            bootstrapWindow.hidden = YES;
            bootstrapWindow.rootViewController = nil;
        }
        self.hudWindow = nil;
        self.hudBootstrapWindow = nil;
        self.hudSession = nil;
        [self destroyFrontBoardHUDScene];
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

- (BOOL)createFrontBoardHUDSceneForWindowScene:(UIWindowScene *)windowScene {
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
    Class managerClass = NSClassFromString(@"FBSceneManager");
    Class binderClass = NSClassFromString(@"UIRootWindowScenePresentationBinder");

    id definition = [self objectFromClass:definitionClass selector:@"definition" argument:nil];
    id identity = [self objectFromClass:identityClass selector:@"identityForIdentifier:" argument:NSBundle.mainBundle.bundleIdentifier];
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

    id effectiveSettings = [self objectFromObject:windowScene selector:@"_effectiveSettings" argument:nil];
    id settings = [effectiveSettings mutableCopy];
    if (!settings) {
        self.frontBoardStatusDescription = @"无法读取 HUD 场景的有效设置。";
        return NO;
    }
    [self sendInteger:YES toObject:settings selector:@"setForeground:"];
    [self sendInteger:0 toObject:settings selector:@"setDeactivationReasons:"];
    [self sendInteger:0 toObject:settings selector:@"setInterruptionPolicy:"];
    id displayConfiguration = [self objectFromObject:settings selector:@"displayConfiguration" argument:nil];
    [self sendObject:settings toObject:parameters selector:@"setSettings:"];

    id clientSettings = [self objectFromObject:windowScene selector:@"_effectiveUIClientSettings" argument:nil];
    if (!clientSettings) {
        self.frontBoardStatusDescription = @"无法读取 HUD 场景的客户端设置。";
        return NO;
    }
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
    self.frontBoardStatusDescription = @"FrontBoard HUD 场景已绑定到 UIKit 窗口。";
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

    self.frontBoardStatusDescription = @"HUD 子进程正在初始化 FrontBoard。";
    self.frontBoardReady = KSBallPrepareFrontBoardSystemShell();
    if (!self.frontBoardReady) {
        self.frontBoardStatusDescription = @"无法初始化 FrontBoard 系统壳。请确认 TrollStore 权限。";
    } else {
        self.frontBoardStatusDescription = @"FrontBoard 已就绪，等待 HUD 窗口连接。";
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
    [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDReadyProcessIdentifierDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
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
    [NSUserDefaults.standardUserDefaults synchronize];
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
    int processStatus = 0;
    if (waitpid(processIdentifier, &processStatus, WNOHANG) == processIdentifier) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDReadyProcessIdentifierDefaultsKey];
        [NSUserDefaults.standardUserDefaults synchronize];
        return NO;
    }
    if (kill(processIdentifier, 0) == 0 || errno == EPERM) {
        return YES;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDReadyProcessIdentifierDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
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

@end
