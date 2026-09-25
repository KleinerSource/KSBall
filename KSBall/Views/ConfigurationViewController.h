#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;
@class HUDSceneCoordinator;
@class KSBallUpdateChecker;

@interface ConfigurationViewController : UITableViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore
                    applicationBridge:(SystemApplicationBridge *)applicationBridge
                 hudSceneCoordinator:(HUDSceneCoordinator *)hudSceneCoordinator
                        updateChecker:(KSBallUpdateChecker *)updateChecker;

@end

NS_ASSUME_NONNULL_END
