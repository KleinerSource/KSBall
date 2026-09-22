#import <UIKit/UIKit.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

@interface KSBallFanLayout : NSObject

+ (NSArray<NSValue *> *)centersForItemCount:(NSUInteger)itemCount
                               anchorCenter:(CGPoint)anchorCenter
                                 safeBounds:(CGRect)safeBounds
                                       edge:(KSBallEdge)edge
                                       bias:(KSBallFanBias)bias;

@end

NS_ASSUME_NONNULL_END
