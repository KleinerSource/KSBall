#import "AppDelegate.h"
#import "HUDSceneCoordinator.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [HUDSceneCoordinator sharedCoordinator];
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    NSUserActivity *activity = options.userActivities.anyObject ?: connectingSceneSession.stateRestorationActivity;
    NSString *configurationName = [activity.activityType isEqualToString:KSBallHUDActivityType] ? @"HUDScene" : @"Default Configuration";
    return [[UISceneConfiguration alloc] initWithName:configurationName sessionRole:connectingSceneSession.role];
}

@end
