#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "HUDSceneCoordinator.h"
#import <stdlib.h>
#import <string.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        // HUD 子进程不能走 UIApplicationMain：它不是由 FrontBoard 启动的，永远拿不到 UIScene。
        if (argc > 1 && strcmp(argv[1], "-hud") == 0) {
            return KSBallRunHUDProcess();
        }
        // root persona 停止进程：代主程序终止 HUD 子进程后立即退出。
        if (argc > 2 && strcmp(argv[1], "-stop-hud") == 0) {
            return KSBallStopHUDProcessMain((pid_t)atoi(argv[2]));
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
