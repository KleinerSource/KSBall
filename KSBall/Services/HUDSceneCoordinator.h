#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;

FOUNDATION_EXPORT NSString * const KSBallHUDActivityType;
FOUNDATION_EXPORT BOOL KSBallPrepareFrontBoardSystemShell(void);

@interface HUDSceneCoordinator : NSObject

@property (nonatomic, readonly, getter=isHUDActive) BOOL HUDActive;
@property (nonatomic, readonly, getter=isFrontBoardReady) BOOL frontBoardReady;

+ (instancetype)sharedCoordinator;
- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)activateHUD;
- (void)deactivateHUD;
- (void)connectHUDWindow:(UIWindow *)window session:(UISceneSession *)session;
- (void)disconnectHUDSession:(UISceneSession *)session;
- (void)openConfiguration;

@end

NS_ASSUME_NONNULL_END
