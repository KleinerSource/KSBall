@import XCTest;

#import "KSBallFanLayout.h"
#import <math.h>

@interface KSBallFanLayoutTests : XCTestCase
@end

@implementation KSBallFanLayoutTests

- (void)testLayoutsStayInsideSafeBoundsWithoutCrowding {
    CGRect safeBounds = CGRectMake(8.0, 50.0, 374.0, 710.0);
    for (NSNumber *countValue in @[@1, @8, @9, @16]) {
        NSUInteger count = countValue.unsignedIntegerValue;
        for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
            for (NSNumber *biasValue in @[@(KSBallFanBiasUpper), @(KSBallFanBiasCenter), @(KSBallFanBiasLower)]) {
                CGPoint anchor = CGPointMake(edgeValue.integerValue == KSBallEdgeLeft ? 36.0 : 354.0, 405.0);
                NSArray<NSValue *> *centers = [KSBallFanLayout centersForItemCount:count anchorCenter:anchor safeBounds:safeBounds edge:edgeValue.integerValue bias:biasValue.integerValue];
                XCTAssertEqual(centers.count, count);
                for (NSValue *value in centers) {
                    CGPoint center = value.CGPointValue;
                    XCTAssertGreaterThanOrEqual(center.x - 25.0, CGRectGetMinX(safeBounds));
                    XCTAssertLessThanOrEqual(center.x + 25.0, CGRectGetMaxX(safeBounds));
                    XCTAssertGreaterThanOrEqual(center.y - 25.0, CGRectGetMinY(safeBounds));
                    XCTAssertLessThanOrEqual(center.y + 25.0, CGRectGetMaxY(safeBounds));
                }
                for (NSUInteger left = 0; left < centers.count; left++) {
                    for (NSUInteger right = left + 1; right < centers.count; right++) {
                        CGPoint leftPoint = centers[left].CGPointValue;
                        CGPoint rightPoint = centers[right].CGPointValue;
                        CGFloat distance = hypot(leftPoint.x - rightPoint.x, leftPoint.y - rightPoint.y);
                        XCTAssertGreaterThanOrEqual(distance, 48.0);
                    }
                }
            }
        }
    }
}

@end
