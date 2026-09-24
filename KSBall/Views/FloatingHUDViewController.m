#import "FloatingHUDViewController.h"
#import "HUDTouchEventBridge.h"
#import "KSBallFanLayout.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import <math.h>

// 悬浮条可见部分与触摸热区。热区比可见条宽得多，保证贴边时依然容易按到。
static const CGFloat KSBallHandleBarWidth = 6.0;
static const CGFloat KSBallHandleActiveBarWidth = 9.0;
static const CGFloat KSBallHandleBarHeight = 72.0;
static const CGFloat KSBallHandleTouchWidth = 30.0;
static const CGFloat KSBallHandleTouchHeight = 112.0;
static const CGFloat KSBallHandleVerticalMargin = 44.0;
// 扇形圆心略微内收，保证外圈和偏上/偏下布局都不会被屏幕边缘挤压。
static const CGFloat KSBallFanAnchorInset = 20.0;
static const CGFloat KSBallMenuButtonSize = 50.0;
static const CGFloat KSBallMenuHoverRadius = 36.0;
static const CGFloat KSBallDragActivationDistance = 8.0;

@interface KSBallHUDCanvasView : UIView
@property (nonatomic, copy) NSArray<UIView *> *interactiveViews;
@end

@implementation KSBallHUDCanvasView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *view in self.interactiveViews) {
        if (!view.hidden && view.alpha > 0.01 && CGRectContainsPoint(view.frame, point)) {
            return YES;
        }
    }
    return NO;
}

@end

@interface FloatingHUDViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong) UIView *handleView;
@property (nonatomic, strong) UIView *barView;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, strong) NSMutableArray<UIButton *> *menuButtons;
@property (nonatomic, strong) NSMutableDictionary<NSString *, KSBallShortcut *> *shortcutsByIdentifier;
@property (nonatomic, strong) NSMutableSet<NSString *> *unavailableIdentifiers;
@property (nonatomic, strong, nullable) UIButton *hoveredButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *feedbackLabel;
@property (nonatomic) BOOL menuVisible;
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL dragMoved;
@property (nonatomic) CGPoint dragStartLocation;
@property (nonatomic) KSBallEdge dragEdge;
@property (nonatomic) CGFloat dragCenterY;
@end

@implementation FloatingHUDViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _menuButtons = [NSMutableArray array];
        _shortcutsByIdentifier = [NSMutableDictionary dictionary];
        _unavailableIdentifiers = [NSMutableSet set];
    }
    return self;
}

- (void)loadView {
    KSBallHUDCanvasView *canvas = [KSBallHUDCanvasView new];
    canvas.backgroundColor = UIColor.clearColor;
    self.view = canvas;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.handleView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, KSBallHandleTouchWidth, KSBallHandleTouchHeight)];
    self.handleView.backgroundColor = UIColor.clearColor;
    self.handleView.isAccessibilityElement = YES;
    self.handleView.accessibilityLabel = @"KSBall 快捷菜单";
    [self.view addSubview:self.handleView];

    self.barView = [UIView new];
    self.barView.userInteractionEnabled = NO;
    self.barView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    self.barView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
    self.barView.layer.borderWidth = 0.5;
    self.barView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.barView.layer.shadowOpacity = 0.3;
    self.barView.layer.shadowRadius = 4.0;
    self.barView.layer.shadowOffset = CGSizeZero;
    [self.handleView addSubview:self.barView];

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.handleView addGestureRecognizer:tapRecognizer];

    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panRecognizer.maximumNumberOfTouches = 1;
    self.panRecognizer.delegate = self;
    [self.handleView addGestureRecognizer:self.panRecognizer];

    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressRecognizer.minimumPressDuration = 0.45;
    longPressRecognizer.allowableMovement = 10.0;
    [self.handleView addGestureRecognizer:longPressRecognizer];

    self.nameLabel = [self capsuleLabel];
    [self.view addSubview:self.nameLabel];
    self.feedbackLabel = [self capsuleLabel];
    [self.view addSubview:self.feedbackLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFromSettings) name:KSBallSettingsDidChangeNotification object:self.settingsStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOutsideTouch:) name:KSBallHUDOutsideTouchNotification object:nil];
    [self reloadFromSettings];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHandle];
    if (self.menuVisible) {
        NSArray<NSValue *> *centers = [self menuCenters];
        [centers enumerateObjectsUsingBlock:^(NSValue * _Nonnull value, NSUInteger index, BOOL * _Nonnull stop) {
            self.menuButtons[index].center = value.CGPointValue;
        }];
    }
}

- (void)reloadFromSettings {
    if (!self.isViewLoaded || self.dragging) {
        return;
    }
    [self dismissMenuAnimated:NO];
    [self layoutHandle];
}

#pragma mark - 布局

- (UILabel *)capsuleLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.86];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.layer.cornerRadius = 13.0;
    label.clipsToBounds = YES;
    label.alpha = 0.0;
    label.userInteractionEnabled = NO;
    return label;
}

- (CGRect)safeBounds {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    return UIEdgeInsetsInsetRect(self.view.bounds, UIEdgeInsetsMake(insets.top + 8.0, insets.left + 8.0, insets.bottom + 8.0, insets.right + 8.0));
}

- (CGFloat)minimumHandleCenterY {
    return MAX(self.view.safeAreaInsets.top, KSBallHandleVerticalMargin) + KSBallHandleTouchHeight / 2.0;
}

- (CGFloat)maximumHandleCenterY {
    CGFloat maximum = CGRectGetHeight(self.view.bounds) - MAX(self.view.safeAreaInsets.bottom, KSBallHandleVerticalMargin) - KSBallHandleTouchHeight / 2.0;
    return MAX(maximum, [self minimumHandleCenterY]);
}

- (KSBallEdge)currentEdge {
    return self.dragging && self.dragMoved ? self.dragEdge : self.settingsStore.settings.edge;
}

- (CGFloat)currentHandleCenterY {
    CGFloat minY = [self minimumHandleCenterY];
    CGFloat maxY = [self maximumHandleCenterY];
    CGFloat y = self.dragging && self.dragMoved ? self.dragCenterY : minY + (maxY - minY) * self.settingsStore.settings.normalizedVerticalPosition;
    return MIN(MAX(y, minY), maxY);
}

- (void)layoutHandle {
    KSBallEdge edge = [self currentEdge];
    CGFloat centerY = [self currentHandleCenterY];
    CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
    CGFloat handleX = edge == KSBallEdgeLeft ? 0.0 : viewWidth - KSBallHandleTouchWidth;
    self.handleView.frame = CGRectMake(handleX, centerY - KSBallHandleTouchHeight / 2.0, KSBallHandleTouchWidth, KSBallHandleTouchHeight);
    [self layoutBar];
    [self refreshHitTargets];
}

- (void)layoutBar {
    BOOL active = self.menuVisible || self.dragging;
    CGFloat barWidth = active ? KSBallHandleActiveBarWidth : KSBallHandleBarWidth;
    KSBallEdge edge = [self currentEdge];
    // 贴边一侧保持平直，只圆角化朝向屏幕内侧的两个角。
    CGFloat barX = edge == KSBallEdgeLeft ? 0.0 : KSBallHandleTouchWidth - barWidth;
    self.barView.frame = CGRectMake(barX, (KSBallHandleTouchHeight - KSBallHandleBarHeight) / 2.0, barWidth, KSBallHandleBarHeight);
    self.barView.layer.cornerRadius = barWidth / 2.0;
    self.barView.layer.maskedCorners = edge == KSBallEdgeLeft ? (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner) : (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner);
    self.barView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:active ? 0.98 : 0.82];
}

- (void)setBarActiveAnimated {
    [UIView animateWithDuration:0.16 animations:^{
        [self layoutBar];
    }];
}

- (CGPoint)fanAnchor {
    CGRect safeBounds = [self safeBounds];
    CGFloat x = [self currentEdge] == KSBallEdgeLeft ? CGRectGetMinX(safeBounds) + KSBallFanAnchorInset : CGRectGetMaxX(safeBounds) - KSBallFanAnchorInset;
    return CGPointMake(x, [self currentHandleCenterY]);
}

- (NSArray<NSValue *> *)menuCenters {
    KSBallSettings *settings = self.settingsStore.settings;
    return [KSBallFanLayout centersForItemCount:self.menuButtons.count anchorCenter:[self fanAnchor] safeBounds:[self safeBounds] edge:[self currentEdge] bias:settings.fanBias];
}

#pragma mark - 扇形菜单

- (void)toggleMenu {
    if (self.menuVisible) {
        [self dismissMenuAnimated:YES];
    } else {
        [self showMenu];
    }
}

- (void)showMenu {
    NSArray<KSBallShortcut *> *shortcuts = self.settingsStore.settings.shortcuts;
    if (shortcuts.count == 0) {
        [self showFeedback:@"长按悬浮条进入设置添加应用"];
        return;
    }

    [self rebuildMenuForShortcuts:shortcuts];
    self.menuVisible = YES;
    NSArray<NSValue *> *centers = [self menuCenters];
    CGPoint anchor = [self fanAnchor];
    for (UIButton *button in self.menuButtons) {
        button.hidden = NO;
        button.alpha = 0.0;
        button.center = anchor;
        button.transform = CGAffineTransformMakeScale(0.2, 0.2);
    }
    [self refreshHitTargets];
    [self setBarActiveAnimated];
    [UIView animateWithDuration:0.32 delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        [self.menuButtons enumerateObjectsUsingBlock:^(UIButton * _Nonnull button, NSUInteger index, BOOL * _Nonnull stop) {
            button.center = centers[index].CGPointValue;
            button.transform = CGAffineTransformIdentity;
            button.alpha = [self restingAlphaForButton:button];
        }];
    } completion:nil];
}

- (void)dismissMenuAnimated:(BOOL)animated {
    [self updateHoveredButton:nil];
    if (!self.menuVisible && self.menuButtons.count == 0) {
        return;
    }
    self.menuVisible = NO;
    [self refreshHitTargets];
    NSArray<UIButton *> *buttons = [self.menuButtons copy];
    CGPoint anchor = [self fanAnchor];
    void (^changes)(void) = ^{
        for (UIButton *button in buttons) {
            button.alpha = 0.0;
            button.center = anchor;
            button.transform = CGAffineTransformMakeScale(0.2, 0.2);
        }
        [self layoutBar];
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        // 动画期间菜单可能已被重新打开，只隐藏仍处于收起状态的旧按钮。
        for (UIButton *button in buttons) {
            if (!self.menuVisible || ![self.menuButtons containsObject:button]) {
                button.hidden = YES;
                button.transform = CGAffineTransformIdentity;
            }
        }
    };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (void)rebuildMenuForShortcuts:(NSArray<KSBallShortcut *> *)shortcuts {
    for (UIButton *button in self.menuButtons) {
        [button removeFromSuperview];
    }
    [self.menuButtons removeAllObjects];
    [self.shortcutsByIdentifier removeAllObjects];
    [self.unavailableIdentifiers removeAllObjects];

    NSMutableDictionary<NSString *, KSBallApplication *> *applicationsByIdentifier = [NSMutableDictionary dictionary];
    for (KSBallApplication *application in self.applicationBridge.availableApplications) {
        applicationsByIdentifier[application.bundleIdentifier.lowercaseString] = application;
    }

    for (KSBallShortcut *shortcut in shortcuts) {
        KSBallApplication *application = applicationsByIdentifier[shortcut.bundleIdentifier.lowercaseString];
        NSString *identifier = shortcut.identifier.UUIDString;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.bounds = CGRectMake(0.0, 0.0, KSBallMenuButtonSize, KSBallMenuButtonSize);
        button.layer.cornerRadius = KSBallMenuButtonSize / 2.0;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.28;
        button.layer.shadowRadius = 6.0;
        button.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        button.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.9];
        button.tintColor = UIColor.whiteColor;
        button.accessibilityLabel = shortcut.displayName;
        button.accessibilityIdentifier = identifier;
        UIImage *icon = application.icon ?: [UIImage systemImageNamed:@"app.fill"];
        [button setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.imageView.layer.cornerRadius = 9.0;
        button.imageView.clipsToBounds = YES;
        button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
        button.hidden = YES;
        if (!application) {
            [self.unavailableIdentifiers addObject:identifier];
        }
        [button addTarget:self action:@selector(launchShortcut:) forControlEvents:UIControlEventTouchUpInside];
        [self.view insertSubview:button belowSubview:self.handleView];
        [self.menuButtons addObject:button];
        self.shortcutsByIdentifier[identifier] = shortcut;
    }
}

- (CGFloat)restingAlphaForButton:(UIButton *)button {
    return [self.unavailableIdentifiers containsObject:button.accessibilityIdentifier] ? 0.55 : 1.0;
}

- (nullable UIButton *)menuButtonNearPoint:(CGPoint)point {
    UIButton *nearestButton = nil;
    CGFloat nearestDistance = KSBallMenuHoverRadius;
    for (UIButton *button in self.menuButtons) {
        CGFloat distance = hypot(button.center.x - point.x, button.center.y - point.y);
        if (distance <= nearestDistance) {
            nearestDistance = distance;
            nearestButton = button;
        }
    }
    return nearestButton;
}

- (void)updateHoveredButton:(nullable UIButton *)button {
    if (button == self.hoveredButton) {
        return;
    }
    UIButton *previousButton = self.hoveredButton;
    self.hoveredButton = button;
    [UIView animateWithDuration:0.12 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        previousButton.transform = CGAffineTransformIdentity;
        previousButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        button.transform = CGAffineTransformMakeScale(1.22, 1.22);
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    } completion:nil];

    if (!button) {
        [UIView animateWithDuration:0.12 animations:^{
            self.nameLabel.alpha = 0.0;
        }];
        return;
    }
    KSBallShortcut *shortcut = self.shortcutsByIdentifier[button.accessibilityIdentifier];
    self.nameLabel.text = shortcut.displayName;
    CGFloat width = MIN(ceil([self.nameLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 26.0)].width) + 24.0, CGRectGetWidth(self.view.bounds) - 32.0);
    CGRect safeBounds = [self safeBounds];
    CGFloat labelY = button.center.y - KSBallMenuButtonSize * 0.61 - 34.0;
    if (labelY < CGRectGetMinY(safeBounds)) {
        labelY = button.center.y + KSBallMenuButtonSize * 0.61 + 8.0;
    }
    CGFloat labelX = MIN(MAX(button.center.x - width / 2.0, CGRectGetMinX(safeBounds)), CGRectGetMaxX(safeBounds) - width);
    self.nameLabel.frame = CGRectMake(labelX, labelY, width, 26.0);
    self.nameLabel.alpha = 1.0;
}

- (void)launchShortcut:(UIButton *)sender {
    KSBallShortcut *shortcut = self.shortcutsByIdentifier[sender.accessibilityIdentifier];
    [self dismissMenuAnimated:YES];
    if (!shortcut || ![self.applicationBridge launchBundleIdentifier:shortcut.bundleIdentifier]) {
        [self showFeedback:@"应用不可用或无法启动"];
    }
}

#pragma mark - 手势

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self toggleMenu];
    }
}

// 从悬浮条向内滑动即展开扇形菜单；手指不抬起滑到图标上松手即可启动，松手在空白处则保持菜单打开以便点选。
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            if (!self.menuVisible) {
                [self showMenu];
            }
            [self updateHoveredButton:[self menuButtonNearPoint:location]];
            break;
        case UIGestureRecognizerStateChanged:
            if (self.menuVisible) {
                [self updateHoveredButton:[self menuButtonNearPoint:location]];
            }
            break;
        case UIGestureRecognizerStateEnded: {
            UIButton *target = self.menuVisible ? self.hoveredButton : nil;
            [self updateHoveredButton:nil];
            if (target) {
                [self launchShortcut:target];
            }
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self updateHoveredButton:nil];
            break;
        default:
            break;
    }
}

// 长按不动进入设置页；长按后拖动可沿边缘移动悬浮条，越过屏幕中线会换到另一侧。
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            [self dismissMenuAnimated:YES];
            self.dragging = YES;
            self.dragMoved = NO;
            self.dragStartLocation = location;
            self.dragEdge = self.settingsStore.settings.edge;
            self.dragCenterY = [self currentHandleCenterY];
            [self setBarActiveAnimated];
            break;
        case UIGestureRecognizerStateChanged: {
            if (!self.dragMoved && hypot(location.x - self.dragStartLocation.x, location.y - self.dragStartLocation.y) >= KSBallDragActivationDistance) {
                self.dragMoved = YES;
            }
            if (!self.dragMoved) {
                break;
            }
            KSBallEdge edge = location.x < CGRectGetMidX(self.view.bounds) ? KSBallEdgeLeft : KSBallEdgeRight;
            BOOL edgeChanged = edge != self.dragEdge;
            self.dragEdge = edge;
            self.dragCenterY = location.y;
            if (edgeChanged) {
                [UIView animateWithDuration:0.18 animations:^{
                    [self layoutHandle];
                }];
            } else {
                [self layoutHandle];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            BOOL moved = self.dragMoved;
            BOOL ended = recognizer.state == UIGestureRecognizerStateEnded;
            KSBallEdge edge = self.dragEdge;
            CGFloat minY = [self minimumHandleCenterY];
            CGFloat maxY = [self maximumHandleCenterY];
            CGFloat normalizedPosition = maxY > minY ? ([self currentHandleCenterY] - minY) / (maxY - minY) : 0.5;
            self.dragging = NO;
            self.dragMoved = NO;
            if (ended && moved) {
                [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
                    settings.edge = edge;
                    settings.normalizedVerticalPosition = normalizedPosition;
                }];
            } else if (ended && self.openConfigurationHandler) {
                self.openConfigurationHandler();
            }
            [UIView animateWithDuration:0.18 animations:^{
                [self layoutHandle];
            }];
            break;
        }
        default:
            break;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.panRecognizer) {
        return !self.dragging;
    }
    return YES;
}

- (void)handleOutsideTouch:(NSNotification *)notification {
    if (self.menuVisible && !self.dragging) {
        [self dismissMenuAnimated:YES];
    }
}

#pragma mark - 辅助

- (void)showFeedback:(NSString *)message {
    self.feedbackLabel.text = message;
    CGFloat width = MIN(ceil([self.feedbackLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 32.0)].width) + 32.0, CGRectGetWidth(self.view.bounds) - 32.0);
    CGFloat bottom = CGRectGetHeight(self.view.bounds) - MAX(self.view.safeAreaInsets.bottom, KSBallHandleVerticalMargin);
    self.feedbackLabel.frame = CGRectMake(CGRectGetMidX(self.view.bounds) - width / 2.0, bottom - 40.0, width, 32.0);
    self.feedbackLabel.layer.cornerRadius = 16.0;
    [UIView animateWithDuration:0.15 animations:^{
        self.feedbackLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 delay:1.4 options:0 animations:^{
            self.feedbackLabel.alpha = 0.0;
        } completion:nil];
    }];
}

- (void)refreshHitTargets {
    NSMutableArray<UIView *> *targets = [NSMutableArray arrayWithObject:self.handleView];
    if (self.menuVisible) {
        [targets addObjectsFromArray:self.menuButtons];
    }
    ((KSBallHUDCanvasView *)self.view).interactiveViews = targets;
}

@end
