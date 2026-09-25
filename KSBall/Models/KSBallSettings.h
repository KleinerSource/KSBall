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
FOUNDATION_EXPORT const CGFloat KSBallMinimumFloatingWindowDwellDuration;
FOUNDATION_EXPORT const CGFloat KSBallMaximumFloatingWindowDwellDuration;
FOUNDATION_EXPORT const CGFloat KSBallDefaultFloatingWindowDwellDuration;

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
/// 兼容旧版本逐应用开关数据；新版本不再读取此值来决定启动方式。
@property (nonatomic) BOOL opensInFloatingWindow;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)shortcutFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

@interface KSBallSettings : NSObject <NSCopying>

@property (nonatomic) BOOL enabled;
/// 总开关关闭时，悬浮应用快捷项改为全屏打开，不初始化悬浮分屏宿主。
@property (nonatomic) BOOL floatingSplitEnabled;
/// 在扇形菜单中悬停选中应用后，达到该时长再松手则以悬浮窗打开。
@property (nonatomic) CGFloat floatingWindowDwellDuration;
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

/// 兼容旧版本逐应用开关数据；不再用于决定悬浮窗口模式。
@property (nonatomic, readonly) BOOL hasFloatingWindowShortcuts;
/// 悬浮分屏总开关开启时，HUD 子进程初始化宿主。
@property (nonatomic, readonly) BOOL shouldEnableFloatingAppHosting;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
