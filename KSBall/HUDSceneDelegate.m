#import "HUDSceneDelegate.h"
#import "HUDSceneCoordinator.h"
#import "PassthroughHUDWindow.h"

@implementation HUDSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }
    self.window = [[PassthroughHUDWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [HUDSceneCoordinator.sharedCoordinator connectHUDWindow:self.window session:session];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [HUDSceneCoordinator.sharedCoordinator disconnectHUDSession:scene.session];
    self.window = nil;
}

@end
