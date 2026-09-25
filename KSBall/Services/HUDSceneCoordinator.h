#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;

FOUNDATION_EXPORT BOOL KSBallIsHUDProcess(void);
/// HUD 子进程是否已成功初始化为悬浮分屏宿主。
FOUNDATION_EXPORT BOOL KSBallFloatingAppHostingAvailable(void);
FOUNDATION_EXPORT int KSBallRunHUDProcess(void);
FOUNDATION_EXPORT int KSBallStopHUDProcessMain(pid_t processIdentifier);

@interface HUDSceneCoordinator : NSObject

@property (nonatomic, readonly, getter=isHUDActive) BOOL HUDActive;
@property (nonatomic, copy, readonly) NSString *statusDescription;
/// HUD 子进程最近一次写入的悬浮分屏宿主状态。
@property (nonatomic, copy, readonly) NSString *floatingHostStatusDescription;

+ (instancetype)sharedCoordinator;
- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)activateHUD;
- (void)deactivateHUD;
- (void)openConfiguration;

@end

NS_ASSUME_NONNULL_END
