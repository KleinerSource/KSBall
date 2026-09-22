#import "SceneDelegate.h"
#import "ConfigurationViewController.h"
#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    if (KSBallIsHUDProcess()) {
        return;
    }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    ConfigurationViewController *configuration = [[ConfigurationViewController alloc] initWithSettingsStore:KSBallSettingsStore.sharedStore applicationBridge:SystemApplicationBridge.new hudSceneCoordinator:HUDSceneCoordinator.sharedCoordinator];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:configuration];
    self.window = window;
    [window makeKeyAndVisible];
    [HUDSceneCoordinator.sharedCoordinator activateHUD];
}

@end
