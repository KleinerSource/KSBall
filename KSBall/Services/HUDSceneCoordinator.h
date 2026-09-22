#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;

FOUNDATION_EXPORT NSString * const KSBallHUDActivityType;
FOUNDATION_EXPORT BOOL KSBallPrepareFrontBoardSystemShell(void);
FOUNDATION_EXPORT BOOL KSBallIsHUDProcess(void);

@interface HUDSceneCoordinator : NSObject

@property (nonatomic, readonly, getter=isHUDActive) BOOL HUDActive;
@property (nonatomic, readonly, getter=isFrontBoardReady) BOOL frontBoardReady;
@property (nonatomic, copy, readonly) NSString *frontBoardStatusDescription;

+ (instancetype)sharedCoordinator;
- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)activateHUD;
- (void)rebuildHUD;
- (void)deactivateHUD;
- (void)bootstrapHUDProcessIfNeeded;
- (void)connectHUDWindow:(UIWindow *)window session:(UISceneSession *)session;
- (void)disconnectHUDSession:(UISceneSession *)session;
- (void)openConfiguration;

@end

NS_ASSUME_NONNULL_END
