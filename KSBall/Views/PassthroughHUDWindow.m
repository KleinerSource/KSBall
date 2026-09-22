#import "PassthroughHUDWindow.h"

@implementation PassthroughHUDWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    UIView *rootView = self.rootViewController.view;
    return hitView == self || hitView == rootView ? nil : hitView;
}

@end
