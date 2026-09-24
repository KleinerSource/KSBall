#import "KSBallFanLayout.h"
#import <math.h>

// 第一圈图标到扇形圆心（把手）的最小距离：半个把手高度加上手指离开把手所需的余量。
static const CGFloat KSBallFanHandleClearance = 30.0;
// 每圈张角至少保持四分之一圆；上下空间都不够时整体缩小图标。
static const CGFloat KSBallFanMinimumSweep = M_PI_2;
static const CGFloat KSBallFanShrinkFactor = 0.9;
// 48 个图标挤在角落时需要缩得更多：0.9^16 ≈ 0.19。
static const NSUInteger KSBallFanMaximumShrinkAttempts = 16;

@implementation KSBallFanLayout

+ (NSArray<NSValue *> *)centersForItemCount:(NSUInteger)itemCount anchorCenter:(CGPoint)anchorCenter safeBounds:(CGRect)safeBounds edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize itemSpacing:(CGFloat)itemSpacing ringSpacing:(CGFloat)ringSpacing scale:(CGFloat *)scale {
    NSUInteger count = MIN(itemCount, KSBallMaximumShortcuts);
    if (scale) {
        *scale = 1.0;
    }
    if (count == 0 || itemSize <= 0.0) {
        return @[];
    }

    CGFloat resolvedScale = 1.0;
    NSArray<NSValue *> *centers = nil;
    for (NSUInteger attempt = 0; attempt <= KSBallFanMaximumShrinkAttempts; attempt++) {
        BOOL fits = NO;
        centers = [self fanCentersForCount:count anchorCenter:anchorCenter safeBounds:safeBounds edge:edge itemSize:itemSize * resolvedScale itemSpacing:MAX(itemSpacing, 0.0) * resolvedScale ringSpacing:MAX(ringSpacing, 0.0) * resolvedScale fits:&fits];
        if (fits || attempt == KSBallFanMaximumShrinkAttempts) {
            break;
        }
        resolvedScale *= KSBallFanShrinkFactor;
    }
    if (scale) {
        *scale = resolvedScale;
    }

    // 兜底：缩到下限仍放不下时整体平移并夹紧到安全区内。
    CGFloat itemRadius = itemSize * resolvedScale / 2.0;
    CGFloat minimumY = CGFLOAT_MAX;
    CGFloat maximumY = -CGFLOAT_MAX;
    for (NSValue *value in centers) {
        CGPoint point = value.CGPointValue;
        minimumY = MIN(minimumY, point.y - itemRadius);
        maximumY = MAX(maximumY, point.y + itemRadius);
    }
    CGFloat lowerTranslation = CGRectGetMinY(safeBounds) - minimumY;
    CGFloat upperTranslation = CGRectGetMaxY(safeBounds) - maximumY;
    CGFloat translationY = MIN(MAX(0.0, lowerTranslation), upperTranslation);

    NSMutableArray<NSValue *> *clampedCenters = [NSMutableArray arrayWithCapacity:centers.count];
    for (NSValue *value in centers) {
        CGPoint point = value.CGPointValue;
        point.y += translationY;
        point.x = MIN(MAX(point.x, CGRectGetMinX(safeBounds) + itemRadius), CGRectGetMaxX(safeBounds) - itemRadius);
        [clampedCenters addObject:[NSValue valueWithCGPoint:point]];
    }
    return clampedCenters;
}

+ (NSArray<NSValue *> *)fanCentersForCount:(NSUInteger)count anchorCenter:(CGPoint)anchorCenter safeBounds:(CGRect)safeBounds edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize itemSpacing:(CGFloat)itemSpacing ringSpacing:(CGFloat)ringSpacing fits:(BOOL *)fits {
    const CGFloat itemRadius = itemSize / 2.0;
    const CGFloat itemStep = itemSize + itemSpacing;
    const CGFloat ringStep = itemSize + ringSpacing;
    const CGFloat direction = edge == KSBallEdgeLeft ? 1.0 : -1.0;
    // 圆心放在贴边的那一列图标上，使正上/正下方向的图标恰好沿屏幕边缘排成一列。
    CGFloat minimumCenterY = CGRectGetMinY(safeBounds) + itemRadius;
    CGFloat maximumCenterY = MAX(CGRectGetMaxY(safeBounds) - itemRadius, minimumCenterY);
    CGPoint center = CGPointMake(edge == KSBallEdgeLeft ? CGRectGetMinX(safeBounds) + itemRadius : CGRectGetMaxX(safeBounds) - itemRadius,
                                 MIN(MAX(anchorCenter.y, minimumCenterY), maximumCenterY));
    CGFloat spaceAbove = center.y - minimumCenterY;
    CGFloat spaceBelow = maximumCenterY - center.y;
    CGFloat maximumRadius = CGRectGetWidth(safeBounds) - itemSize;

    // 第一圈刚好能在四分之一圆上并排 3 个图标（半圆约 5 个），且不压到把手。
    CGFloat firstRadius = MAX(itemRadius + KSBallFanHandleClearance, itemStep / (2.0 * sin(M_PI / 8.0)));
    // 当前半径下这一圈上下可见的角度范围。角度相对“指向屏幕内侧的水平方向”，正值向下；
    // 每圈按自身半径计算，所以内圈可以比外圈张得更开，整体贴合屏幕可显示的区域。
    void (^visibleAngles)(CGFloat, CGFloat *, CGFloat *) = ^(CGFloat radius, CGFloat *lower, CGFloat *upper) {
        CGFloat upperAngle = spaceBelow >= radius ? M_PI_2 : asin(spaceBelow / radius);
        CGFloat lowerAngle = spaceAbove >= radius ? -M_PI_2 : -asin(spaceAbove / radius);
        CGFloat missingSweep = KSBallFanMinimumSweep - (upperAngle - lowerAngle);
        if (missingSweep > 0.0) {
            // 上下空间都不足时向空间较大的一侧补足张角，超出部分由外层缩小图标处理。
            if (spaceBelow >= spaceAbove) {
                upperAngle = MIN(M_PI_2, upperAngle + missingSweep);
            } else {
                lowerAngle = MAX(-M_PI_2, lowerAngle - missingSweep);
            }
        }
        *lower = lowerAngle;
        *upper = upperAngle;
    };
    // 弦长不小于 itemStep 时相邻图标保持设定的同圈间距。
    NSUInteger (^capacityAt)(CGFloat, CGFloat) = ^NSUInteger(CGFloat radius, CGFloat sweep) {
        CGFloat angleStep = 2.0 * asin(MIN(1.0, itemStep / (radius * 2.0)));
        return (NSUInteger)floor(sweep / angleStep + 1e-6) + 1;
    };

    BOOL allFit = YES;
    NSMutableArray<NSValue *> *centers = [NSMutableArray arrayWithCapacity:count];
    NSUInteger remaining = count;
    CGFloat previousRadius = 0.0;
    for (NSUInteger ring = 0; remaining > 0; ring++) {
        CGFloat radius = ring == 0 ? firstRadius : previousRadius + ringStep;
        CGFloat lowerAngle = 0.0;
        CGFloat upperAngle = 0.0;
        visibleAngles(radius, &lowerAngle, &upperAngle);
        NSUInteger capacity = capacityAt(radius, upperAngle - lowerAngle);
        // 目标是每向外一圈多放 2 个（按四分之一圆计，即 3、5、7、9……，半圆为 5、9、13……）。
        // 按圈间距排出的半径往往差一点点放不下，这时把这一圈再向外推，最多推半个圈距；
        // 推得动就按目标数量排，推不动（屏幕边界或间距太大）就按实际能放下的数量排。
        // 最后一圈图标不够填满时不必外推。
        if (ring > 0 && remaining > capacity) {
            CGFloat quarterFraction = (upperAngle - lowerAngle) / M_PI_2;
            NSUInteger target = (NSUInteger)lround((2.0 + 2.0 * ring) * quarterFraction) + 1;
            if (capacity < target && target > 1) {
                CGFloat angleStep = (upperAngle - lowerAngle) / (target - 1);
                CGFloat targetRadius = itemStep / (2.0 * sin(MIN(angleStep, M_PI) / 2.0));
                if (targetRadius - radius <= ringStep / 2.0) {
                    CGFloat targetLower = 0.0;
                    CGFloat targetUpper = 0.0;
                    visibleAngles(targetRadius, &targetLower, &targetUpper);
                    NSUInteger targetCapacity = capacityAt(targetRadius, targetUpper - targetLower);
                    if (targetCapacity > capacity) {
                        radius = targetRadius;
                        lowerAngle = targetLower;
                        upperAngle = targetUpper;
                        capacity = targetCapacity;
                    }
                }
            }
        }
        if (upperAngle - lowerAngle < KSBallFanMinimumSweep - 1e-6 ||
            radius * sin(upperAngle) > spaceBelow + 0.001 ||
            radius * sin(-lowerAngle) > spaceAbove + 0.001 ||
            radius > maximumRadius + 0.001) {
            allFit = NO;
        }

        CGFloat sweep = upperAngle - lowerAngle;
        NSUInteger ringCount = MIN(capacity, remaining);
        for (NSUInteger index = 0; index < ringCount; index++) {
            // 每圈铺满自己的可见张角，保持扇形轮廓；只有一个图标时放在张角中线上。
            CGFloat progress = ringCount == 1 ? 0.5 : (CGFloat)index / (CGFloat)(ringCount - 1);
            CGFloat angle = lowerAngle + sweep * progress;
            [centers addObject:[NSValue valueWithCGPoint:CGPointMake(center.x + direction * cos(angle) * radius, center.y + sin(angle) * radius)]];
        }
        remaining -= ringCount;
        previousRadius = radius;
    }
    if (fits) {
        *fits = allFit;
    }
    return centers;
}

@end
