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

typedef NS_ENUM(NSInteger, KSBallEdge) {
    KSBallEdgeLeft = 0,
    KSBallEdgeRight = 1,
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

typedef NS_ENUM(NSInteger, KSBallKeyboardPresentationMode) {
    /// 键盘随悬浮应用画面缩放，并受悬浮窗裁剪。
    KSBallKeyboardPresentationModeFloatingWindow = 0,
    /// 键盘按系统尺寸显示在屏幕底部。
    KSBallKeyboardPresentationModeGlobal = 1,
};

@interface KSBallShortcut : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSUUID *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
/// 从扇形菜单以悬浮窗打开，而不是全屏启动。
@property (nonatomic) BOOL opensInFloatingWindow;

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
/// 悬浮条触摸热区在可见条四周向外扩展的距离。
@property (nonatomic) CGFloat handleTouchRadius;
@property (nonatomic) KSBallBackdropStyle backdropStyle;
/// 毛玻璃的模糊程度，1 为系统材质的完整模糊。
@property (nonatomic) CGFloat backdropBlur;
@property (nonatomic) KSBallKeyboardPresentationMode keyboardPresentationMode;
@property (nonatomic, strong) NSMutableArray<KSBallShortcut *> *shortcuts;

/// 是否有快捷应用设为以悬浮窗打开；HUD 子进程据此决定是否初始化悬浮分屏宿主。
@property (nonatomic, readonly) BOOL hasFloatingWindowShortcuts;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
