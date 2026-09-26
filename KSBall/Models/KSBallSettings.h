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
FOUNDATION_EXPORT const CGFloat KSBallMinimumBackdropBlur;
FOUNDATION_EXPORT const CGFloat KSBallDefaultBackdropBlur;
FOUNDATION_EXPORT const CGFloat KSBallMinimumHandleTouchRadius;
FOUNDATION_EXPORT const CGFloat KSBallMaximumHandleTouchRadius;
FOUNDATION_EXPORT const CGFloat KSBallDefaultHandleTouchRadius;
FOUNDATION_EXPORT const CGFloat KSBallMinimumFixedTriggerInset;
FOUNDATION_EXPORT const CGFloat KSBallMaximumFixedTriggerInset;

typedef NS_ENUM(NSInteger, KSBallEdge) {
    KSBallEdgeLeft = 0,
    KSBallEdgeRight = 1,
};

typedef NS_ENUM(NSInteger, KSBallMenuTriggerMode) {
    KSBallMenuTriggerModeHandle = 0,
    KSBallMenuTriggerModeFixedCorners = 1,
};

typedef NS_OPTIONS(NSUInteger, KSBallFixedTriggerCorner) {
    KSBallFixedTriggerCornerTopLeft = 1 << 0,
    KSBallFixedTriggerCornerTopRight = 1 << 1,
    KSBallFixedTriggerCornerBottomLeft = 1 << 2,
    KSBallFixedTriggerCornerBottomRight = 1 << 3,
    KSBallFixedTriggerCornerAll = (1 << 4) - 1,
};

// 数值与已保存的设置兼容，新增的“自动”放在末尾。
typedef NS_ENUM(NSInteger, KSBallHandleStyle) {
    KSBallHandleStyleLight = 0,
    KSBallHandleStyleDark = 1,
    /// 不绘制悬浮条，但边缘热区仍可滑出菜单。
    KSBallHandleStyleHidden = 2,
    /// 跟随系统深色模式。
    KSBallHandleStyleAutomatic = 3,
};

typedef NS_ENUM(NSInteger, KSBallBackdropStyle) {
    KSBallBackdropStyleLight = 0,
    KSBallBackdropStyleDark = 1,
    KSBallBackdropStyleNone = 2,
    /// 跟随系统深色模式。
    KSBallBackdropStyleAutomatic = 3,
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
@property (nonatomic) KSBallMenuTriggerMode menuTriggerMode;
@property (nonatomic) KSBallFixedTriggerCorner fixedTriggerCorners;
@property (nonatomic) BOOL landscapeTriggerEnabled;
@property (nonatomic) CGFloat fixedTriggerHorizontalInset;
@property (nonatomic) CGFloat fixedTriggerVerticalInset;
@property (nonatomic) KSBallEdge edge;
@property (nonatomic) CGFloat normalizedVerticalPosition;
@property (nonatomic) CGFloat iconSize;
/// 同一圈内相邻图标之间的间距。
@property (nonatomic) CGFloat iconSpacing;
/// 相邻两圈之间的间距。
@property (nonatomic) CGFloat ringSpacing;
@property (nonatomic) KSBallHandleStyle handleStyle;
/// 悬浮条触摸热区在可见条四周向外扩展的距离。
@property (nonatomic) CGFloat handleTouchRadius;
@property (nonatomic) KSBallBackdropStyle backdropStyle;
/// 毛玻璃的模糊程度，1 为系统材质的完整模糊。
@property (nonatomic) CGFloat backdropBlur;
@property (nonatomic, strong) NSMutableArray<KSBallShortcut *> *shortcuts;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
