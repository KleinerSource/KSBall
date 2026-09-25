#import "PassthroughHUDWindow.h"

@implementation PassthroughHUDWindow

+ (BOOL)_isSystemWindow {
    return YES;
}

- (BOOL)_isWindowServerHostingManaged {
    return NO;
}

- (BOOL)_ignoresHitTest {
    return NO;
}

- (BOOL)_isSecure {
    return YES;
}

- (BOOL)_shouldCreateContextAsSecure {
    return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    UIView *rootView = self.rootViewController.view;
    return hitView == self || hitView == rootView ? nil : hitView;
}

@end
