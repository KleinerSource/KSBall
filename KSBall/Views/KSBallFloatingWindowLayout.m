#import "KSBallFloatingWindowLayout.h"
#import <math.h>

const NSUInteger KSBallMaximumFloatingWindows = 3;
const CGFloat KSBallFloatingWindowDefaultScale = 0.8;
const CGFloat KSBallFloatingWindowMinimumScale = 0.35;
const CGFloat KSBallFloatingWindowMaximumScale = 0.9;
const CGFloat KSBallFloatingWindowThumbnailScale = 0.16;
const CGFloat KSBallFloatingWindowTitleBarHeight = 28.0;
const CGFloat KSBallFloatingWindowCornerRadius = 18.0;
const CGFloat KSBallFloatingWindowThumbnailCornerRadius = 10.0;
const CGFloat KSBallFloatingDockPadding = 6.0;
static const CGFloat KSBallFloatingWindowCascadeOffset = 24.0;
static const CGFloat KSBallFloatingMinimizeOverhangRatio = 0.35;
// 收纳区缩略图与屏幕边缘、安全区顶部以及彼此之间的距离。
static const CGFloat KSBallFloatingDockEdgeInset = 8.0;
static const CGFloat KSBallFloatingDockTopInset = 12.0;
static const CGFloat KSBallFloatingDockSpacing = 10.0;

@implementation KSBallFloatingWindowLayout

+ (CGFloat)clampedScale:(CGFloat)scale {
    if (!isfinite(scale)) {
        return KSBallFloatingWindowDefaultScale;
    }
    return MIN(MAX(scale, KSBallFloatingWindowMinimumScale), KSBallFloatingWindowMaximumScale);
}

+ (CGSize)windowSizeForScale:(CGFloat)scale screenSize:(CGSize)screenSize {
    CGFloat clampedScale = [self clampedScale:scale];
    return CGSizeMake(round(screenSize.width * clampedScale), round(screenSize.height * clampedScale) + KSBallFloatingWindowTitleBarHeight);
}

+ (CGFloat)scaleForWindowWidth:(CGFloat)width screenSize:(CGSize)screenSize {
    if (screenSize.width <= 0.0) {
        return KSBallFloatingWindowDefaultScale;
    }
    return [self clampedScale:width / screenSize.width];
}

+ (CGSize)thumbnailSizeForScreenSize:(CGSize)screenSize {
    return CGSizeMake(round(screenSize.width * KSBallFloatingWindowThumbnailScale), round(screenSize.height * KSBallFloatingWindowThumbnailScale));
}

+ (CGRect)safeBoundsForBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    return UIEdgeInsetsInsetRect(bounds, safeAreaInsets);
}

+ (CGRect)defaultFrameForIndex:(NSUInteger)index scale:(CGFloat)scale screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    CGSize size = [self windowSizeForScale:scale screenSize:screenSize];
    CGRect safeBounds = [self safeBoundsForBounds:bounds safeAreaInsets:safeAreaInsets];
    CGFloat offset = KSBallFloatingWindowCascadeOffset * index;
    CGRect frame = CGRectMake(CGRectGetMidX(safeBounds) - size.width / 2.0 + offset, CGRectGetMidY(safeBounds) - size.height / 2.0 + offset, size.width, size.height);
    return [self clampedFrame:frame inBounds:bounds safeAreaInsets:safeAreaInsets];
}

+ (CGRect)clampedFrame:(CGRect)frame inBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    CGRect safeBounds = [self safeBoundsForBounds:bounds safeAreaInsets:safeAreaInsets];
    CGFloat minX = CGRectGetMinX(bounds);
    CGFloat maxX = MAX(minX, CGRectGetMaxX(bounds) - CGRectGetWidth(frame));
    CGFloat minY = CGRectGetMinY(safeBounds);
    CGFloat maxY = MAX(minY, CGRectGetMaxY(safeBounds) - CGRectGetHeight(frame));
    frame.origin.x = MIN(MAX(CGRectGetMinX(frame), minX), maxX);
    frame.origin.y = MIN(MAX(CGRectGetMinY(frame), minY), maxY);
    return frame;
}

+ (BOOL)shouldMinimizeFrame:(CGRect)frame inBounds:(CGRect)bounds edge:(KSBallEdge *)edge {
    CGFloat threshold = CGRectGetWidth(frame) * KSBallFloatingMinimizeOverhangRatio;
    CGFloat leftOverhang = CGRectGetMinX(bounds) - CGRectGetMinX(frame);
    CGFloat rightOverhang = CGRectGetMaxX(frame) - CGRectGetMaxX(bounds);
    if (leftOverhang <= threshold && rightOverhang <= threshold) {
        return NO;
    }
    if (edge) {
        *edge = leftOverhang > rightOverhang ? KSBallEdgeLeft : KSBallEdgeRight;
    }
    return YES;
}

+ (CGRect)dockSlotFrameAtIndex:(NSUInteger)index edge:(KSBallEdge)edge screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    CGSize size = [self thumbnailSizeForScreenSize:screenSize];
    CGRect safeBounds = [self safeBoundsForBounds:bounds safeAreaInsets:safeAreaInsets];
    CGFloat x = edge == KSBallEdgeLeft ? CGRectGetMinX(bounds) + KSBallFloatingDockEdgeInset : CGRectGetMaxX(bounds) - KSBallFloatingDockEdgeInset - size.width;
    CGFloat y = CGRectGetMinY(safeBounds) + KSBallFloatingDockTopInset + index * (size.height + KSBallFloatingDockSpacing);
    return CGRectMake(x, y, size.width, size.height);
}

+ (CGRect)dockPlateFrameForCount:(NSUInteger)count edge:(KSBallEdge)edge screenSize:(CGSize)screenSize bounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    if (count == 0) {
        return CGRectZero;
    }
    CGRect first = [self dockSlotFrameAtIndex:0 edge:edge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
    CGRect last = [self dockSlotFrameAtIndex:count - 1 edge:edge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
    return CGRectInset(CGRectUnion(first, last), -KSBallFloatingDockPadding, -KSBallFloatingDockPadding);
}

@end
