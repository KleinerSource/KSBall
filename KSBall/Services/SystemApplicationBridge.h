#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface KSBallApplication : NSObject

@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, strong, readonly, nullable) UIImage *icon;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName icon:(nullable UIImage *)icon;

@end

typedef NSArray<KSBallApplication *> * _Nonnull (^KSBallApplicationProvider)(void);
typedef BOOL (^KSBallApplicationLauncher)(NSString *bundleIdentifier);

/// 设置页列表统一使用的 29pt 圆形图标，与悬浮菜单中的圆形图标保持一致；icon 为空时返回占位图标。
FOUNDATION_EXPORT UIImage *KSBallListIconImage(UIImage * _Nullable icon);

@protocol KSBallSystemApplicationBridging <NSObject>
- (NSArray<KSBallApplication *> *)availableApplications;
- (nullable UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier;
- (BOOL)launchBundleIdentifier:(NSString *)bundleIdentifier;
- (BOOL)isAvailable;
- (NSString *)unavailabilityReason;
@end

@interface SystemApplicationBridge : NSObject <KSBallSystemApplicationBridging>

- (instancetype)init;
- (instancetype)initWithApplicationProvider:(nullable KSBallApplicationProvider)applicationProvider launcher:(nullable KSBallApplicationLauncher)launcher;

@end

NS_ASSUME_NONNULL_END
