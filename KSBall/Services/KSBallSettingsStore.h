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
- (void)reload;

@end

NS_ASSUME_NONNULL_END
