#import "FloatingAppWindowView.h"
#import "KSBallFloatingWindowLayout.h"
#import "KSBallLayerHitTesting.h"
#import <math.h>

static const CGFloat KSBallFloatingButtonSize = 28.0;
static const CGFloat KSBallFloatingResizeHandleSize = 28.0;
static const CGFloat KSBallFloatingPlaceholderIconSize = 56.0;
static const CGFloat KSBallFloatingBadgeIconSize = 22.0;
// 收纳区缩略图向外甩出超过该距离或速度时收起整个边栏。
static const CGFloat KSBallFloatingDockCollapseDistance = 44.0;
static const CGFloat KSBallFloatingDockCollapseVelocity = 600.0;

@interface FloatingAppWindowView ()
@property (nonatomic, readwrite) CGSize screenSize;
@property (nonatomic, strong) UIView *clipView;
@property (nonatomic, strong) UIView *titleBarView;
@property (nonatomic, strong) UIView *grabberView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *minimizeButton;
@property (nonatomic, strong) UIButton *fullScreenButton;
@property (nonatomic, strong) UIView *contentView;
// 锚点在左上角的缩放层：边界等于屏幕尺寸，按窗口宽度整体缩小。
@property (nonatomic, strong) UIView *scalingView;
@property (nonatomic, strong, nullable) UIView *presentationView;
@property (nonatomic, strong) UIView *placeholderView;
@property (nonatomic, strong) UIImageView *placeholderIconView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *resizeHandleView;
@property (nonatomic, strong) CAShapeLayer *resizeIndicatorLayer;
@property (nonatomic, strong) UIView *minimizedOverlayView;
@property (nonatomic, strong) UIImageView *badgeIconView;
@property (nonatomic) CGFloat resizeStartWidth;
@property (nonatomic) CGFloat resizeStartContentHeight;
@end

@implementation FloatingAppWindowView

- (instancetype)initWithDisplayName:(NSString *)displayName icon:(UIImage *)icon screenSize:(CGSize)screenSize {
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return nil;
    }
    _screenSize = screenSize;
    _minimizedEdge = KSBallEdgeRight;
    self.accessibilityLabel = displayName;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.28;
    self.layer.shadowRadius = 18.0;
    self.layer.shadowOffset = CGSizeMake(0.0, 8.0);

    self.clipView = [UIView new];
    self.clipView.backgroundColor = UIColor.systemBackgroundColor;
    self.clipView.layer.cornerRadius = KSBallFloatingWindowCornerRadius;
    self.clipView.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipView.layer.masksToBounds = YES;
    self.clipView.layer.borderWidth = 0.5;
    [self addSubview:self.clipView];

    [self buildContentWithIcon:icon displayName:displayName];
    [self buildTitleBar];
    [self buildResizeHandle];
    [self buildMinimizedOverlayWithIcon:icon];
    [self updateBorderColor];

    // 窗口外框与占位区都需要接住触摸，否则会穿透到下层应用；应用画面则由系统直接把触摸交给被托管的应用。
    for (UIView *view in @[self.titleBarView, self.resizeHandleView, self.minimizedOverlayView, self.placeholderView]) {
        KSBallSetLayerHitTestsAsOpaque(view.layer, YES);
    }
    return self;
}

#pragma mark - 构建

- (void)buildContentWithIcon:(UIImage *)icon displayName:(NSString *)displayName {
    self.contentView = [UIView new];
    self.contentView.backgroundColor = UIColor.systemBackgroundColor;
    self.contentView.clipsToBounds = YES;
    [self.clipView addSubview:self.contentView];

    self.scalingView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.screenSize.width, self.screenSize.height)];
    self.scalingView.layer.anchorPoint = CGPointZero;
    self.scalingView.layer.position = CGPointZero;
    self.scalingView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.scalingView];

    self.placeholderView = [UIView new];
    self.placeholderView.backgroundColor = UIColor.systemBackgroundColor;
    [self.contentView addSubview:self.placeholderView];

    self.placeholderIconView = [[UIImageView alloc] initWithImage:icon ?: [UIImage systemImageNamed:@"app.fill"]];
    self.placeholderIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.placeholderIconView.tintColor = UIColor.secondaryLabelColor;
    self.placeholderIconView.layer.cornerRadius = KSBallFloatingPlaceholderIconSize * 0.225;
    self.placeholderIconView.layer.cornerCurve = kCACornerCurveContinuous;
    self.placeholderIconView.clipsToBounds = YES;
    [self.placeholderView addSubview:self.placeholderIconView];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.activityIndicator startAnimating];
    [self.placeholderView addSubview:self.activityIndicator];

    self.statusLabel = [UILabel new];
    self.statusLabel.text = displayName;
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [self.placeholderView addSubview:self.statusLabel];
}

- (void)buildTitleBar {
    self.titleBarView = [UIView new];
    self.titleBarView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.clipView addSubview:self.titleBarView];

    self.grabberView = [UIView new];
    self.grabberView.userInteractionEnabled = NO;
    self.grabberView.backgroundColor = UIColor.tertiaryLabelColor;
    self.grabberView.layer.cornerRadius = 2.5;
    [self.titleBarView addSubview:self.grabberView];

    self.closeButton = [self titleBarButtonWithSymbol:@"xmark" action:@selector(closeTapped) accessibilityLabel:@"关闭"];
    self.minimizeButton = [self titleBarButtonWithSymbol:@"minus" action:@selector(minimizeTapped) accessibilityLabel:@"收起"];
    self.fullScreenButton = [self titleBarButtonWithSymbol:@"arrow.up.left.and.arrow.down.right" action:@selector(fullScreenTapped) accessibilityLabel:@"全屏打开"];

    UIPanGestureRecognizer *moveRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMove:)];
    moveRecognizer.maximumNumberOfTouches = 1;
    moveRecognizer.cancelsTouchesInView = NO;
    [self.titleBarView addGestureRecognizer:moveRecognizer];
}

- (UIButton *)titleBarButtonWithSymbol:(NSString *)symbol action:(SEL)action accessibilityLabel:(NSString *)accessibilityLabel {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightBold];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:configuration] forState:UIControlStateNormal];
    button.tintColor = UIColor.secondaryLabelColor;
    button.accessibilityLabel = accessibilityLabel;
    KSBallSetLayerHitTestsAsOpaque(button.layer, YES);
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:action];
    tapRecognizer.cancelsTouchesInView = NO;
    [button addGestureRecognizer:tapRecognizer];
    [self.titleBarView addSubview:button];
    return button;
}

- (void)buildResizeHandle {
    self.resizeHandleView = [UIView new];
    self.resizeHandleView.backgroundColor = UIColor.clearColor;
    self.resizeHandleView.accessibilityLabel = @"调整窗口大小";
    [self addSubview:self.resizeHandleView];

    // 贴着窗口右下圆角画一段弧线作为缩放提示。
    self.resizeIndicatorLayer = [CAShapeLayer layer];
    self.resizeIndicatorLayer.fillColor = UIColor.clearColor.CGColor;
    self.resizeIndicatorLayer.lineWidth = 4.0;
    self.resizeIndicatorLayer.lineCap = kCALineCapRound;
    self.resizeIndicatorLayer.shadowColor = UIColor.blackColor.CGColor;
    self.resizeIndicatorLayer.shadowOpacity = 0.35;
    self.resizeIndicatorLayer.shadowRadius = 2.0;
    self.resizeIndicatorLayer.shadowOffset = CGSizeZero;
    [self.resizeHandleView.layer addSublayer:self.resizeIndicatorLayer];

    UIPanGestureRecognizer *resizeRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResize:)];
    resizeRecognizer.maximumNumberOfTouches = 1;
    [self.resizeHandleView addGestureRecognizer:resizeRecognizer];
}

- (void)buildMinimizedOverlayWithIcon:(UIImage *)icon {
    // 收起后覆盖整个缩略图：吃掉触摸，避免误操作到被缩小的应用，点按恢复，向外甩出收起边栏。
    self.minimizedOverlayView = [UIView new];
    self.minimizedOverlayView.backgroundColor = UIColor.clearColor;
    self.minimizedOverlayView.hidden = YES;
    [self addSubview:self.minimizedOverlayView];

    self.badgeIconView = [[UIImageView alloc] initWithImage:icon ?: [UIImage systemImageNamed:@"app.fill"]];
    self.badgeIconView.contentMode = UIViewContentModeScaleAspectFill;
    self.badgeIconView.tintColor = UIColor.whiteColor;
    self.badgeIconView.backgroundColor = icon ? UIColor.clearColor : [UIColor colorWithWhite:0.18 alpha:0.95];
    self.badgeIconView.layer.cornerRadius = KSBallFloatingBadgeIconSize * 0.225;
    self.badgeIconView.layer.cornerCurve = kCACornerCurveContinuous;
    self.badgeIconView.layer.borderColor = UIColor.whiteColor.CGColor;
    self.badgeIconView.layer.borderWidth = 1.0;
    self.badgeIconView.clipsToBounds = YES;
    [self.minimizedOverlayView addSubview:self.badgeIconView];

    UITapGestureRecognizer *restoreRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(restoreTapped)];
    [self.minimizedOverlayView addGestureRecognizer:restoreRecognizer];
    UIPanGestureRecognizer *dismissRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
    dismissRecognizer.maximumNumberOfTouches = 1;
    [self.minimizedOverlayView addGestureRecognizer:dismissRecognizer];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    self.clipView.frame = bounds;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:self.clipView.layer.cornerRadius].CGPath;

    CGFloat titleBarHeight = self.minimized ? 0.0 : KSBallFloatingWindowTitleBarHeight;
    self.titleBarView.frame = CGRectMake(0.0, 0.0, width, KSBallFloatingWindowTitleBarHeight);
    self.contentView.frame = CGRectMake(0.0, titleBarHeight, width, MAX(height - titleBarHeight, 0.0));
    CGFloat contentScale = self.screenSize.width > 0.0 ? width / self.screenSize.width : 1.0;
    self.scalingView.transform = CGAffineTransformMakeScale(contentScale, contentScale);

    CGFloat buttonY = (KSBallFloatingWindowTitleBarHeight - KSBallFloatingButtonSize) / 2.0;
    self.closeButton.frame = CGRectMake(4.0, buttonY, KSBallFloatingButtonSize, KSBallFloatingButtonSize);
    self.fullScreenButton.frame = CGRectMake(width - 4.0 - KSBallFloatingButtonSize, buttonY, KSBallFloatingButtonSize, KSBallFloatingButtonSize);
    self.minimizeButton.frame = CGRectOffset(self.fullScreenButton.frame, -KSBallFloatingButtonSize, 0.0);
    self.grabberView.frame = CGRectMake((width - 36.0) / 2.0, (KSBallFloatingWindowTitleBarHeight - 5.0) / 2.0, 36.0, 5.0);

    [self layoutPlaceholder];

    self.resizeHandleView.frame = CGRectMake(width - KSBallFloatingResizeHandleSize, height - KSBallFloatingResizeHandleSize, KSBallFloatingResizeHandleSize, KSBallFloatingResizeHandleSize);
    CGFloat radius = KSBallFloatingWindowCornerRadius;
    CGPoint arcCenter = CGPointMake(KSBallFloatingResizeHandleSize - radius, KSBallFloatingResizeHandleSize - radius);
    self.resizeIndicatorLayer.frame = self.resizeHandleView.bounds;
    self.resizeIndicatorLayer.path = [UIBezierPath bezierPathWithArcCenter:arcCenter radius:radius - 3.0 startAngle:M_PI_4 * 0.35 endAngle:M_PI_2 - M_PI_4 * 0.35 clockwise:YES].CGPath;

    self.minimizedOverlayView.frame = bounds;
    self.badgeIconView.frame = CGRectMake(-4.0, height - KSBallFloatingBadgeIconSize + 4.0, KSBallFloatingBadgeIconSize, KSBallFloatingBadgeIconSize);
}

- (void)layoutPlaceholder {
    CGRect bounds = self.contentView.bounds;
    self.placeholderView.frame = bounds;
    CGFloat iconSize = MIN(KSBallFloatingPlaceholderIconSize, CGRectGetWidth(bounds) * 0.4);
    CGFloat centerY = CGRectGetMidY(bounds) - 24.0;
    self.placeholderIconView.frame = CGRectMake(CGRectGetMidX(bounds) - iconSize / 2.0, centerY - iconSize / 2.0, iconSize, iconSize);
    self.activityIndicator.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(self.placeholderIconView.frame) + 22.0);
    CGFloat labelTop = self.activityIndicator.hidden ? CGRectGetMaxY(self.placeholderIconView.frame) + 12.0 : CGRectGetMaxY(self.activityIndicator.frame) + 8.0;
    self.statusLabel.frame = CGRectMake(12.0, labelTop, MAX(CGRectGetWidth(bounds) - 24.0, 0.0), 40.0);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateBorderColor];
}

- (void)updateBorderColor {
    // CGColor 不会随深浅色自动变化，按当前特征集合重新解析。
    UIColor *borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection];
    self.clipView.layer.borderColor = borderColor.CGColor;
    self.resizeIndicatorLayer.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.9].CGColor;
}

#pragma mark - 状态

- (void)setMinimized:(BOOL)minimized {
    _minimized = minimized;
    self.clipView.layer.cornerRadius = minimized ? KSBallFloatingWindowThumbnailCornerRadius : KSBallFloatingWindowCornerRadius;
    self.titleBarView.alpha = minimized ? 0.0 : 1.0;
    self.resizeHandleView.alpha = minimized ? 0.0 : 1.0;
    self.resizeHandleView.userInteractionEnabled = !minimized;
    self.titleBarView.userInteractionEnabled = !minimized;
    // 遮罩按不透明命中，只调透明度仍会在系统层面拦截触摸，展开时必须隐藏。
    self.minimizedOverlayView.hidden = !minimized;
    self.transform = CGAffineTransformIdentity;
    [self setNeedsLayout];
}

- (void)setPresentationView:(UIView *)presentationView {
    if (_presentationView == presentationView) {
        return;
    }
    if (_presentationView.superview == self.scalingView) {
        [_presentationView removeFromSuperview];
    }
    _presentationView = presentationView;
    if (presentationView) {
        presentationView.frame = self.scalingView.bounds;
        presentationView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.scalingView addSubview:presentationView];
    }
    [self.activityIndicator stopAnimating];
    self.activityIndicator.hidden = YES;
    [UIView animateWithDuration:0.2 animations:^{
        self.placeholderView.alpha = presentationView ? 0.0 : 1.0;
    } completion:^(BOOL finished) {
        // 隐藏后占位区不再按不透明拦截触摸，应用画面才能收到触摸。
        self.placeholderView.hidden = self.presentationView != nil;
    }];
    [self setNeedsLayout];
}

- (void)showStatusMessage:(NSString *)message {
    self.statusLabel.text = message;
    [self.activityIndicator stopAnimating];
    self.activityIndicator.hidden = YES;
    self.placeholderView.hidden = NO;
    self.placeholderView.alpha = 1.0;
    [self setNeedsLayout];
}

#pragma mark - 交互

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self.delegate floatingAppWindowViewDidBeginInteraction:self];
}

- (void)closeTapped {
    [self.delegate floatingAppWindowViewDidRequestClose:self];
}

- (void)minimizeTapped {
    [self.delegate floatingAppWindowViewDidRequestMinimize:self];
}

- (void)fullScreenTapped {
    [self.delegate floatingAppWindowViewDidRequestFullScreen:self];
}

- (void)restoreTapped {
    [self.delegate floatingAppWindowViewDidRequestRestore:self];
}

- (void)handleMove:(UIPanGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            [self.delegate floatingAppWindowViewDidBeginInteraction:self];
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [recognizer translationInView:self.superview];
            [recognizer setTranslation:CGPointZero inView:self.superview];
            self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self.delegate floatingAppWindowViewDidEndMoving:self];
            break;
        default:
            break;
    }
}

// 左上角固定，按手指在水平与竖直方向的位移分别换算出宽度后取平均，窗口始终保持屏幕宽高比。
- (void)handleResize:(UIPanGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            self.resizeStartWidth = CGRectGetWidth(self.bounds);
            self.resizeStartContentHeight = CGRectGetHeight(self.bounds) - KSBallFloatingWindowTitleBarHeight;
            [self.delegate floatingAppWindowViewDidBeginInteraction:self];
            break;
        case UIGestureRecognizerStateChanged: {
            if (self.screenSize.height <= 0.0) {
                break;
            }
            CGPoint translation = [recognizer translationInView:self.superview];
            CGFloat aspect = self.screenSize.width / self.screenSize.height;
            CGFloat widthFromX = self.resizeStartWidth + translation.x;
            CGFloat widthFromY = (self.resizeStartContentHeight + translation.y) * aspect;
            CGFloat scale = [KSBallFloatingWindowLayout scaleForWindowWidth:(widthFromX + widthFromY) / 2.0 screenSize:self.screenSize];
            CGSize size = [KSBallFloatingWindowLayout windowSizeForScale:scale screenSize:self.screenSize];
            CGRect frame = self.frame;
            frame.size = size;
            self.frame = frame;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self.delegate floatingAppWindowViewDidEndMoving:self];
            break;
        default:
            break;
    }
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)recognizer {
    CGFloat direction = self.minimizedEdge == KSBallEdgeLeft ? -1.0 : 1.0;
    CGFloat outward = [recognizer translationInView:self.superview].x * direction;
    switch (recognizer.state) {
        case UIGestureRecognizerStateChanged:
            // 只允许向收纳区外侧拖动，向内拖动时轻微阻尼。
            self.transform = CGAffineTransformMakeTranslation((outward > 0.0 ? outward : outward * 0.2) * direction, 0.0);
            break;
        case UIGestureRecognizerStateEnded: {
            CGFloat velocity = [recognizer velocityInView:self.superview].x * direction;
            if (outward > KSBallFloatingDockCollapseDistance || velocity > KSBallFloatingDockCollapseVelocity) {
                [self.delegate floatingAppWindowViewDidRequestHideDock:self];
                break;
            }
            [UIView animateWithDuration:0.25 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                self.transform = CGAffineTransformIdentity;
            } completion:nil];
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [UIView animateWithDuration:0.2 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                self.transform = CGAffineTransformIdentity;
            } completion:nil];
            break;
        }
        default:
            break;
    }
}

@end
