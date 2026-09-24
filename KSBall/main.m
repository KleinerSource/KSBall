#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "HUDSceneCoordinator.h"
#import <string.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        // HUD 子进程不能走 UIApplicationMain：它不是由 FrontBoard 启动的，永远拿不到 UIScene。
        if (argc > 1 && strcmp(argv[1], "-hud") == 0) {
            return KSBallRunHUDProcess();
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
