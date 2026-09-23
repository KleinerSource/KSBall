#import "AppDelegate.h"
#import "HUDSceneCoordinator.h"

@implementation AppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        [HUDSceneCoordinator.sharedCoordinator bootstrapHUDProcessIfNeeded];
    }
    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [HUDSceneCoordinator sharedCoordinator];
    if (KSBallIsHUDProcess()) {
        NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:KSBallHUDActivityType];
        activity.title = @"KSBall HUD";
        [application requestSceneSessionActivation:nil userActivity:activity options:nil errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"KSBall HUD scene activation failed: %@", error.localizedDescription);
        }];
    }
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    NSString *configurationName = KSBallIsHUDProcess() ? @"KeepScene" : @"Default Configuration";
    return [[UISceneConfiguration alloc] initWithName:configurationName sessionRole:connectingSceneSession.role];
}

@end
