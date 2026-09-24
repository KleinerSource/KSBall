@import XCTest;

#import "KSBallFanLayout.h"
#import <math.h>

@interface KSBallFanLayoutTests : XCTestCase
@end

@implementation KSBallFanLayoutTests

- (CGRect)safeBounds {
    return CGRectMake(8.0, 50.0, 374.0, 710.0);
}

- (NSArray<NSValue *> *)centersForCount:(NSUInteger)count anchorY:(CGFloat)anchorY edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize itemSpacing:(CGFloat)itemSpacing ringSpacing:(CGFloat)ringSpacing scale:(CGFloat *)scale {
    // 与 FloatingHUDViewController 一致：把手距屏幕边缘 10pt。
    CGRect safeBounds = [self safeBounds];
    CGFloat anchorX = edge == KSBallEdgeLeft ? 12.0 : CGRectGetMaxX(safeBounds) + 8.0 - 12.0;
    return [KSBallFanLayout centersForItemCount:count anchorCenter:CGPointMake(anchorX, anchorY) safeBounds:safeBounds edge:edge itemSize:itemSize itemSpacing:itemSpacing ringSpacing:ringSpacing scale:scale];
}

- (NSArray<NSValue *> *)centersForCount:(NSUInteger)count anchorY:(CGFloat)anchorY edge:(KSBallEdge)edge {
    return [self centersForCount:count anchorY:anchorY edge:edge itemSize:50.0 itemSpacing:12.0 ringSpacing:12.0 scale:NULL];
}

- (void)testLayoutsStayInsideSafeBoundsWithConfiguredSpacing {
    CGRect safeBounds = [self safeBounds];
    NSArray<NSArray<NSNumber *> *> *metrics = @[@[@32, @0, @0], @[@40, @4, @20], @[@50, @12, @12], @[@64, @32, @4]];
    for (NSArray<NSNumber *> *metric in metrics) {
        CGFloat itemSize = metric[0].doubleValue;
        CGFloat itemSpacing = metric[1].doubleValue;
        CGFloat ringSpacing = metric[2].doubleValue;
        for (NSNumber *countValue in @[@1, @3, @8, @16, @48]) {
            for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
                for (NSNumber *anchorYValue in @[@20.0, @120.0, @405.0, @680.0, @800.0]) {
                    NSUInteger count = countValue.unsignedIntegerValue;
                    CGFloat scale = 0.0;
                    NSArray<NSValue *> *centers = [self centersForCount:count anchorY:anchorYValue.doubleValue edge:edgeValue.integerValue itemSize:itemSize itemSpacing:itemSpacing ringSpacing:ringSpacing scale:&scale];
                    XCTAssertEqual(centers.count, count);
                    XCTAssertGreaterThan(scale, 0.0);
                    XCTAssertLessThanOrEqual(scale, 1.0);
                    CGFloat itemRadius = itemSize * scale / 2.0;
                    for (NSValue *value in centers) {
                        CGPoint center = value.CGPointValue;
                        XCTAssertGreaterThanOrEqual(center.x - itemRadius, CGRectGetMinX(safeBounds) - 0.001);
                        XCTAssertLessThanOrEqual(center.x + itemRadius, CGRectGetMaxX(safeBounds) + 0.001);
                        XCTAssertGreaterThanOrEqual(center.y - itemRadius, CGRectGetMinY(safeBounds) - 0.001);
                        XCTAssertLessThanOrEqual(center.y + itemRadius, CGRectGetMaxY(safeBounds) + 0.001);
                    }
                    // 同圈间距与圈间距取较小者，任意两个图标都不会比它更近。
                    CGFloat minimumDistance = (itemSize + MIN(itemSpacing, ringSpacing)) * scale - 0.5;
                    for (NSUInteger left = 0; left < centers.count; left++) {
                        for (NSUInteger right = left + 1; right < centers.count; right++) {
                            CGPoint leftPoint = centers[left].CGPointValue;
                            CGPoint rightPoint = centers[right].CGPointValue;
                            XCTAssertGreaterThanOrEqual(hypot(leftPoint.x - rightPoint.x, leftPoint.y - rightPoint.y), minimumDistance);
                        }
                    }
                }
            }
        }
    }
}

- (void)testMiddlePositionOpensSymmetricHalfCircle {
    CGFloat middle = CGRectGetMidY([self safeBounds]);
    for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
        NSArray<NSValue *> *centers = [self centersForCount:8 anchorY:middle edge:edgeValue.integerValue];
        XCTAssertEqualWithAccuracy([self averageYOfCenters:centers], middle, 0.5);
        // 半圆两端的图标沿屏幕边缘排在把手正上方和正下方。
        CGFloat edgeColumnX = edgeValue.integerValue == KSBallEdgeLeft ? 33.0 : 357.0;
        NSUInteger edgeColumnCount = 0;
        for (NSValue *value in centers) {
            if (fabs(value.CGPointValue.x - edgeColumnX) < 0.5) {
                edgeColumnCount++;
            }
        }
        XCTAssertGreaterThanOrEqual(edgeColumnCount, 4);
    }
}

- (void)testRingsFollowVisibleSpaceNearEdges {
    CGRect safeBounds = [self safeBounds];
    // 把手离底部还有一点距离时，各圈只向下延伸到屏幕可显示的位置，不强制排成水平一行。
    CGFloat anchorY = CGRectGetMaxY(safeBounds) - 60.0;
    for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
        NSArray<NSValue *> *centers = [self centersForCount:16 anchorY:anchorY edge:edgeValue.integerValue];
        CGFloat lowestY = -CGFLOAT_MAX;
        for (NSValue *value in centers) {
            lowestY = MAX(lowestY, value.CGPointValue.y);
        }
        XCTAssertGreaterThan(lowestY, anchorY + 1.0);
        XCTAssertLessThanOrEqual(lowestY + 25.0, CGRectGetMaxY(safeBounds) + 0.001);
    }
}

- (void)testDirectionFollowsAvailableSpace {
    for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
        KSBallEdge edge = edgeValue.integerValue;
        XCTAssertGreaterThan([self averageYOfCenters:[self centersForCount:8 anchorY:120.0 edge:edge]], 120.0);
        XCTAssertLessThan([self averageYOfCenters:[self centersForCount:8 anchorY:680.0 edge:edge]], 680.0);
    }
}

- (void)testRingCapacitiesGrowByTwoPerQuarter {
    CGRect safeBounds = [self safeBounds];
    // 右下角为四分之一圆：40pt 图标、8pt 间距时依次为 3、5、7。
    CGFloat scale = 0.0;
    NSArray<NSValue *> *cornerCenters = [self centersForCount:15 anchorY:800.0 edge:KSBallEdgeRight itemSize:40.0 itemSpacing:8.0 ringSpacing:8.0 scale:&scale];
    XCTAssertEqualWithAccuracy(scale, 1.0, 0.001);
    CGPoint cornerCenter = CGPointMake(CGRectGetMaxX(safeBounds) - 20.0, CGRectGetMaxY(safeBounds) - 20.0);
    XCTAssertEqualObjects([self ringSizesOfCenters:cornerCenters aroundCenter:cornerCenter], (@[@3, @5, @7]));

    // 屏幕中部为半圆，每圈容量为四分之一圆的两倍：5、9。
    CGFloat middle = CGRectGetMidY(safeBounds);
    NSArray<NSValue *> *middleCenters = [self centersForCount:14 anchorY:middle edge:KSBallEdgeLeft itemSize:40.0 itemSpacing:8.0 ringSpacing:8.0 scale:&scale];
    XCTAssertEqualWithAccuracy(scale, 1.0, 0.001);
    CGPoint middleCenter = CGPointMake(CGRectGetMinX(safeBounds) + 20.0, middle);
    XCTAssertEqualObjects([self ringSizesOfCenters:middleCenters aroundCenter:middleCenter], (@[@5, @9]));
}

- (void)testRingSpacingIsIndependentOfItemSpacing {
    CGRect safeBounds = [self safeBounds];
    CGFloat middle = CGRectGetMidY(safeBounds);
    CGPoint center = CGPointMake(CGRectGetMinX(safeBounds) + 20.0, middle);
    // 圈间距足够大时不需要外推，第二圈半径正好比内圈多出一个图标尺寸加圈间距。
    NSArray<NSValue *> *centers = [self centersForCount:14 anchorY:middle edge:KSBallEdgeLeft itemSize:40.0 itemSpacing:8.0 ringSpacing:30.0 scale:NULL];
    CGPoint inner = centers.firstObject.CGPointValue;
    CGPoint outer = centers[5].CGPointValue;
    XCTAssertEqualWithAccuracy(hypot(outer.x - center.x, outer.y - center.y) - hypot(inner.x - center.x, inner.y - center.y), 70.0, 0.01);
}

- (NSArray<NSNumber *> *)ringSizesOfCenters:(NSArray<NSValue *> *)centers aroundCenter:(CGPoint)center {
    NSMutableArray<NSNumber *> *sizes = [NSMutableArray array];
    CGFloat currentRadius = -1.0;
    for (NSValue *value in centers) {
        CGPoint point = value.CGPointValue;
        CGFloat radius = hypot(point.x - center.x, point.y - center.y);
        if (fabs(radius - currentRadius) > 0.5) {
            [sizes addObject:@1];
            currentRadius = radius;
        } else {
            sizes[sizes.count - 1] = @(sizes.lastObject.unsignedIntegerValue + 1);
        }
    }
    return sizes;
}

- (CGFloat)averageYOfCenters:(NSArray<NSValue *> *)centers {
    CGFloat total = 0.0;
    for (NSValue *value in centers) {
        total += value.CGPointValue.y;
    }
    return centers.count > 0 ? total / centers.count : 0.0;
}

@end
