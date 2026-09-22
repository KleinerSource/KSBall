#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;
@class HUDSceneCoordinator;

@interface ConfigurationViewController : UITableViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore
                    applicationBridge:(SystemApplicationBridge *)applicationBridge
                 hudSceneCoordinator:(HUDSceneCoordinator *)hudSceneCoordinator;

@end

NS_ASSUME_NONNULL_END
