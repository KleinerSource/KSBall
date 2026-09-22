#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SystemApplicationBridge;
@class KSBallShortcut;

@interface AppPickerViewController : UITableViewController

@property (nonatomic, copy, nullable) void (^selectionHandler)(KSBallShortcut *shortcut);

- (instancetype)initWithApplicationBridge:(SystemApplicationBridge *)applicationBridge;

@end

NS_ASSUME_NONNULL_END
