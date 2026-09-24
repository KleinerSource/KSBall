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
