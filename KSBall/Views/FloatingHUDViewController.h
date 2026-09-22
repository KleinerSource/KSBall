#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KSBallSettingsStore;
@class SystemApplicationBridge;

@interface FloatingHUDViewController : UIViewController

@property (nonatomic, copy, nullable) dispatch_block_t openConfigurationHandler;

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge;
- (void)reloadFromSettings;
- (void)dismissMenuAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
