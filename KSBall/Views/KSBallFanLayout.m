#import "KSBallFanLayout.h"
#import <math.h>

// 第一圈图标到扇形圆心（把手）的最小距离：半个把手高度加上手指离开把手所需的余量。
static const CGFloat KSBallFanHandleClearance = 30.0;
// 扇形张角至少保持四分之一圆。
static const CGFloat KSBallFanMinimumSweep = M_PI_2;
// 小于约 8° 的倾角直接拉平，让贴近屏幕上下边缘的一排图标整齐排成一行。
static const CGFloat KSBallFanFlattenAngle = 0.14;
static const CGFloat KSBallFanShrinkFactor = 0.9;
// 48 个图标挤在角落时需要缩得更多：0.9^16 ≈ 0.19。
static const NSUInteger KSBallFanMaximumShrinkAttempts = 16;

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
    // 圆心放在贴边的那一列图标上，使正上/正下方向的图标恰好沿屏幕边缘排成一列。
    CGFloat minimumCenterY = CGRectGetMinY(safeBounds) + itemRadius;
    CGFloat maximumCenterY = MAX(CGRectGetMaxY(safeBounds) - itemRadius, minimumCenterY);
    CGPoint center = CGPointMake(edge == KSBallEdgeLeft ? CGRectGetMinX(safeBounds) + itemRadius : CGRectGetMaxX(safeBounds) - itemRadius,
                                 MIN(MAX(anchorCenter.y, minimumCenterY), maximumCenterY));
    CGFloat spaceAbove = center.y - minimumCenterY;
    CGFloat spaceBelow = maximumCenterY - center.y;

    // 各圈半径只取决于图标尺寸与间距，拖动悬浮条时圈的位置保持稳定：
    // 第一圈刚好能在四分之一圆上并排 3 个图标（半圆约 5 个），且不压到把手；之后每圈向外推一个 step。
    const CGFloat firstRadius = MAX(itemRadius + KSBallFanHandleClearance, step / (2.0 * sin(M_PI / 8.0)));
    // 每圈能放多少个图标由弧长决定：相邻图标弦长不小于 step，张角受屏幕上下边界限制，
    // 因此图标越小、间距越小、可用张角越大，每圈放得越多。
    void (^computeRings)(CGFloat, NSMutableArray<NSNumber *> *, NSMutableArray<NSNumber *> *) = ^(CGFloat sweep, NSMutableArray<NSNumber *> *counts, NSMutableArray<NSNumber *> *radii) {
        [counts removeAllObjects];
        [radii removeAllObjects];
        NSUInteger remaining = count;
        CGFloat radius = firstRadius;
        while (remaining > 0) {
            CGFloat angleStep = 2.0 * asin(MIN(1.0, step / (radius * 2.0)));
            NSUInteger capacity = (NSUInteger)floor(sweep / angleStep + 1e-6) + 1;
            NSUInteger ringCount = MIN(capacity, remaining);
            [counts addObject:@(ringCount)];
            [radii addObject:@(radius)];
            remaining -= ringCount;
            radius += step;
        }
    };
    NSMutableArray<NSNumber *> *ringCounts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *ringRadii = [NSMutableArray array];

    // 角度相对“指向屏幕内侧的水平方向”，正值向下。先按半圆排布，再根据外圈半径收窄张角，迭代几次即可收敛。
    CGFloat lowerAngle = -M_PI_2;
    CGFloat upperAngle = M_PI_2;
    for (NSUInteger iteration = 0; iteration < 6; iteration++) {
        computeRings(upperAngle - lowerAngle, ringCounts, ringRadii);
        CGFloat outerRadius = ringRadii.lastObject.doubleValue;
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

    computeRings(upperAngle - lowerAngle, ringCounts, ringRadii);
    CGFloat outerRadius = ringRadii.lastObject.doubleValue;
    // 张角总是包含水平方向，最远的图标位于圆心正内侧 outerRadius 处。
    BOOL fitsHorizontally = outerRadius <= CGRectGetWidth(safeBounds) - itemSize + 0.001;
    BOOL fitsVertically = outerRadius * sin(upperAngle) <= spaceBelow + 0.001 && outerRadius * sin(-lowerAngle) <= spaceAbove + 0.001;
    if (fits) {
        *fits = fitsHorizontally && fitsVertically;
    }

    NSMutableArray<NSValue *> *centers = [NSMutableArray arrayWithCapacity:count];
    [ringCounts enumerateObjectsUsingBlock:^(NSNumber * _Nonnull ringCountValue, NSUInteger ring, BOOL * _Nonnull stop) {
        NSUInteger ringCount = ringCountValue.unsignedIntegerValue;
        CGFloat radius = ringRadii[ring].doubleValue;
        for (NSUInteger index = 0; index < ringCount; index++) {
            // 每圈都铺满整个张角，保持扇形轮廓；只有一个图标时放在张角中线上。
            CGFloat progress = ringCount == 1 ? 0.5 : (CGFloat)index / (CGFloat)(ringCount - 1);
            CGFloat angle = lowerAngle + (upperAngle - lowerAngle) * progress;
            [centers addObject:[NSValue valueWithCGPoint:CGPointMake(center.x + direction * cos(angle) * radius, center.y + sin(angle) * radius)]];
        }
    }];
    return centers;
}

@end
