#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "KSBallSharedStorage.h"
#import "SystemApplicationBridge.h"
#import "HUDTouchEventBridge.h"
#import "FloatingHUDViewController.h"
#import "PassthroughHUDWindow.h"
#import <dlfcn.h>
#import <errno.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>
#import <spawn.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/wait.h>
#import <unistd.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

static const char * const KSBallHUDProcessArgument = "-hud";
static const char * const KSBallStopProcessArgument = "-stop-hud";
static NSString * const KSBallHUDProcessIdentifierDefaultsKey = @"KSBallHUDProcessIdentifier";
static NSString * const KSBallHUDReadyProcessIdentifierStorageKey = @"HUDReadyProcessIdentifier";
static NSString * const KSBallHUDStatusDescriptionStorageKey = @"HUDStatusDescription";
static NSString * const KSBallFloatingHostStatusStorageKey = @"FloatingHostStatus";
static const uid_t KSBallApplicationPersonaIdentifier = 99;
static const uint32_t KSBallApplicationPersonaFlags = 1;
static const short KSBallApplicationSpawnFlags = 2;
static const CGFloat KSBallHUDWindowLevel = 10000010.0;
// 留在应用和系统键盘上方，同时让系统键盘可以盖过 HUD。
static const CGFloat KSBallGlobalKeyboardHUDWindowLevel = 10000.0;

static CGFloat KSBallHUDWindowLevelForKeyboardMode(KSBallKeyboardPresentationMode mode) {
    return mode == KSBallKeyboardPresentationModeGlobal ? KSBallGlobalKeyboardHUDWindowLevel : KSBallHUDWindowLevel;
}

extern char **environ;

typedef int (*KSBallSetPersonaFunction)(const posix_spawnattr_t *attributes, uid_t personaIdentifier, uint32_t flags);
typedef int (*KSBallSetPersonaUIDFunction)(const posix_spawnattr_t *attributes, uid_t userIdentifier);
typedef int (*KSBallSetPersonaGIDFunction)(const posix_spawnattr_t *attributes, gid_t groupIdentifier);
typedef void (*KSBallInstallEventRunLoopSourcesFunction)(id dispatcher, SEL selector, CFRunLoopRef runLoop);

static int KSBallConfigureBasicSpawnAttributes(posix_spawnattr_t *attributes) {
    int result = posix_spawnattr_setpgroup(attributes, 0);
    if (result != 0) {
        return result;
    }
    return posix_spawnattr_setflags(attributes, KSBallApplicationSpawnFlags);
}

// 统一封装 posix_spawn：优先以 root persona 启动（可选优化），缺少权限时回退为普通子进程。
static int KSBallPosixSpawnExecutable(const char *executable, char *arguments[], pid_t *processIdentifier, BOOL *outUsingPersona, BOOL *outUsedNormalFallback, NSString **outPersonaFailure) {
    posix_spawnattr_t attributes;
    int result = posix_spawnattr_init(&attributes);
    if (result != 0) {
        return result;
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
        if (outPersonaFailure) {
            *outPersonaFailure = personaFailure;
        }
        return result;
    }

    result = posix_spawn(processIdentifier, executable, NULL, &attributes, arguments, environ);
    posix_spawnattr_destroy(&attributes);

    // 某些系统允许设置 persona 属性，但在真正 spawn 时才因权限返回 EPERM。
    if (result == EPERM && usingPersona) {
        personaFailure = @"Operation not permitted";
        usingPersona = NO;
        usedNormalFallback = YES;
        result = posix_spawnattr_init(&attributes);
        if (result == 0) {
            result = KSBallConfigureBasicSpawnAttributes(&attributes);
            if (result == 0) {
                result = posix_spawn(processIdentifier, executable, NULL, &attributes, arguments, environ);
            }
            posix_spawnattr_destroy(&attributes);
        }
    }

    if (outUsingPersona) {
        *outUsingPersona = usingPersona;
    }
    if (outUsedNormalFallback) {
        *outUsedNormalFallback = usedNormalFallback;
    }
    if (outPersonaFailure) {
        *outPersonaFailure = personaFailure;
    }
    return result;
}

BOOL KSBallIsHUDProcess(void) {
    NSString *argument = [NSString stringWithUTF8String:KSBallHUDProcessArgument];
    return [NSProcessInfo.processInfo.arguments containsObject:argument];
}

#pragma mark - 悬浮分屏宿主

static BOOL KSBallFloatingAppHostingReady;

BOOL KSBallFloatingAppHostingAvailable(void) {
    return KSBallFloatingAppHostingReady;
}

static void KSBallSetFloatingHostStatus(NSString *status) {
    NSData *statusData = [status dataUsingEncoding:NSUTF8StringEncoding];
    if (statusData) {
        [KSBallSharedStorage setData:statusData forKey:KSBallFloatingHostStatusStorageKey];
    }
}

// 让 HUD 进程像 FrontBoardAppLauncher 那样成为 FrontBoard 场景宿主，才能托管其它应用的场景。
// 必须在 UIKit 初始化之前调用；只在有应用设为悬浮窗打开时执行，其余情况 HUD 的启动路径保持不变。
static void KSBallInitializeFloatingAppHosting(void) {
    if (!KSBallSettingsStore.sharedStore.settings.shouldEnableFloatingAppHosting) {
        [KSBallSharedStorage removeDataForKey:KSBallFloatingHostStatusStorageKey];
        return;
    }
    void *frontBoard = dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/BoardServices.framework/BoardServices", RTLD_LAZY | RTLD_GLOBAL);

    typedef void (*KSBallSystemShellInitializeFunction)(id);
    KSBallSystemShellInitializeFunction initializeSystemShell = (KSBallSystemShellInitializeFunction)dlsym(frontBoard ?: RTLD_DEFAULT, "FBSystemShellInitialize");
    if (!initializeSystemShell) {
        KSBallSetFloatingHostStatus(@"悬浮分屏不可用：系统缺少 FBSystemShellInitialize。");
        return;
    }
    for (NSString *className in @[@"FBSceneManager", @"FBProcessManager", @"RBSProcessHandle", @"FBApplicationProcessLaunchTransaction"]) {
        if (!NSClassFromString(className)) {
            KSBallSetFloatingHostStatus([NSString stringWithFormat:@"悬浮分屏不可用：系统缺少 %@。", className]);
            return;
        }
    }
    initializeSystemShell(nil);
    KSBallFloatingAppHostingReady = YES;
    KSBallSetFloatingHostStatus(@"悬浮分屏宿主已就绪。");
}

#pragma mark - HUD 插件进程

static void *KSBallLookupSymbol(void *frameworkHandle, const char *symbolName) {
    void *symbol = dlsym(RTLD_DEFAULT, symbolName);
    return symbol ?: (frameworkHandle ? dlsym(frameworkHandle, symbolName) : NULL);
}

// 部分系统版本不再公开 -[UIEventDispatcher _installEventRunLoopSources:]，
// 需要从 -[UIApplication _run] 中找到对它的 BL 调用（与 TrollSpeed 相同的做法）。
static KSBallInstallEventRunLoopSourcesFunction KSBallFindInstallEventRunLoopSources(Class applicationClass) {
#if defined(__arm64__)
    IMP runImplementation = class_getMethodImplementation(applicationClass, NSSelectorFromString(@"_run"));
    if (!runImplementation) {
        return NULL;
    }
    void *runAddress = (void *)runImplementation;
#if __has_feature(ptrauth_calls)
    runAddress = ptrauth_strip(runAddress, ptrauth_key_function_pointer);
#endif
    const uint32_t *instructions = (const uint32_t *)runAddress;
    void *installAddress = NULL;
    for (NSUInteger index = 0; index < 0x140; index++) {
        // mov x2, x0; mov x0, x?
        if (instructions[index] != 0xaa0003e2 || (instructions[index + 1] & 0xff000000) != 0xaa000000) {
            continue;
        }
        // bl -[UIEventDispatcher _installEventRunLoopSources:]
        uint32_t branchInstruction = instructions[index + 2];
        if ((branchInstruction & 0xfc000000) != 0x94000000) {
            continue;
        }
        int32_t branchOffset = branchInstruction & 0x03ffffff;
        if (branchOffset & 0x02000000) {
            branchOffset |= (int32_t)0xfc000000;
        }
        branchOffset *= 4;
        const uint32_t *target = (const uint32_t *)((intptr_t)&instructions[index + 2] + branchOffset);
        // cbz x0, ...
        if ((*target & 0xff000000) != 0xb4000000) {
            continue;
        }
        installAddress = (void *)target;
    }
#if __has_feature(ptrauth_calls)
    if (installAddress) {
        installAddress = ptrauth_sign_unauthenticated(installAddress, ptrauth_key_function_pointer, 0);
    }
#endif
    return (KSBallInstallEventRunLoopSourcesFunction)installAddress;
#else
    return NULL;
#endif
}

// 插件模式下 UIKit 不会安装事件分发源，合成的触摸无法送达视图，必须手动接好 fetcher 与 dispatcher。
static void KSBallInstallHUDEventDispatcher(UIApplication *application) {
    @try {
        id dispatcher = [application valueForKey:@"eventDispatcher"];
        if (!dispatcher) {
            NSLog(@"KSBall HUD event dispatcher is unavailable.");
            return;
        }

        CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
        SEL installSelector = NSSelectorFromString(@"_installEventRunLoopSources:");
        if ([dispatcher respondsToSelector:installSelector]) {
            ((void (*)(id, SEL, CFRunLoopRef))objc_msgSend)(dispatcher, installSelector, mainRunLoop);
        } else {
            KSBallInstallEventRunLoopSourcesFunction install = KSBallFindInstallEventRunLoopSources(application.class);
            if (!install) {
                NSLog(@"KSBall HUD could not locate -[UIEventDispatcher _installEventRunLoopSources:].");
                return;
            }
            install(dispatcher, installSelector, mainRunLoop);
        }

        id fetcher = [[NSClassFromString(@"UIEventFetcher") alloc] init];
        if (!fetcher) {
            NSLog(@"KSBall HUD event fetcher is unavailable.");
            return;
        }
        [dispatcher setValue:fetcher forKey:@"eventFetcher"];
        SEL sinkSelector = NSSelectorFromString(@"setEventFetcherSink:");
        if ([fetcher respondsToSelector:sinkSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(fetcher, sinkSelector, dispatcher);
        } else {
            [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
        }
        [application setValue:fetcher forKey:@"eventFetcher"];
    } @catch (NSException *exception) {
        NSLog(@"KSBall HUD event dispatcher setup failed: %@", exception);
    }
}

@interface KSBallHUDApplication : UIApplication
@end

@implementation KSBallHUDApplication

- (instancetype)init {
    self = [super init];
    if (self) {
        KSBallInstallHUDEventDispatcher(self);
    }
    return self;
}

@end

@interface HUDSceneCoordinator ()
- (void)presentHUDWindow;
- (void)installTerminationHandler;
- (void)reattachHUDWindowAfterSpringBoardLaunch;
@end

@interface KSBallHUDApplicationDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@end

@implementation KSBallHUDApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [HUDSceneCoordinator.sharedCoordinator presentHUDWindow];
    return YES;
}

@end

int KSBallRunHUDProcess(void) {
    // FrontBoardAppLauncher 在 UIApplicationMain 之前初始化 system shell，这里同样放在所有 UIKit 初始化之前。
    KSBallInitializeFloatingAppHosting();

    void *graphicsServices = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_GLOBAL);
    void *backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_GLOBAL);

    typedef void (*KSBallInitializeFunction)(void);
    typedef void (*KSBallInstantiateApplicationFunction)(Class);
    KSBallInitializeFunction initializeGraphics = (KSBallInitializeFunction)KSBallLookupSymbol(graphicsServices, "GSInitialize");
    KSBallInitializeFunction startDisplayServices = (KSBallInitializeFunction)KSBallLookupSymbol(backBoardServices, "BKSDisplayServicesStart");
    KSBallInitializeFunction initializeApplication = (KSBallInitializeFunction)KSBallLookupSymbol(NULL, "UIApplicationInitialize");
    KSBallInstantiateApplicationFunction instantiateApplication = (KSBallInstantiateApplicationFunction)KSBallLookupSymbol(NULL, "UIApplicationInstantiateSingleton");
    if (!initializeGraphics || !startDisplayServices || !initializeApplication || !instantiateApplication) {
        NSLog(@"KSBall HUD plugin initialization symbols are unavailable.");
        return EXIT_FAILURE;
    }

    (void)[UIScreen class];
    CFRunLoopGetCurrent();

    initializeGraphics();
    startDisplayServices();
    initializeApplication();

    instantiateApplication(KSBallHUDApplication.class);
    static KSBallHUDApplicationDelegate *applicationDelegate;
    applicationDelegate = [KSBallHUDApplicationDelegate new];
    UIApplication *application = UIApplication.sharedApplication;
    application.delegate = applicationDelegate;
    SEL accessibilityInitSelector = NSSelectorFromString(@"_accessibilityInit");
    if ([application respondsToSelector:accessibilityInitSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(application, accessibilityInitSelector);
    }

    [NSRunLoop currentRunLoop];
    [HUDSceneCoordinator.sharedCoordinator installTerminationHandler];
    if (!KSBallRegisterHUDEventCallback()) {
        NSLog(@"KSBall HUD touch event callback registration failed.");
    }

    SEL completeAsPluginSelector = NSSelectorFromString(@"__completeAndRunAsPlugin");
    if (![application respondsToSelector:completeAsPluginSelector]) {
        NSLog(@"KSBall HUD plugin entry point is unavailable.");
        return EXIT_FAILURE;
    }
    ((void (*)(id, SEL))objc_msgSend)(application, completeAsPluginSelector);

    // SpringBoard 重启后 accessibility 窗口托管随之失效，但窗口渲染上下文由 backboardd 持有仍然有效，
    // 向新的 SpringBoard 重新注册即可恢复，无需主程序重新拉起（重启时主程序通常也被结束）。
    static int springBoardLaunchToken;
    notify_register_dispatch("SBSpringBoardDidLaunchNotification", &springBoardLaunchToken, dispatch_get_main_queue(), ^(int token) {
        [HUDSceneCoordinator.sharedCoordinator reattachHUDWindowAfterSpringBoardLaunch];
    });

    CFRunLoopRun();
    return EXIT_SUCCESS;
}

// root persona 停止进程入口：主程序以 mobile 运行，对 root 子进程直发信号会被 EPERM 拒绝，
// 由本进程代为投递 SIGTERM，超时后升级为 SIGKILL。
int KSBallStopHUDProcessMain(pid_t processIdentifier) {
    if (processIdentifier <= 0) {
        return EXIT_FAILURE;
    }
    if (kill(processIdentifier, 0) != 0 && errno == ESRCH) {
        return EXIT_SUCCESS;
    }
    kill(processIdentifier, SIGTERM);
    BOOL stopped = NO;
    for (NSUInteger attempt = 0; attempt < 30 && !stopped; attempt++) {
        stopped = kill(processIdentifier, 0) != 0 && errno == ESRCH;
        if (!stopped) {
            usleep(20000);
        }
    }
    if (!stopped) {
        kill(processIdentifier, SIGKILL);
        for (NSUInteger attempt = 0; attempt < 30 && !stopped; attempt++) {
            stopped = kill(processIdentifier, 0) != 0 && errno == ESRCH;
            if (!stopped) {
                usleep(20000);
            }
        }
    }
    return stopped ? EXIT_SUCCESS : EXIT_FAILURE;
}

#pragma mark - 协调器

@interface HUDSceneCoordinator ()
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong, nullable) UIWindow *hudWindow;
@property (nonatomic, strong, nullable) id accessibilityWindowHostingController;
@property (nonatomic, strong, nullable) dispatch_source_t terminationSignalSource;
@property (nonatomic, copy, nullable) dispatch_block_t hudProcessStopCompletion;
@property (nonatomic) unsigned int accessibilityWindowContextIdentifier;
@property (nonatomic) BOOL accessibilityWindowRegistered;
@property (nonatomic) BOOL hudProcessStopping;
/// HUD 子进程启动时是否应启用悬浮应用宿主；变化时需要重建 HUD 以初始化或撤销宿主。
@property (nonatomic) BOOL appliedFloatingAppHostingEnabled;
@property (nonatomic, copy) NSString *statusDescription;

- (BOOL)registerHUDWindowWithAccessibilityHost:(UIWindow *)window;
- (void)unregisterHUDWindowFromAccessibilityHost;
- (void)updateHUDWindowLevelForKeyboardPresentationMode;
- (void)stopHUDProcessWithCompletion:(nullable dispatch_block_t)completion;
- (void)rebuildHUD;
- (BOOL)spawnHUDProcess;
- (pid_t)spawnStopProcessForProcessIdentifier:(pid_t)processIdentifier;
- (BOOL)hasLiveHUDProcess;
@end

@implementation HUDSceneCoordinator

@synthesize statusDescription = _statusDescription;

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
        _statusDescription = @"尚未启动 HUD。";
        _appliedFloatingAppHostingEnabled = settingsStore.settings.shouldEnableFloatingAppHosting;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:KSBallSettingsDidChangeNotification object:settingsStore];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setStatusDescription:(NSString *)statusDescription {
    _statusDescription = [statusDescription copy];
    if (KSBallIsHUDProcess() && _statusDescription.length > 0) {
        NSData *statusData = [_statusDescription dataUsingEncoding:NSUTF8StringEncoding];
        [KSBallSharedStorage setData:statusData forKey:KSBallHUDStatusDescriptionStorageKey];
    }
}

- (void)installTerminationHandler {
    signal(SIGTERM, SIG_IGN);
    dispatch_source_t terminationSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    if (!terminationSource) {
        signal(SIGTERM, SIG_DFL);
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(terminationSource, ^{
        [weakSelf deactivateHUD];
        exit(EXIT_SUCCESS);
    });
    dispatch_resume(terminationSource);
    self.terminationSignalSource = terminationSource;
}

- (void)presentHUDWindow {
    if (self.hudWindow) {
        return;
    }
    // 启动期间开关可能已被关闭（子进程尚未注册 Darwin 通知），此时直接退出，避免误显示。
    if (!self.settingsStore.settings.enabled) {
        exit(EXIT_SUCCESS);
    }

    PassthroughHUDWindow *window = [[PassthroughHUDWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    FloatingHUDViewController *controller = [[FloatingHUDViewController alloc] initWithSettingsStore:self.settingsStore applicationBridge:self.applicationBridge];
    __weak typeof(self) weakSelf = self;
    controller.openConfigurationHandler = ^{
        [weakSelf openConfiguration];
    };
    window.rootViewController = controller;
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = KSBallHUDWindowLevelForKeyboardMode(self.settingsStore.settings.keyboardPresentationMode);
    window.hidden = NO;
    [window makeKeyAndVisible];
    self.hudWindow = window;

    if (![self registerHUDWindowWithAccessibilityHost:window]) {
        NSLog(@"KSBall HUD window registration failed: %@", self.statusDescription);
        return;
    }
    NSData *readyData = [[NSString stringWithFormat:@"%d", getpid()] dataUsingEncoding:NSUTF8StringEncoding];
    [KSBallSharedStorage setData:readyData forKey:KSBallHUDReadyProcessIdentifierStorageKey];
    self.statusDescription = @"HUD 窗口已注册到 SpringBoard。";
}

- (BOOL)isHUDActive {
    if (![self hasLiveHUDProcess]) {
        NSData *statusData = [KSBallSharedStorage dataForKey:KSBallHUDStatusDescriptionStorageKey];
        NSString *childStatus = [[NSString alloc] initWithData:statusData encoding:NSUTF8StringEncoding];
        self.statusDescription = childStatus.length > 0 ? [NSString stringWithFormat:@"HUD 子进程已退出；最后阶段：%@", childStatus] : @"HUD 子进程未运行。";
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    pid_t processIdentifier = (pid_t)[defaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
    NSData *readyData = [KSBallSharedStorage dataForKey:KSBallHUDReadyProcessIdentifierStorageKey];
    BOOL ready = (pid_t)[[[NSString alloc] initWithData:readyData encoding:NSUTF8StringEncoding] intValue] == processIdentifier;
    NSData *statusData = [KSBallSharedStorage dataForKey:KSBallHUDStatusDescriptionStorageKey];
    NSString *childStatus = [[NSString alloc] initWithData:statusData encoding:NSUTF8StringEncoding];
    if (childStatus.length > 0) {
        self.statusDescription = childStatus;
    } else if (ready) {
        self.statusDescription = @"HUD 窗口已注册到 SpringBoard。";
    } else {
        self.statusDescription = @"HUD 子进程已启动，正在注册 SpringBoard 窗口。";
    }
    return ready;
}

- (void)activateHUD {
    if (KSBallIsHUDProcess() || !self.settingsStore.settings.enabled) {
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
        self.statusDescription = @"HUD 子进程已在运行。";
        return;
    }
    [self spawnHUDProcess];
}

- (void)rebuildHUD {
    if (KSBallIsHUDProcess()) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self stopHUDProcessWithCompletion:^{
        if (weakSelf.settingsStore.settings.enabled) {
            [weakSelf activateHUD];
        }
    }];
}

// 旧的托管连接随 SpringBoard 一起失效，丢弃后重新注册；新 SpringBoard 的服务可能尚未就绪，失败时稍后重试。
- (void)reattachHUDWindowAfterSpringBoardLaunch {
    [self reattachHUDWindowWithRemainingAttempts:5];
}

- (void)reattachHUDWindowWithRemainingAttempts:(NSUInteger)remainingAttempts {
    UIWindow *window = self.hudWindow;
    if (!window || !self.settingsStore.settings.enabled) {
        return;
    }
    self.accessibilityWindowHostingController = nil;
    self.accessibilityWindowContextIdentifier = 0;
    self.accessibilityWindowRegistered = NO;
    if ([self registerHUDWindowWithAccessibilityHost:window]) {
        self.statusDescription = @"SpringBoard 重启后 HUD 窗口已重新注册。";
        return;
    }
    if (remainingAttempts <= 1) {
        NSLog(@"KSBall HUD window re-registration failed: %@", self.statusDescription);
        [self deactivateHUD];
        exit(EXIT_FAILURE);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf reattachHUDWindowWithRemainingAttempts:remainingAttempts - 1];
    });
}

- (void)deactivateHUD {
    if (!KSBallIsHUDProcess()) {
        [self stopHUDProcessWithCompletion:nil];
        return;
    }

    [self unregisterHUDWindowFromAccessibilityHost];
    UIWindow *window = self.hudWindow;
    [(FloatingHUDViewController *)window.rootViewController closeFloatingWindows];
    window.hidden = YES;
    window.rootViewController = nil;
    self.hudWindow = nil;
    [KSBallSharedStorage removeDataForKey:KSBallHUDReadyProcessIdentifierStorageKey];
    self.statusDescription = @"HUD 窗口已注销，子进程正在退出。";
}

- (void)stopHUDProcessWithCompletion:(nullable dispatch_block_t)completion {
    if (self.hudProcessStopping) {
        self.hudProcessStopCompletion = completion;
        return;
    }

    pid_t processIdentifier = (pid_t)[NSUserDefaults.standardUserDefaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
    if (processIdentifier <= 0 || ![self hasLiveHUDProcess]) {
        self.statusDescription = @"HUD 子进程已停止。";
        if (completion) {
            completion();
        }
        return;
    }

    self.hudProcessStopping = YES;
    self.hudProcessStopCompletion = completion;
    // 普通回退模式下直发即可；persona 模式下子进程是 root，主程序的信号会被 EPERM 拒绝，
    // 改由 root persona 停止进程代为投递。
    pid_t stopProcessIdentifier = -1;
    if (kill(processIdentifier, SIGTERM) != 0 && errno == EPERM) {
        stopProcessIdentifier = [self spawnStopProcessForProcessIdentifier:processIdentifier];
    }
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

        if (stopProcessIdentifier > 0) {
            int stopProcessStatus = 0;
            // 停止进程会在子进程退出或自身超时后结束，这里回收它避免遗留僵尸。
            while (waitpid(stopProcessIdentifier, &stopProcessStatus, 0) < 0 && errno == EINTR) {
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            if (stopped && [defaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey] == processIdentifier) {
                [defaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
                [KSBallSharedStorage removeDataForKey:KSBallHUDReadyProcessIdentifierStorageKey];
                [KSBallSharedStorage removeDataForKey:KSBallHUDStatusDescriptionStorageKey];
                [defaults synchronize];
            }
            self.hudProcessStopping = NO;
            dispatch_block_t stopCompletion = self.hudProcessStopCompletion;
            self.hudProcessStopCompletion = nil;
            self.statusDescription = stopped ? @"HUD 子进程已停止。" : @"HUD 子进程未能退出，已阻止重复启动。";
            if (stopped && stopCompletion) {
                stopCompletion();
            }
        });
    });
}

- (BOOL)registerHUDWindowWithAccessibilityHost:(UIWindow *)window {
    SEL contextIdentifierSelector = NSSelectorFromString(@"_contextId");
    SEL registerWindowSelector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    Class hostingControllerClass = NSClassFromString(@"SBSAccessibilityWindowHostingController");
    if (!hostingControllerClass || ![window respondsToSelector:contextIdentifierSelector]) {
        self.statusDescription = @"SpringBoard accessibility window host 不可用。";
        return NO;
    }

    [self unregisterHUDWindowFromAccessibilityHost];
    id hostingController = [hostingControllerClass new];
    if (![hostingController respondsToSelector:registerWindowSelector]) {
        self.statusDescription = @"SpringBoard accessibility window host 缺少注册接口。";
        return NO;
    }

    unsigned int contextIdentifier = ((unsigned int (*)(id, SEL))objc_msgSend)(window, contextIdentifierSelector);
    if (contextIdentifier == 0) {
        self.statusDescription = @"HUD 窗口没有可用的渲染上下文。";
        return NO;
    }
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

- (void)openConfiguration {
    [(FloatingHUDViewController *)self.hudWindow.rootViewController dismissMenuAnimated:YES];
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (![self.applicationBridge launchBundleIdentifier:bundleIdentifier]) {
        NSURL *url = [NSURL URLWithString:@"ksball://settings"];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)settingsDidChange:(NSNotification *)notification {
    if (KSBallIsHUDProcess()) {
        // persona 模式下子进程以 root 运行，主程序的 SIGTERM/SIGKILL 会因 EPERM 无法送达，
        // 关闭开关时由子进程监听共享设置变化并自行退出。
        if (!self.settingsStore.settings.enabled) {
            [self deactivateHUD];
            exit(EXIT_SUCCESS);
        }
        BOOL floatingAppHostingEnabled = self.settingsStore.settings.shouldEnableFloatingAppHosting;
        BOOL floatingHostChanged = floatingAppHostingEnabled != self.appliedFloatingAppHostingEnabled;
        self.appliedFloatingAppHostingEnabled = floatingAppHostingEnabled;
        if (floatingHostChanged) {
            [self deactivateHUD];
            exit(EXIT_SUCCESS);
        }
        [self updateHUDWindowLevelForKeyboardPresentationMode];
        return;
    }
    if (self.settingsStore.settings.enabled) {
        BOOL floatingWindowShortcuts = self.settingsStore.settings.shouldEnableFloatingAppHosting;
        BOOL floatingHostChanged = floatingWindowShortcuts != self.appliedFloatingAppHostingEnabled;
        self.appliedFloatingAppHostingEnabled = floatingWindowShortcuts;
        // 悬浮分屏宿主只能在 HUD 子进程启动时初始化，开关从无到有或从有到无都要重建一次。
        if (floatingHostChanged && [self hasLiveHUDProcess]) {
            [self rebuildHUD];
        } else {
            [self activateHUD];
        }
    } else {
        [self deactivateHUD];
    }
}

- (void)updateHUDWindowLevelForKeyboardPresentationMode {
    UIWindow *window = self.hudWindow;
    CGFloat desiredLevel = KSBallHUDWindowLevelForKeyboardMode(self.settingsStore.settings.keyboardPresentationMode);
    if (!window || fabs(window.windowLevel - desiredLevel) < 0.5) {
        return;
    }
    [self unregisterHUDWindowFromAccessibilityHost];
    window.windowLevel = desiredLevel;
    if (![self registerHUDWindowWithAccessibilityHost:window]) {
        NSLog(@"KSBall HUD window re-registration failed after keyboard presentation mode changed: %@", self.statusDescription);
    }
}

- (NSString *)floatingHostStatusDescription {
    if (!self.settingsStore.settings.floatingSplitEnabled) {
        return @"已关闭：快捷应用将全屏打开，悬浮分屏宿主不会启动。";
    }
    if (!self.settingsStore.settings.hasFloatingWindowShortcuts) {
        return @"未启用：在快捷应用右侧打开开关后，该应用会以悬浮窗打开。";
    }
    NSData *statusData = [KSBallSharedStorage dataForKey:KSBallFloatingHostStatusStorageKey];
    NSString *status = [[NSString alloc] initWithData:statusData encoding:NSUTF8StringEncoding];
    return status.length > 0 ? status : @"等待 HUD 子进程初始化悬浮分屏宿主。";
}

- (BOOL)spawnHUDProcess {
    NSString *executablePath = NSBundle.mainBundle.executablePath;
    if (executablePath.length == 0) {
        self.statusDescription = @"无法定位 HUD 子进程可执行文件。";
        return NO;
    }

    const char *executable = executablePath.fileSystemRepresentation;
    char *arguments[] = { (char *)executable, (char *)KSBallHUDProcessArgument, NULL };
    [KSBallSharedStorage removeDataForKey:KSBallHUDReadyProcessIdentifierStorageKey];
    [KSBallSharedStorage removeDataForKey:KSBallHUDStatusDescriptionStorageKey];

    pid_t processIdentifier = 0;
    BOOL usingPersona = NO;
    BOOL usedNormalFallback = NO;
    NSString *personaFailure = nil;
    int result = KSBallPosixSpawnExecutable(executable, arguments, &processIdentifier, &usingPersona, &usedNormalFallback, &personaFailure);
    if (result != 0) {
        if (personaFailure.length > 0) {
            self.statusDescription = [NSString stringWithFormat:@"HUD 子进程启动失败：persona %@；普通回退：%s", personaFailure, strerror(result)];
        } else {
            self.statusDescription = [NSString stringWithFormat:@"HUD 子进程启动失败：%s", strerror(result)];
        }
        return NO;
    }

    [NSUserDefaults.standardUserDefaults setInteger:processIdentifier forKey:KSBallHUDProcessIdentifierDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    if (usedNormalFallback && personaFailure.length > 0) {
        self.statusDescription = [NSString stringWithFormat:@"HUD 子进程已启动（PID %d，普通模式；persona 不可用：%@）。", processIdentifier, personaFailure];
    } else if (usingPersona) {
        self.statusDescription = [NSString stringWithFormat:@"HUD 子进程已启动（PID %d，persona）。", processIdentifier];
    } else {
        self.statusDescription = [NSString stringWithFormat:@"HUD 子进程已启动（PID %d）。", processIdentifier];
    }
    return YES;
}

// 以 root persona 重新执行自身作为停止进程，代主程序向 HUD 子进程投递信号。
- (pid_t)spawnStopProcessForProcessIdentifier:(pid_t)processIdentifier {
    NSString *executablePath = NSBundle.mainBundle.executablePath;
    if (executablePath.length == 0) {
        return -1;
    }
    const char *executable = executablePath.fileSystemRepresentation;
    char processIdentifierBuffer[16];
    snprintf(processIdentifierBuffer, sizeof(processIdentifierBuffer), "%d", processIdentifier);
    char *arguments[] = { (char *)executable, (char *)KSBallStopProcessArgument, processIdentifierBuffer, NULL };
    pid_t stopProcessIdentifier = 0;
    int result = KSBallPosixSpawnExecutable(executable, arguments, &stopProcessIdentifier, NULL, NULL, NULL);
    return result == 0 ? stopProcessIdentifier : -1;
}

- (BOOL)hasLiveHUDProcess {
    pid_t processIdentifier = (pid_t)[NSUserDefaults.standardUserDefaults integerForKey:KSBallHUDProcessIdentifierDefaultsKey];
    if (processIdentifier <= 0) {
        return NO;
    }
    int processStatus = 0;
    if (waitpid(processIdentifier, &processStatus, WNOHANG) == processIdentifier) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
        [KSBallSharedStorage removeDataForKey:KSBallHUDReadyProcessIdentifierStorageKey];
        [NSUserDefaults.standardUserDefaults synchronize];
        return NO;
    }
    if (kill(processIdentifier, 0) == 0 || errno == EPERM) {
        return YES;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:KSBallHUDProcessIdentifierDefaultsKey];
    [KSBallSharedStorage removeDataForKey:KSBallHUDReadyProcessIdentifierStorageKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    return NO;
}

@end
