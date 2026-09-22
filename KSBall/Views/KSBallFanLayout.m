#import "KSBallFanLayout.h"

@implementation KSBallFanLayout

+ (NSArray<NSValue *> *)centersForItemCount:(NSUInteger)itemCount anchorCenter:(CGPoint)anchorCenter safeBounds:(CGRect)safeBounds edge:(KSBallEdge)edge bias:(KSBallFanBias)bias {
    NSUInteger visibleCount = MIN(itemCount, KSBallMaximumShortcuts);
    if (visibleCount == 0) {
        return @[];
    }

    const CGFloat buttonRadius = 25.0;
    const CGFloat span = 2.14;
    const CGFloat baseAngle = edge == KSBallEdgeLeft ? 0.0 : M_PI;
    const CGFloat biasOffset = bias * 0.42;
    CGFloat scale = MIN(1.0, MAX(0.68, (CGRectGetHeight(safeBounds) - buttonRadius * 2.0) / 420.0));
    CGFloat radii[] = { 168.0 * scale, 232.0 * scale };

    NSMutableArray<NSValue *> *rawCenters = [NSMutableArray arrayWithCapacity:visibleCount];
    for (NSUInteger index = 0; index < visibleCount; index++) {
        NSUInteger layer = index / 8;
        NSUInteger layerStart = layer * 8;
        NSUInteger itemsInLayer = MIN((NSUInteger)8, visibleCount - layerStart);
        NSUInteger layerIndex = index - layerStart;
        CGFloat offset = itemsInLayer == 1 ? 0.0 : (-span / 2.0 + span * layerIndex / (itemsInLayer - 1));
        CGFloat angle = baseAngle + biasOffset + offset;
        CGPoint point = CGPointMake(anchorCenter.x + cos(angle) * radii[layer], anchorCenter.y + sin(angle) * radii[layer]);
        [rawCenters addObject:[NSValue valueWithCGPoint:point]];
    }

    CGFloat minimumY = CGFLOAT_MAX;
    CGFloat maximumY = -CGFLOAT_MAX;
    for (NSValue *value in rawCenters) {
        CGPoint point = value.CGPointValue;
        minimumY = MIN(minimumY, point.y - buttonRadius);
        maximumY = MAX(maximumY, point.y + buttonRadius);
    }
    CGFloat lowerTranslation = CGRectGetMinY(safeBounds) - minimumY;
    CGFloat upperTranslation = CGRectGetMaxY(safeBounds) - maximumY;
    CGFloat translationY = MIN(MAX(0.0, lowerTranslation), upperTranslation);

    NSMutableArray<NSValue *> *centers = [NSMutableArray arrayWithCapacity:rawCenters.count];
    for (NSValue *value in rawCenters) {
        CGPoint point = value.CGPointValue;
        point.y += translationY;
        point.x = MIN(MAX(point.x, CGRectGetMinX(safeBounds) + buttonRadius), CGRectGetMaxX(safeBounds) - buttonRadius);
        [centers addObject:[NSValue valueWithCGPoint:point]];
    }
    return centers;
}

@end
