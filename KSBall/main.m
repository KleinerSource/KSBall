#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "HUDSceneCoordinator.h"
#import <string.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "-hud") == 0) {
            return KSBallRunHUDProcess();
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
