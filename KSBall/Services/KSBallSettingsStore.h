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
- (void)removeShortcutAtIndex:(NSUInteger)index;
- (void)moveShortcutFromIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex;
/// 兼容旧版本逐应用设置；新版本不通过此值决定窗口打开模式。
- (void)setShortcutAtIndex:(NSUInteger)index opensInFloatingWindow:(BOOL)opensInFloatingWindow;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
