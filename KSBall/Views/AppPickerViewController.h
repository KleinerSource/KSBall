#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SystemApplicationBridge;
@class KSBallShortcut;

@interface AppPickerViewController : UITableViewController

/// 每点一次 + 号就回调一次；返回 YES 表示已加入快捷列表，该应用随即从列表中移除。
@property (nonatomic, copy, nullable) BOOL (^selectionHandler)(KSBallShortcut *shortcut);

/// existingBundleIdentifiers 中的应用不会出现在列表里；最多还能添加 remainingCapacity 个。
- (instancetype)initWithApplicationBridge:(SystemApplicationBridge *)applicationBridge
                existingBundleIdentifiers:(NSArray<NSString *> *)existingBundleIdentifiers
                        remainingCapacity:(NSUInteger)remainingCapacity;

@end

NS_ASSUME_NONNULL_END
