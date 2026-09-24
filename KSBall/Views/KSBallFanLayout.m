#import "KSBallFanLayout.h"
#import <math.h>

// 第一圈图标到扇形圆心（把手）的最小距离：半个把手高度加上手指离开把手所需的余量。
static const CGFloat KSBallFanHandleClearance = 30.0;
// 扇形张角至少保持四分之一圆。
static const CGFloat KSBallFanMinimumSweep = M_PI_2;
// 小于约 8° 的倾角直接拉平，让贴近屏幕上下边缘的一排图标整齐排成一行。
static const CGFloat KSBallFanFlattenAngle = 0.14;
static const CGFloat KSBallFanShrinkFactor = 0.9;
static const NSUInteger KSBallFanMaximumShrinkAttempts = 8;

@implementation KSBallFanLayout

+ (NSArray<NSValue *> *)centersForItemCount:(NSUInteger)itemCount anchorCenter:(CGPoint)anchorCenter safeBounds:(CGRect)safeBounds edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize spacing:(CGFloat)spacing scale:(CGFloat *)scale {
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
        centers = [self fanCentersForCount:count anchorCenter:anchorCenter safeBounds:safeBounds edge:edge itemSize:itemSize * resolvedScale spacing:MAX(spacing, 0.0) * resolvedScale fits:&fits];
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

+ (NSArray<NSValue *> *)fanCentersForCount:(NSUInteger)count anchorCenter:(CGPoint)anchorCenter safeBounds:(CGRect)safeBounds edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize spacing:(CGFloat)spacing fits:(BOOL *)fits {
    const CGFloat itemRadius = itemSize / 2.0;
    const CGFloat step = itemSize + spacing;
    const CGFloat direction = edge == KSBallEdgeLeft ? 1.0 : -1.0;
    const CGFloat firstRadius = MAX(step, itemRadius + KSBallFanHandleClearance);
    // 圆心放在贴边的那一列图标上，使正上/正下方向的图标恰好沿屏幕边缘排成一列。
    CGFloat minimumCenterY = CGRectGetMinY(safeBounds) + itemRadius;
    CGFloat maximumCenterY = MAX(CGRectGetMaxY(safeBounds) - itemRadius, minimumCenterY);
    CGPoint center = CGPointMake(edge == KSBallEdgeLeft ? CGRectGetMinX(safeBounds) + itemRadius : CGRectGetMaxX(safeBounds) - itemRadius,
                                 MIN(MAX(anchorCenter.y, minimumCenterY), maximumCenterY));
    CGFloat spaceAbove = center.y - minimumCenterY;
    CGFloat spaceBelow = maximumCenterY - center.y;

    NSArray<NSNumber *> *(^ringCountsForSweep)(CGFloat) = ^NSArray<NSNumber *> *(CGFloat sweep) {
        NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
        NSUInteger remaining = count;
        CGFloat radius = firstRadius;
        while (remaining > 0) {
            // 弦长等于 step 时相邻图标恰好保持设定间距。
            CGFloat angleStep = 2.0 * asin(MIN(1.0, step / (radius * 2.0)));
            NSUInteger capacity = (NSUInteger)floor(sweep / angleStep + 1e-6) + 1;
            NSUInteger ringCount = MIN(capacity, remaining);
            [counts addObject:@(ringCount)];
            remaining -= ringCount;
            radius += step;
        }
        return counts;
    };

    // 角度相对“指向屏幕内侧的水平方向”，正值向下。先按半圆排布，再根据外圈半径收窄张角，迭代几次即可收敛。
    CGFloat lowerAngle = -M_PI_2;
    CGFloat upperAngle = M_PI_2;
    for (NSUInteger iteration = 0; iteration < 4; iteration++) {
        NSArray<NSNumber *> *counts = ringCountsForSweep(upperAngle - lowerAngle);
        CGFloat outerRadius = firstRadius + step * (counts.count - 1);
        CGFloat newUpper = spaceBelow >= outerRadius ? M_PI_2 : asin(spaceBelow / outerRadius);
        CGFloat newLower = spaceAbove >= outerRadius ? -M_PI_2 : -asin(spaceAbove / outerRadius);
        if (newUpper < KSBallFanFlattenAngle) {
            newUpper = 0.0;
        }
        if (newLower > -KSBallFanFlattenAngle) {
            newLower = 0.0;
        }
        CGFloat missingSweep = KSBallFanMinimumSweep - (newUpper - newLower);
        if (missingSweep > 0.0) {
            // 上下空间都不足时，向空间较大的一侧补足张角。
            if (spaceBelow >= spaceAbove) {
                newUpper = MIN(M_PI_2, newUpper + missingSweep);
            } else {
                newLower = MAX(-M_PI_2, newLower - missingSweep);
            }
        }
        BOOL converged = fabs(newUpper - upperAngle) < 1e-4 && fabs(newLower - lowerAngle) < 1e-4;
        upperAngle = newUpper;
        lowerAngle = newLower;
        if (converged) {
            break;
        }
    }

    NSArray<NSNumber *> *ringCounts = ringCountsForSweep(upperAngle - lowerAngle);
    CGFloat outerRadius = firstRadius + step * (ringCounts.count - 1);
    // 张角总是包含水平方向，最远的图标位于圆心正内侧 outerRadius 处。
    BOOL fitsHorizontally = outerRadius <= CGRectGetWidth(safeBounds) - itemSize + 0.001;
    BOOL fitsVertically = outerRadius * sin(upperAngle) <= spaceBelow + 0.001 && outerRadius * sin(-lowerAngle) <= spaceAbove + 0.001;
    if (fits) {
        *fits = fitsHorizontally && fitsVertically;
    }

    NSMutableArray<NSValue *> *centers = [NSMutableArray arrayWithCapacity:count];
    CGFloat radius = firstRadius;
    for (NSNumber *ringCountValue in ringCounts) {
        NSUInteger ringCount = ringCountValue.unsignedIntegerValue;
        for (NSUInteger index = 0; index < ringCount; index++) {
            // 每圈都铺满整个张角，保持扇形轮廓；只有一个图标时放在张角中线上。
            CGFloat progress = ringCount == 1 ? 0.5 : (CGFloat)index / (CGFloat)(ringCount - 1);
            CGFloat angle = lowerAngle + (upperAngle - lowerAngle) * progress;
            [centers addObject:[NSValue valueWithCGPoint:CGPointMake(center.x + direction * cos(angle) * radius, center.y + sin(angle) * radius)]];
        }
        radius += step;
    }
    return centers;
}

@end
