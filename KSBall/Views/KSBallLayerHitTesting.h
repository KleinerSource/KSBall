#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

// 系统窗口托管按图层做命中测试：透明区域的触摸会直接落到下层应用。
// 热区需要按不透明处理；纯展示用的图层则不能拦截触摸。
static inline void KSBallSetLayerHitTestsAsOpaque(CALayer *layer, BOOL opaque) {
    SEL selector = NSSelectorFromString(@"setHitTestsAsOpaque:");
    if ([layer respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, selector, opaque);
    }
}

static inline void KSBallSetLayerAllowsHitTesting(CALayer *layer, BOOL allowsHitTesting) {
    SEL selector = NSSelectorFromString(@"setAllowsHitTesting:");
    if ([layer respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, selector, allowsHitTesting);
    }
    for (CALayer *sublayer in layer.sublayers) {
        KSBallSetLayerAllowsHitTesting(sublayer, allowsHitTesting);
    }
}
