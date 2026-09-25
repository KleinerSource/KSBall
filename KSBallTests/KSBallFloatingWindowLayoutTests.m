@import XCTest;

#import "KSBallFloatingWindowLayout.h"

@interface KSBallFloatingWindowLayoutTests : XCTestCase
@end

@implementation KSBallFloatingWindowLayoutTests

static const CGSize KSBallTestScreenSize = {390.0, 844.0};
static const CGRect KSBallTestBounds = {{0.0, 0.0}, {390.0, 844.0}};
static const UIEdgeInsets KSBallTestSafeAreaInsets = {47.0, 0.0, 34.0, 0.0};

- (void)testScaleIsClamped {
    XCTAssertEqualWithAccuracy([KSBallFloatingWindowLayout clampedScale:0.1], KSBallFloatingWindowMinimumScale, 0.0001);
    XCTAssertEqualWithAccuracy([KSBallFloatingWindowLayout clampedScale:2.0], KSBallFloatingWindowMaximumScale, 0.0001);
    XCTAssertEqualWithAccuracy([KSBallFloatingWindowLayout clampedScale:NAN], KSBallFloatingWindowDefaultScale, 0.0001);
    XCTAssertEqualWithAccuracy([KSBallFloatingWindowLayout scaleForWindowWidth:1000.0 screenSize:KSBallTestScreenSize], KSBallFloatingWindowMaximumScale, 0.0001);
}

- (void)testWindowKeepsScreenAspectRatioBelowTitleBar {
    for (NSNumber *scale in @[@0.35, @0.5, @0.8, @0.9]) {
        CGSize size = [KSBallFloatingWindowLayout windowSizeForScale:scale.doubleValue screenSize:KSBallTestScreenSize];
        CGFloat contentHeight = size.height - KSBallFloatingWindowTitleBarHeight;
        XCTAssertEqualWithAccuracy(size.width / contentHeight, KSBallTestScreenSize.width / KSBallTestScreenSize.height, 0.01);
        XCTAssertEqualWithAccuracy([KSBallFloatingWindowLayout scaleForWindowWidth:size.width screenSize:KSBallTestScreenSize], scale.doubleValue, 0.01);
    }
}

- (void)testClampedFrameKeepsWindowInsideSafeArea {
    CGSize size = [KSBallFloatingWindowLayout windowSizeForScale:0.5 screenSize:KSBallTestScreenSize];
    CGRect offscreen = CGRectMake(-300.0, 900.0, size.width, size.height);
    CGRect clamped = [KSBallFloatingWindowLayout clampedFrame:offscreen inBounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets];
    XCTAssertGreaterThanOrEqual(CGRectGetMinX(clamped), 0.0);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(clamped), CGRectGetHeight(KSBallTestBounds) - KSBallTestSafeAreaInsets.bottom + 0.001);

    CGRect aboveTop = [KSBallFloatingWindowLayout clampedFrame:CGRectMake(20.0, -200.0, size.width, size.height) inBounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(aboveTop), KSBallTestSafeAreaInsets.top, 0.001);
}

- (void)testTallWindowIsPinnedBelowSafeAreaTop {
    // 最大比例下窗口比安全区更高，此时标题条必须贴住安全区顶部而不是被推出屏幕。
    CGSize size = [KSBallFloatingWindowLayout windowSizeForScale:KSBallFloatingWindowMaximumScale screenSize:KSBallTestScreenSize];
    XCTAssertGreaterThan(size.height, CGRectGetHeight(KSBallTestBounds) - KSBallTestSafeAreaInsets.top - KSBallTestSafeAreaInsets.bottom);
    CGRect clamped = [KSBallFloatingWindowLayout clampedFrame:CGRectMake(0.0, 400.0, size.width, size.height) inBounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets];
    XCTAssertEqualWithAccuracy(CGRectGetMinY(clamped), KSBallTestSafeAreaInsets.top, 0.001);
}

- (void)testDefaultFramesCascadeInsideSafeArea {
    CGRect previous = CGRectNull;
    for (NSUInteger index = 0; index < KSBallMaximumFloatingWindows; index++) {
        CGRect frame = [KSBallFloatingWindowLayout defaultFrameForIndex:index scale:KSBallFloatingWindowDefaultScale screenSize:KSBallTestScreenSize bounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets];
        XCTAssertGreaterThanOrEqual(CGRectGetMinY(frame), KSBallTestSafeAreaInsets.top - 0.001);
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(frame), 0.0);
        XCTAssertLessThanOrEqual(CGRectGetMaxX(frame), CGRectGetWidth(KSBallTestBounds) + 0.001);
        if (!CGRectIsNull(previous)) {
            XCTAssertFalse(CGPointEqualToPoint(frame.origin, previous.origin));
        }
        previous = frame;
    }
}

- (void)testMinimizeRequiresDraggingPastEdge {
    CGSize size = [KSBallFloatingWindowLayout windowSizeForScale:0.5 screenSize:KSBallTestScreenSize];
    KSBallEdge edge = KSBallEdgeLeft;
    CGRect slightlyOut = CGRectMake(CGRectGetWidth(KSBallTestBounds) - size.width + size.width * 0.2, 200.0, size.width, size.height);
    XCTAssertFalse([KSBallFloatingWindowLayout shouldMinimizeFrame:slightlyOut inBounds:KSBallTestBounds edge:&edge]);

    CGRect farRight = CGRectMake(CGRectGetWidth(KSBallTestBounds) - size.width * 0.5, 200.0, size.width, size.height);
    XCTAssertTrue([KSBallFloatingWindowLayout shouldMinimizeFrame:farRight inBounds:KSBallTestBounds edge:&edge]);
    XCTAssertEqual(edge, KSBallEdgeRight);

    CGRect farLeft = CGRectMake(-size.width * 0.5, 200.0, size.width, size.height);
    XCTAssertTrue([KSBallFloatingWindowLayout shouldMinimizeFrame:farLeft inBounds:KSBallTestBounds edge:&edge]);
    XCTAssertEqual(edge, KSBallEdgeLeft);
}

- (void)testDockSlotsStackWithoutOverlapInsidePlate {
    for (NSNumber *edgeValue in @[@(KSBallEdgeLeft), @(KSBallEdgeRight)]) {
        KSBallEdge edge = edgeValue.integerValue;
        CGRect plate = [KSBallFloatingWindowLayout dockPlateFrameForCount:KSBallMaximumFloatingWindows edge:edge screenSize:KSBallTestScreenSize bounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets];
        XCTAssertTrue(CGRectContainsRect(KSBallTestBounds, plate));
        CGRect previous = CGRectNull;
        for (NSUInteger index = 0; index < KSBallMaximumFloatingWindows; index++) {
            CGRect slot = [KSBallFloatingWindowLayout dockSlotFrameAtIndex:index edge:edge screenSize:KSBallTestScreenSize bounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets];
            XCTAssertGreaterThanOrEqual(CGRectGetMinY(slot), KSBallTestSafeAreaInsets.top);
            XCTAssertTrue(CGRectContainsRect(plate, slot));
            if (!CGRectIsNull(previous)) {
                XCTAssertFalse(CGRectIntersectsRect(previous, slot));
            }
            previous = slot;
        }
    }
    XCTAssertTrue(CGRectEqualToRect([KSBallFloatingWindowLayout dockPlateFrameForCount:0 edge:KSBallEdgeRight screenSize:KSBallTestScreenSize bounds:KSBallTestBounds safeAreaInsets:KSBallTestSafeAreaInsets], CGRectZero));
}

@end
