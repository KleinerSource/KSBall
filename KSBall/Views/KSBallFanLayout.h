#import <UIKit/UIKit.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

// 悬浮条可见部分的几何参数，悬浮窗与设置页中的排序编辑器共用，保证两边位置一致。
FOUNDATION_EXPORT const CGFloat KSBallHandleEdgeInset;
FOUNDATION_EXPORT const CGFloat KSBallHandleBarWidth;
FOUNDATION_EXPORT const CGFloat KSBallHandleBarHeight;

@interface KSBallFanLayout : NSObject

/// 可见悬浮条中心的纵向可移动范围：与屏幕上下边缘保留 10pt，允许拖到四个角落。
+ (CGFloat)minimumHandleCenterYInBounds:(CGRect)bounds;
+ (CGFloat)maximumHandleCenterYInBounds:(CGRect)bounds;
+ (CGPoint)handleCenterForEdge:(KSBallEdge)edge normalizedPosition:(CGFloat)normalizedPosition inBounds:(CGRect)bounds;
/// 扇形菜单可以占用的区域：安全区再向内收 8pt。
+ (CGRect)menuSafeBoundsForBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;

/// 以把手旁的图标列为圆心逐圈排布图标（内圈优先）。
/// - 同一圈相邻图标的中心距不小于 itemSize + itemSpacing；
/// - 相邻两圈的半径差为 itemSize + ringSpacing；
/// - 每圈各自按半径和屏幕上下可用空间求出可见张角，并在张角内按弧长放下尽可能多的图标。
/// 放不下时会把图标尺寸和两种间距按同一比例缩小，实际比例通过 scale 返回（1 表示未缩放）。
+ (NSArray<NSValue *> *)centersForItemCount:(NSUInteger)itemCount
                               anchorCenter:(CGPoint)anchorCenter
                                 safeBounds:(CGRect)safeBounds
                                       edge:(KSBallEdge)edge
                                   itemSize:(CGFloat)itemSize
                                itemSpacing:(CGFloat)itemSpacing
                                ringSpacing:(CGFloat)ringSpacing
                                      scale:(nullable CGFloat *)scale;

@end

NS_ASSUME_NONNULL_END
