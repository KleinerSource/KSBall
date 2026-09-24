#import <Foundation/Foundation.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const KSBallSettingsDidChangeNotification;

@interface KSBallSettingsStore : NSObject

@property (nonatomic, copy, readonly) KSBallSettings *settings;

+ (instancetype)sharedStore;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults key:(NSString *)key;
- (void)mutateSettings:(void (NS_NOESCAPE ^)(KSBallSettings *settings))mutation;
- (BOOL)addShortcut:(KSBallShortcut *)shortcut;
/// 批量添加，跳过重复项并在达到上限时停止，返回实际添加的数量。
- (NSUInteger)addShortcuts:(NSArray<KSBallShortcut *> *)shortcuts;
- (void)removeShortcutAtIndex:(NSUInteger)index;
- (void)moveShortcutFromIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
