#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import "FloatingHUDViewController.h"
#import "PassthroughHUDWindow.h"
#import <dlfcn.h>

NSString * const KSBallHUDActivityType = @"com.kleinersource.ksball.hud";

BOOL KSBallPrepareFrontBoardSystemShell(void) {
    static dispatch_once_t onceToken;
    static BOOL ready;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/FrontBoardHUD.framework/FrontBoardHUD", RTLD_LAZY);
        typedef void (*FBSystemShellInitializeFunction)(id);
        FBSystemShellInitializeFunction initializer = (FBSystemShellInitializeFunction)dlsym(RTLD_DEFAULT, "FBSystemShellInitialize");
        if (initializer) {
            initializer(nil);
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
@property (nonatomic) BOOL frontBoardReady;
@property (nonatomic) BOOL hudActivationRequested;
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
    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:KSBallHUDActivityType];
    activity.title = @"KSBall HUD";
    [[UIApplication sharedApplication] requestSceneSessionActivation:nil userActivity:activity options:nil errorHandler:^(NSError * _Nonnull error) {
        NSLog(@"KSBall HUD scene activation failed: %@", error.localizedDescription);
    }];
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
}

@end
