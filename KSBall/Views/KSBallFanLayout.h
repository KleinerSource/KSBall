#import <UIKit/UIKit.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSBallFanLayout : NSObject

/// 以把手旁的图标列为圆心，逐圈排布图标（内圈优先），相邻图标中心距至少为 itemSize + spacing。
/// 扇形张角随把手位置变化：屏幕中部为向内的半圆；靠近底部时收成向上的四分之一圆，最底一排保持水平；
/// 靠近顶部时同理向下展开，最顶一排保持水平。
/// 放不下时会把图标尺寸和间距按同一比例缩小，实际比例通过 scale 返回（1 表示未缩放）。
+ (NSArray<NSValue *> *)centersForItemCount:(NSUInteger)itemCount
                               anchorCenter:(CGPoint)anchorCenter
                                 safeBounds:(CGRect)safeBounds
                                       edge:(KSBallEdge)edge
                                   itemSize:(CGFloat)itemSize
                                    spacing:(CGFloat)spacing
                                      scale:(nullable CGFloat *)scale;

@end

NS_ASSUME_NONNULL_END
