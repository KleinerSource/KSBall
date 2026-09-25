#import <UIKit/UIKit.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger KSBallMaximumFloatingWindows;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowDefaultScale;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowMinimumScale;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowMaximumScale;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowThumbnailScale;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowTitleBarHeight;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowCornerRadius;
FOUNDATION_EXPORT const CGFloat KSBallFloatingWindowThumbnailCornerRadius;
/// 收纳区底板在缩略图四周留出的边距。
FOUNDATION_EXPORT const CGFloat KSBallFloatingDockPadding;

/// 悬浮窗的几何计算。被托管的应用始终按竖屏全屏尺寸布局，窗口只是把整个界面等比缩小显示，
/// 因此窗口内容区与屏幕同宽高比，标题条额外叠加在内容区上方。
@interface KSBallFloatingWindowLayout : NSObject

+ (CGFloat)clampedScale:(CGFloat)scale;
/// 展开状态的窗口尺寸：内容区为屏幕尺寸乘以 scale，再加上标题条高度。
+ (CGSize)windowSizeForScale:(CGFloat)scale screenSize:(CGSize)screenSize;
/// 由窗口宽度反推缩放比例（已限制在允许范围内）。
+ (CGFloat)scaleForWindowWidth:(CGFloat)width screenSize:(CGSize)screenSize;
+ (CGSize)thumbnailSizeForScreenSize:(CGSize)screenSize;

/// 第 index 个新窗口的默认位置：在安全区内居中，之后每个依次向右下错开。
+ (CGRect)defaultFrameForIndex:(NSUInteger)index scale:(CGFloat)scale screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;
/// 松手后把窗口收回可见范围：能完整放下时整窗位于安全区内，放不下时贴住安全区顶部，保证标题条可抓取。
+ (CGRect)clampedFrame:(CGRect)frame inBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;
/// 窗口被拖出屏幕左右边缘超过自身宽度的 35% 时收进该侧的收纳区。
+ (BOOL)shouldMinimizeFrame:(CGRect)frame inBounds:(CGRect)bounds edge:(nullable KSBallEdge *)edge;

/// 收纳区中第 index 个缩略图的位置：贴着屏幕边缘从安全区顶部向下排列。
+ (CGRect)dockSlotFrameAtIndex:(NSUInteger)index edge:(KSBallEdge)edge screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;
/// 恰好包住 count 个缩略图的收纳区底板；count 为 0 时返回 CGRectZero。
+ (CGRect)dockPlateFrameForCount:(NSUInteger)count edge:(KSBallEdge)edge screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;

@end

NS_ASSUME_NONNULL_END
