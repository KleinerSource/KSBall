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
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    NSString *configurationName = KSBallIsHUDProcess() ? @"KeepScene" : @"Default Configuration";
    return [[UISceneConfiguration alloc] initWithName:configurationName sessionRole:connectingSceneSession.role];
}

@end
