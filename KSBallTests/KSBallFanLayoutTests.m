@import XCTest;

#import "KSBallFanLayout.h"
#import <math.h>

@interface KSBallFanLayoutTests : XCTestCase
@end

@implementation KSBallFanLayoutTests

- (NSArray<NSValue *> *)centersForCount:(NSUInteger)count anchorY:(CGFloat)anchorY edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize spacing:(CGFloat)spacing {
    return [self centersForCount:count anchorY:anchorY edge:edge itemSize:itemSize spacing:spacing scale:NULL];
}

- (NSArray<NSValue *> *)centersForCount:(NSUInteger)count anchorY:(CGFloat)anchorY edge:(KSBallEdge)edge itemSize:(CGFloat)itemSize spacing:(CGFloat)spacing scale:(CGFloat *)scale {
    // 与 FloatingHUDViewController 一致：把手距屏幕边缘 10pt。
    CGRect safeBounds = [self safeBounds];
    CGFloat anchorX = edge == KSBallEdgeLeft ? 12.0 : CGRectGetMaxX(safeBounds) + 8.0 - 12.0;
    return [KSBallFanLayout centersForItemCount:count anchorCenter:CGPointMake(anchorX, anchorY) safeBounds:safeBounds edge:edge itemSize:itemSize spacing:spacing scale:scale];
}

- (CGRect)safeBounds {
    return CGRectMake(8.0, 50.0, 374.0, 710.0);
}

- (void)testLayoutsStayInsideSafeBoundsWithConfiguredSpacing {
    CGRect safeBounds = [self safeBounds];
    NSArray<NSArray<NSNumber *> *> *metrics = @[@[@32, @4], @[@40, @4], @[@50, @12], @[@64, @16]];
    for (NSArray<NSNumber *> *metric in metrics) {
        CGFloat itemSize = metric[0].doubleValue;
        CGFloat spacing = metric[1].doubleValue;
        for (NSNumber *countValue in @[@1, @3, @8, @16, @48]) {
            for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
                for (NSNumber *anchorYValue in @[@20.0, @120.0, @405.0, @680.0, @800.0]) {
                    NSUInteger count = countValue.unsignedIntegerValue;
                    CGFloat scale = 0.0;
                    NSArray<NSValue *> *centers = [self centersForCount:count anchorY:anchorYValue.doubleValue edge:edgeValue.integerValue itemSize:itemSize spacing:spacing scale:&scale];
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
                    for (NSUInteger left = 0; left < centers.count; left++) {
                        for (NSUInteger right = left + 1; right < centers.count; right++) {
                            CGPoint leftPoint = centers[left].CGPointValue;
                            CGPoint rightPoint = centers[right].CGPointValue;
                            XCTAssertGreaterThanOrEqual(hypot(leftPoint.x - rightPoint.x, leftPoint.y - rightPoint.y), (itemSize + spacing) * scale - 0.5);
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
        NSArray<NSValue *> *centers = [self centersForCount:8 anchorY:middle edge:edgeValue.integerValue itemSize:50.0 spacing:12.0];
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

- (void)testCornerPositionsOpenQuarterCircleWithFlatOuterRow {
    CGRect safeBounds = [self safeBounds];
    for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
        NSArray<NSValue *> *bottomCenters = [self centersForCount:8 anchorY:800.0 edge:edgeValue.integerValue itemSize:50.0 spacing:12.0];
        CGFloat bottomRowY = CGRectGetMaxY(safeBounds) - 25.0;
        NSUInteger bottomRowCount = 0;
        for (NSValue *value in bottomCenters) {
            XCTAssertLessThanOrEqual(value.CGPointValue.y, bottomRowY + 0.001);
            if (fabs(value.CGPointValue.y - bottomRowY) < 0.5) {
                bottomRowCount++;
            }
        }
        XCTAssertGreaterThanOrEqual(bottomRowCount, 2);

        NSArray<NSValue *> *topCenters = [self centersForCount:8 anchorY:20.0 edge:edgeValue.integerValue itemSize:50.0 spacing:12.0];
        CGFloat topRowY = CGRectGetMinY(safeBounds) + 25.0;
        NSUInteger topRowCount = 0;
        for (NSValue *value in topCenters) {
            XCTAssertGreaterThanOrEqual(value.CGPointValue.y, topRowY - 0.001);
            if (fabs(value.CGPointValue.y - topRowY) < 0.5) {
                topRowCount++;
            }
        }
        XCTAssertGreaterThanOrEqual(topRowCount, 2);
    }
}

- (void)testDirectionFollowsAvailableSpace {
    for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
        KSBallEdge edge = edgeValue.integerValue;
        XCTAssertGreaterThan([self averageYOfCenters:[self centersForCount:8 anchorY:120.0 edge:edge itemSize:50.0 spacing:12.0]], 120.0);
        XCTAssertLessThan([self averageYOfCenters:[self centersForCount:8 anchorY:680.0 edge:edge itemSize:50.0 spacing:12.0]], 680.0);
    }
}

- (void)testRingCapacitiesFollowAvailableArc {
    CGRect safeBounds = [self safeBounds];
    // 右下角为四分之一圆：内圈 3 个，外圈按弧长逐圈增多（40pt 图标、8pt 间距时为 3、4、6）。
    CGFloat scale = 0.0;
    NSArray<NSValue *> *cornerCenters = [self centersForCount:15 anchorY:800.0 edge:KSBallEdgeRight itemSize:40.0 spacing:8.0 scale:&scale];
    XCTAssertEqualWithAccuracy(scale, 1.0, 0.001);
    CGPoint cornerCenter = CGPointMake(CGRectGetMaxX(safeBounds) - 20.0, CGRectGetMaxY(safeBounds) - 20.0);
    XCTAssertEqualObjects([self ringSizesOfCenters:cornerCenters aroundCenter:cornerCenter], (@[@3, @4, @6, @2]));

    // 屏幕中部为半圆，同样的半径下每圈容量约为四分之一圆的两倍。
    CGFloat middle = CGRectGetMidY(safeBounds);
    NSArray<NSValue *> *middleCenters = [self centersForCount:14 anchorY:middle edge:KSBallEdgeLeft itemSize:40.0 spacing:8.0 scale:&scale];
    XCTAssertEqualWithAccuracy(scale, 1.0, 0.001);
    CGPoint middleCenter = CGPointMake(CGRectGetMinX(safeBounds) + 20.0, middle);
    XCTAssertEqualObjects([self ringSizesOfCenters:middleCenters aroundCenter:middleCenter], (@[@5, @8, @1]));
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
