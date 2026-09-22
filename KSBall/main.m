#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "HUDSceneCoordinator.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        KSBallPrepareFrontBoardSystemShell();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
