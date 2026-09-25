#import "AppDelegate.h"
#import "ConfigurationViewController.h"
#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "KSBallUpdateChecker.h"
#import "SystemApplicationBridge.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    ConfigurationViewController *configuration = [[ConfigurationViewController alloc] initWithSettingsStore:KSBallSettingsStore.sharedStore applicationBridge:SystemApplicationBridge.new hudSceneCoordinator:HUDSceneCoordinator.sharedCoordinator updateChecker:KSBallUpdateChecker.sharedChecker];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:configuration];
    [self.window makeKeyAndVisible];
    [HUDSceneCoordinator.sharedCoordinator activateHUD];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    return [url.scheme isEqualToString:@"ksball"];
}

@end
