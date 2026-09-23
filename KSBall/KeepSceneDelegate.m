#import "KeepSceneDelegate.h"
#import "HUDSceneCoordinator.h"
#import "PassthroughHUDWindow.h"

@interface KeepSceneDelegate ()
@property (nonatomic, strong) UIWindow *hudWindow;
@end

@implementation KeepSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (KSBallIsHUDProcess() || ![scene isKindOfClass:UIWindowScene.class]) {
        return;
    }

    self.hudWindow = [[PassthroughHUDWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    [HUDSceneCoordinator.sharedCoordinator connectHUDWindow:self.hudWindow session:session];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [HUDSceneCoordinator.sharedCoordinator disconnectHUDSession:scene.session];
    self.hudWindow = nil;
}

@end
