#import <UIKit/UIKit.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSBallFanLayout : NSObject

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
