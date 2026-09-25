#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;

@interface FloatingHUDViewController : UIViewController

@property (nonatomic, copy, nullable) dispatch_block_t openConfigurationHandler;

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)reloadFromSettings;
- (void)dismissMenuAnimated:(BOOL)animated;
/// HUD 退出前关闭全部悬浮窗，结束由悬浮分屏启动的应用进程。
- (void)closeFloatingWindows;

@end

NS_ASSUME_NONNULL_END
