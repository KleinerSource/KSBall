#import "KeepSceneDelegate.h"
#import "HUDSceneCoordinator.h"
#import "PassthroughHUDWindow.h"

@interface KeepSceneDelegate ()
@property (nonatomic, strong) UIWindow *window;
@end

@implementation KeepSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (!KSBallIsHUDProcess() || ![scene isKindOfClass:UIWindowScene.class]) {
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
