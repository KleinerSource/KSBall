#import "FloatingAppSceneHost.h"
#import "KSBallFrontBoardPrivate.h"
#import <errno.h>
#import <signal.h>

static NSString * const KSBallFloatingScenePrefix = @"KSBall.floating";
// FrontBoard 的后台启动意图：进程启动后不会被 SpringBoard 拉到前台，只显示我们创建的场景。
static const long long KSBallFloatingLaunchIntentBackground = 4;
static const NSTimeInterval KSBallFloatingTerminationGracePeriod = 3.0;
static const NSUInteger KSBallFloatingPresentationAppearanceStyle = 2;

// HUD 可能以 mobile 身份运行，向其它用户的进程探测会得到 EPERM，这同样说明进程存在。
static BOOL KSBallProcessIsAlive(pid_t processIdentifier) {
    return kill(processIdentifier, 0) == 0 || errno == EPERM;
}

@interface FloatingAppSceneHost ()
@property (nonatomic, copy, readwrite) NSString *bundleIdentifier;
@property (nonatomic, strong, readwrite, nullable) UIView *presentationView;
@property (nonatomic, strong, nullable) _UIScenePresenter *presenter;
@property (nonatomic, strong, nullable) FBApplicationProcessLaunchTransaction *launchTransaction;
@property (nonatomic, copy, nullable) NSString *sceneIdentifier;
@property (nonatomic, strong, nullable) dispatch_source_t processExitSource;
@property (nonatomic) pid_t processIdentifier;
@property (nonatomic) BOOL launchedByHost;
@property (nonatomic) BOOL processExited;
@property (nonatomic) BOOL invalidated;
@end

@implementation FloatingAppSceneHost

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
    self = [super init];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _userInterfaceStyle = UIUserInterfaceStyleLight;
    }
    return self;
}

- (void)dealloc {
    if (_processExitSource) {
        dispatch_source_cancel(_processExitSource);
    }
}

#pragma mark - 启动

- (void)startWithCompletion:(KSBallFloatingSceneCompletion)completion {
    RBSProcessHandle *handle = [self runningProcessHandle];
    if (handle) {
        self.launchedByHost = NO;
        [self finishStartWithProcessHandle:handle completion:completion];
        return;
    }

    RBSProcessIdentity *identity = [self processIdentity];
    Class transactionClass = KSBallPrivateClass(FBApplicationProcessLaunchTransaction);
    FBProcessManager *processManager = [KSBallPrivateClass(FBProcessManager) sharedInstance];
    if (!identity || !transactionClass || !processManager) {
        completion(NO, @"系统缺少 FrontBoard 启动接口");
        return;
    }

    FBApplicationProcessLaunchTransaction *transaction = nil;
    @try {
        transaction = [[transactionClass alloc] initWithProcessIdentity:identity executionContextProvider:^id{
            FBMutableProcessExecutionContext *context = [KSBallPrivateClass(FBMutableProcessExecutionContext) new];
            context.identity = identity;
            context.environment = @{};
            context.launchIntent = KSBallFloatingLaunchIntentBackground;
            return [processManager launchProcessWithContext:context];
        }];
    } @catch (NSException *exception) {
        completion(NO, [NSString stringWithFormat:@"无法创建启动任务：%@", exception.reason]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [transaction setCompletionBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.invalidated) {
                return;
            }
            strongSelf.launchTransaction = nil;
            RBSProcessHandle *launchedHandle = [strongSelf runningProcessHandle];
            if (!launchedHandle) {
                completion(NO, @"应用进程未能启动");
                return;
            }
            strongSelf.launchedByHost = YES;
            [strongSelf finishStartWithProcessHandle:launchedHandle completion:completion];
        });
    }];
    self.launchTransaction = transaction;
    [transaction begin];
}

- (void)finishStartWithProcessHandle:(RBSProcessHandle *)handle completion:(KSBallFloatingSceneCompletion)completion {
    NSString *failureReason = nil;
    if (![self createSceneForProcessHandle:handle failureReason:&failureReason]) {
        completion(NO, failureReason);
        return;
    }
    [self monitorProcessExit];
    completion(YES, nil);
}

- (nullable RBSProcessIdentity *)processIdentity {
    return [KSBallPrivateClass(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:self.bundleIdentifier];
}

- (nullable RBSProcessHandle *)runningProcessHandle {
    RBSProcessIdentity *identity = [self processIdentity];
    Class predicateClass = KSBallPrivateClass(RBSProcessPredicate);
    Class handleClass = KSBallPrivateClass(RBSProcessHandle);
    if (!identity || !predicateClass || !handleClass) {
        return nil;
    }
    RBSProcessPredicate *predicate = [predicateClass predicateMatchingIdentity:identity];
    RBSProcessHandle *handle = [handleClass handleForPredicate:predicate error:nil];
    pid_t processIdentifier = handle ? handle.pid : 0;
    return processIdentifier > 0 && KSBallProcessIsAlive(processIdentifier) ? handle : nil;
}

#pragma mark - 场景

- (BOOL)createSceneForProcessHandle:(RBSProcessHandle *)handle failureReason:(NSString **)failureReason {
    @try {
        self.processIdentifier = handle.pid;
        [[KSBallPrivateClass(FBProcessManager) sharedInstance] registerProcessForAuditToken:handle.auditToken];

        // 每次打开都用新的场景标识，多窗口与关闭后重开互不干扰。
        NSString *sceneIdentifier = [NSString stringWithFormat:@"%@:%@:%@", KSBallFloatingScenePrefix, self.bundleIdentifier, NSUUID.UUID.UUIDString];
        FBSMutableSceneDefinition *definition = [KSBallPrivateClass(FBSMutableSceneDefinition) definition];
        definition.identity = [KSBallPrivateClass(FBSSceneIdentity) identityForIdentifier:sceneIdentifier];
        definition.clientIdentity = [KSBallPrivateClass(FBSSceneClientIdentity) identityForProcessIdentity:handle.identity];
        definition.specification = [KSBallPrivateClass(UIApplicationSceneSpecification) specification];
        FBSMutableSceneParameters *parameters = [KSBallPrivateClass(FBSMutableSceneParameters) parametersForSpecification:definition.specification];
        parameters.settings = [self initialSceneSettings];

        UIMutableApplicationSceneClientSettings *clientSettings = [KSBallPrivateClass(UIMutableApplicationSceneClientSettings) new];
        clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
        clientSettings.statusBarStyle = 0;
        parameters.clientSettings = clientSettings;

        FBScene *scene = [[KSBallPrivateClass(FBSceneManager) sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];
        if (!scene) {
            *failureReason = @"FrontBoard 未能创建场景";
            return NO;
        }
        self.sceneIdentifier = sceneIdentifier;

        _UIScenePresenter *presenter = [scene.uiPresentationManager createPresenterWithIdentifier:sceneIdentifier];
        [presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
            context.appearanceStyle = KSBallFloatingPresentationAppearanceStyle;
        }];
        [presenter activate];
        self.presenter = presenter;
        self.presentationView = presenter.presentationView;
        if (!self.presentationView) {
            *failureReason = @"场景没有可显示的画面";
            [self destroyScene];
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        *failureReason = [NSString stringWithFormat:@"创建场景失败：%@", exception.reason];
        [self destroyScene];
        return NO;
    }
}

// 应用按竖屏全屏尺寸与安全区布局，窗口只做等比缩放，与全屏打开时的界面完全一致。
- (UIMutableApplicationSceneSettings *)initialSceneSettings {
    UIMutableApplicationSceneSettings *settings = [KSBallPrivateClass(UIMutableApplicationSceneSettings) new];
    UIScreen *screen = UIScreen.mainScreen;
    settings.canShowAlerts = YES;
    settings.foreground = YES;
    settings.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(screen.bounds), CGRectGetHeight(screen.bounds));
    settings.interfaceOrientation = UIInterfaceOrientationPortrait;
    settings.level = 1;
    settings.persistenceIdentifier = NSUUID.UUID.UUIDString;
    settings.statusBarDisabled = YES;
    settings.safeAreaInsetsPortrait = self.sceneSafeAreaInsets;
    settings.peripheryInsets = self.sceneSafeAreaInsets;
    if ([screen respondsToSelector:@selector(displayConfiguration)]) {
        settings.displayConfiguration = screen.displayConfiguration;
    }
    if ([settings respondsToSelector:@selector(setDeviceOrientation:)]) {
        settings.deviceOrientation = UIDeviceOrientationPortrait;
    }
    if ([settings respondsToSelector:@selector(setUserInterfaceStyle:)]) {
        settings.userInterfaceStyle = self.userInterfaceStyle;
    }
    return settings;
}

- (void)updateUserInterfaceStyle:(UIUserInterfaceStyle)userInterfaceStyle {
    if (self.userInterfaceStyle == userInterfaceStyle) {
        return;
    }
    self.userInterfaceStyle = userInterfaceStyle;
    FBScene *scene = self.presenter.scene;
    if (![scene respondsToSelector:@selector(updateSettingsWithBlock:)]) {
        return;
    }
    @try {
        [scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            if ([settings respondsToSelector:@selector(setUserInterfaceStyle:)]) {
                settings.userInterfaceStyle = userInterfaceStyle;
            }
        }];
    } @catch (NSException *exception) {
        NSLog(@"KSBall floating scene appearance update failed: %@", exception);
    }
}

#pragma mark - 进程

- (void)monitorProcessExit {
    if (self.processExitSource || self.processIdentifier <= 0) {
        return;
    }
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)self.processIdentifier, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    if (!source) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        [weakSelf handleProcessExit];
    });
    dispatch_resume(source);
    self.processExitSource = source;
}

- (void)handleProcessExit {
    self.processExited = YES;
    if (self.processExitSource) {
        dispatch_source_cancel(self.processExitSource);
        self.processExitSource = nil;
    }
    if (!self.invalidated && self.processExitHandler) {
        self.processExitHandler();
    }
}

#pragma mark - 结束

- (void)invalidate {
    [self invalidateTerminatingProcess:YES];
}

- (void)detachForFullScreenLaunch {
    [self invalidateTerminatingProcess:NO];
}

- (void)invalidateTerminatingProcess:(BOOL)terminateProcess {
    if (self.invalidated) {
        return;
    }
    self.invalidated = YES;
    self.launchTransaction = nil;
    [self destroyScene];

    pid_t processIdentifier = self.processIdentifier;
    // 附加到已在运行的应用时不结束它，只收回我们创建的场景。
    if (!terminateProcess || !self.launchedByHost || self.processExited || processIdentifier <= 0) {
        return;
    }
    kill(processIdentifier, SIGTERM);
    // 保留退出监听以判断进程是否已结束，避免宽限期后误杀复用了同一 PID 的其它进程。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(KSBallFloatingTerminationGracePeriod * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.processExited && KSBallProcessIsAlive(processIdentifier)) {
            kill(processIdentifier, SIGKILL);
        }
    });
}

- (void)destroyScene {
    _UIScenePresenter *presenter = self.presenter;
    self.presenter = nil;
    [self.presentationView removeFromSuperview];
    self.presentationView = nil;
    @try {
        [presenter deactivate];
        [presenter invalidate];
        if (self.sceneIdentifier) {
            [[KSBallPrivateClass(FBSceneManager) sharedInstance] destroyScene:self.sceneIdentifier withTransitionContext:nil];
        }
    } @catch (NSException *exception) {
        NSLog(@"KSBall floating scene teardown failed: %@", exception);
    }
    self.sceneIdentifier = nil;
}

@end
