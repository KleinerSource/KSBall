#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;

FOUNDATION_EXPORT BOOL KSBallIsHUDProcess(void);
FOUNDATION_EXPORT int KSBallRunHUDProcess(void);
FOUNDATION_EXPORT int KSBallStopHUDProcessMain(pid_t processIdentifier);

@interface HUDSceneCoordinator : NSObject

@property (nonatomic, readonly, getter=isHUDActive) BOOL HUDActive;
@property (nonatomic, copy, readonly) NSString *statusDescription;

+ (instancetype)sharedCoordinator;
- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)activateHUD;
- (void)deactivateHUD;
- (void)openConfiguration;

@end

NS_ASSUME_NONNULL_END
