#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger KSBallMaximumShortcuts;
FOUNDATION_EXPORT const CGFloat KSBallMinimumIconSize;
FOUNDATION_EXPORT const CGFloat KSBallMaximumIconSize;
FOUNDATION_EXPORT const CGFloat KSBallDefaultIconSize;
FOUNDATION_EXPORT const CGFloat KSBallMinimumIconSpacing;
FOUNDATION_EXPORT const CGFloat KSBallMaximumIconSpacing;
FOUNDATION_EXPORT const CGFloat KSBallDefaultIconSpacing;
FOUNDATION_EXPORT const CGFloat KSBallMinimumRingSpacing;
FOUNDATION_EXPORT const CGFloat KSBallMaximumRingSpacing;
FOUNDATION_EXPORT const CGFloat KSBallDefaultRingSpacing;
FOUNDATION_EXPORT const CGFloat KSBallMinimumBackdropOpacity;
FOUNDATION_EXPORT const CGFloat KSBallDefaultBackdropOpacity;

typedef NS_ENUM(NSInteger, KSBallEdge) {
    KSBallEdgeLeft = 0,
    KSBallEdgeRight = 1,
};

typedef NS_ENUM(NSInteger, KSBallHandleStyle) {
    KSBallHandleStyleLight = 0,
    KSBallHandleStyleDark = 1,
    /// 不绘制悬浮条，但边缘热区仍可滑出菜单。
    KSBallHandleStyleHidden = 2,
};

typedef NS_ENUM(NSInteger, KSBallBackdropStyle) {
    KSBallBackdropStyleLight = 0,
    KSBallBackdropStyleDark = 1,
    KSBallBackdropStyleNone = 2,
};

@interface KSBallShortcut : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSUUID *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)shortcutFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

@interface KSBallSettings : NSObject <NSCopying>

@property (nonatomic) BOOL enabled;
@property (nonatomic) KSBallEdge edge;
@property (nonatomic) CGFloat normalizedVerticalPosition;
@property (nonatomic) CGFloat iconSize;
/// 同一圈内相邻图标之间的间距。
@property (nonatomic) CGFloat iconSpacing;
/// 相邻两圈之间的间距。
@property (nonatomic) CGFloat ringSpacing;
@property (nonatomic) KSBallHandleStyle handleStyle;
@property (nonatomic) KSBallBackdropStyle backdropStyle;
@property (nonatomic) CGFloat backdropOpacity;
@property (nonatomic, strong) NSMutableArray<KSBallShortcut *> *shortcuts;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
