#import "FloatingHUDViewController.h"
#import "KSBallFanLayout.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import <math.h>
#import <notify.h>
#import <objc/message.h>

// 悬浮条可见部分：细短条，与屏幕边缘保留 10pt 间隙。
static const CGFloat KSBallHandleEdgeInset = 10.0;
static const CGFloat KSBallHandleBarWidth = 4.0;
static const CGFloat KSBallHandleActiveBarWidth = 6.0;
static const CGFloat KSBallHandleBarHeight = 36.0;
// 触摸热区从屏幕边缘开始，远大于可见条，保证手指容易按到。
static const CGFloat KSBallHandleTouchWidth = 52.0;
static const CGFloat KSBallHandleTouchHeight = 120.0;
// 可见条与屏幕上下边缘的最小距离，允许把悬浮条拖到四个角落；热区可以超出屏幕。
static const CGFloat KSBallHandleVerticalInset = 10.0;
static const CGFloat KSBallDragActivationDistance = 8.0;
static const CGFloat KSBallPreviewIconSize = 108.0;
// 配置变化后扇形菜单的预览停留时间。
static const NSTimeInterval KSBallMenuPreviewDuration = 1.6;
static const char * const KSBallLockStateNotification = "com.apple.springboard.lockstate";

// 系统窗口托管按图层做命中测试：透明区域的触摸会直接落到下层应用。
// 热区需要按不透明处理；纯展示用的图层则不能拦截触摸。
static void KSBallSetLayerHitTestsAsOpaque(CALayer *layer, BOOL opaque) {
    SEL selector = NSSelectorFromString(@"setHitTestsAsOpaque:");
    if ([layer respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, selector, opaque);
    }
}

static void KSBallSetLayerAllowsHitTesting(CALayer *layer, BOOL allowsHitTesting) {
    SEL selector = NSSelectorFromString(@"setAllowsHitTesting:");
    if ([layer respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, selector, allowsHitTesting);
    }
    for (CALayer *sublayer in layer.sublayers) {
        KSBallSetLayerAllowsHitTesting(sublayer, allowsHitTesting);
    }
}

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
@property (nonatomic, strong) UIVisualEffectView *backdropView;
@property (nonatomic, strong) NSMutableArray<UIView *> *menuItemViews;
@property (nonatomic, copy) NSArray<KSBallShortcut *> *menuShortcuts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *iconsByBundleIdentifier;
@property (nonatomic, strong, nullable) UIView *hoveredItemView;
@property (nonatomic) CGFloat menuItemSize;
@property (nonatomic) CGFloat menuHoverRadius;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *previewNameLabel;
@property (nonatomic, strong) UILabel *feedbackLabel;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hoverFeedbackGenerator;
@property (nonatomic) BOOL menuVisible;
@property (nonatomic) BOOL previewingMenu;
@property (nonatomic) BOOL backdropRequested;
@property (nonatomic) BOOL screenLocked;
@property (nonatomic) int lockStateToken;
@property (nonatomic) BOOL hasAppliedSettings;
@property (nonatomic, copy) NSString *appliedMenuLayoutSignature;
@property (nonatomic, copy) NSString *appliedBackdropSignature;
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
        _menuItemViews = [NSMutableArray array];
        _menuShortcuts = @[];
        _iconsByBundleIdentifier = [NSMutableDictionary dictionary];
        _appliedMenuLayoutSignature = @"";
        _appliedBackdropSignature = @"";
        _lockStateToken = NOTIFY_TOKEN_INVALID;
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

    self.backdropView = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.backdropView.userInteractionEnabled = NO;
    self.backdropView.hidden = YES;
    self.backdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backdropView.frame = self.view.bounds;
    [self.view addSubview:self.backdropView];

    self.previewImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, KSBallPreviewIconSize, KSBallPreviewIconSize)];
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewImageView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.previewImageView.layer.shadowOpacity = 0.35;
    self.previewImageView.layer.shadowRadius = 16.0;
    self.previewImageView.layer.shadowOffset = CGSizeMake(0.0, 6.0);
    self.previewImageView.alpha = 0.0;
    [self.view addSubview:self.previewImageView];

    self.previewNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.previewNameLabel.textColor = UIColor.whiteColor;
    self.previewNameLabel.textAlignment = NSTextAlignmentCenter;
    self.previewNameLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.previewNameLabel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.previewNameLabel.layer.shadowOpacity = 0.5;
    self.previewNameLabel.layer.shadowRadius = 4.0;
    self.previewNameLabel.layer.shadowOffset = CGSizeZero;
    self.previewNameLabel.alpha = 0.0;
    [self.view addSubview:self.previewNameLabel];

    self.handleView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, KSBallHandleTouchWidth, KSBallHandleTouchHeight)];
    // 几乎透明的底色加上按不透明命中，整个热区都能接住触摸而不会穿透到下层应用。
    self.handleView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.012];
    KSBallSetLayerHitTestsAsOpaque(self.handleView.layer, YES);
    self.handleView.isAccessibilityElement = YES;
    self.handleView.accessibilityLabel = @"KSBall 快捷菜单";
    [self.view addSubview:self.handleView];

    self.barView = [UIView new];
    self.barView.userInteractionEnabled = NO;
    self.barView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
    self.barView.layer.borderWidth = 0.5;
    self.barView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.barView.layer.shadowOpacity = 0.3;
    self.barView.layer.shadowRadius = 3.0;
    self.barView.layer.shadowOffset = CGSizeZero;
    [self.handleView addSubview:self.barView];

    // 扇形菜单只能由滑动展开；点按悬浮条不做任何事。
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panRecognizer.maximumNumberOfTouches = 1;
    self.panRecognizer.delegate = self;
    [self.handleView addGestureRecognizer:self.panRecognizer];

    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressRecognizer.minimumPressDuration = 0.45;
    longPressRecognizer.allowableMovement = 10.0;
    [self.handleView addGestureRecognizer:longPressRecognizer];

    self.feedbackLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.feedbackLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.86];
    self.feedbackLabel.textColor = UIColor.whiteColor;
    self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
    self.feedbackLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.feedbackLabel.layer.cornerRadius = 16.0;
    self.feedbackLabel.clipsToBounds = YES;
    self.feedbackLabel.alpha = 0.0;
    [self.view addSubview:self.feedbackLabel];

    self.hoverFeedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];

    for (UIView *decorativeView in @[self.backdropView, self.previewImageView, self.previewNameLabel, self.feedbackLabel]) {
        KSBallSetLayerAllowsHitTesting(decorativeView.layer, NO);
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFromSettings) name:KSBallSettingsDidChangeNotification object:self.settingsStore];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(KSBallLockStateNotification, &_lockStateToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf refreshLockState];
    });
    [self refreshLockState];
    [self reloadFromSettings];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (_lockStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_lockStateToken);
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHandle];
}

- (void)reloadFromSettings {
    if (!self.isViewLoaded || self.dragging) {
        return;
    }
    KSBallSettings *settings = self.settingsStore.settings;
    NSString *shortcutIdentifiers = [[settings.shortcuts valueForKey:@"bundleIdentifier"] componentsJoinedByString:@","];
    NSString *menuLayoutSignature = [NSString stringWithFormat:@"%.2f|%.2f|%.2f|%@", settings.iconSize, settings.iconSpacing, settings.ringSpacing, shortcutIdentifiers];
    NSString *backdropSignature = [NSString stringWithFormat:@"%ld|%.2f", (long)settings.backdropStyle, settings.backdropOpacity];
    BOOL menuLayoutChanged = self.hasAppliedSettings && ![menuLayoutSignature isEqualToString:self.appliedMenuLayoutSignature];
    BOOL backdropChanged = self.hasAppliedSettings && ![backdropSignature isEqualToString:self.appliedBackdropSignature];
    self.hasAppliedSettings = YES;
    self.appliedMenuLayoutSignature = menuLayoutSignature;
    self.appliedBackdropSignature = backdropSignature;

    [self reloadIcons];
    // 用户正在滑动选择时不打断当前菜单。
    if (self.menuVisible && !self.previewingMenu) {
        return;
    }
    [self layoutHandle];
    if ((menuLayoutChanged || backdropChanged) && !self.screenLocked && settings.shortcuts.count > 0) {
        // 调整毛玻璃时连同背景一起预览；其余情况不遮挡设置页。
        [self presentMenuPreviewWithBackdrop:backdropChanged];
    } else {
        [self dismissMenuAnimated:NO];
    }
}

#pragma mark - 锁屏

- (void)refreshLockState {
    uint64_t state = 0;
    if (self.lockStateToken != NOTIFY_TOKEN_INVALID) {
        notify_get_state(self.lockStateToken, &state);
    }
    [self setScreenLocked:state != 0];
}

- (void)setScreenLocked:(BOOL)screenLocked {
    _screenLocked = screenLocked;
    if (!self.isViewLoaded) {
        return;
    }
    if (screenLocked) {
        // 切换 enabled 会取消进行中的滑动或拖动。
        for (UIGestureRecognizer *recognizer in self.handleView.gestureRecognizers) {
            recognizer.enabled = NO;
            recognizer.enabled = YES;
        }
        self.dragging = NO;
        self.dragMoved = NO;
        [self dismissMenuAnimated:NO];
    }
    self.handleView.hidden = screenLocked;
    [self layoutHandle];
}

- (void)reloadIcons {
    // 图标在设置变化时预先加载，避免滑出菜单时卡顿。
    NSMutableDictionary<NSString *, UIImage *> *icons = [NSMutableDictionary dictionary];
    for (KSBallShortcut *shortcut in self.settingsStore.settings.shortcuts) {
        NSString *key = shortcut.bundleIdentifier.lowercaseString;
        UIImage *icon = self.iconsByBundleIdentifier[key] ?: [self.applicationBridge iconForBundleIdentifier:shortcut.bundleIdentifier];
        if (icon) {
            icons[key] = icon;
        }
    }
    self.iconsByBundleIdentifier = icons;
}

#pragma mark - 悬浮条

- (KSBallEdge)currentEdge {
    return self.dragging && self.dragMoved ? self.dragEdge : self.settingsStore.settings.edge;
}

- (CGFloat)minimumHandleCenterY {
    return KSBallHandleVerticalInset + KSBallHandleBarHeight / 2.0;
}

- (CGFloat)maximumHandleCenterY {
    return MAX(CGRectGetHeight(self.view.bounds) - KSBallHandleVerticalInset - KSBallHandleBarHeight / 2.0, [self minimumHandleCenterY]);
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
    CGFloat handleX = edge == KSBallEdgeLeft ? 0.0 : CGRectGetWidth(self.view.bounds) - KSBallHandleTouchWidth;
    self.handleView.frame = CGRectMake(handleX, centerY - KSBallHandleTouchHeight / 2.0, KSBallHandleTouchWidth, KSBallHandleTouchHeight);
    [self layoutBar];
    [self refreshHitTargets];
}

- (void)layoutBar {
    BOOL active = self.menuVisible || self.dragging;
    CGFloat barWidth = active ? KSBallHandleActiveBarWidth : KSBallHandleBarWidth;
    CGFloat barX = [self currentEdge] == KSBallEdgeLeft ? KSBallHandleEdgeInset : KSBallHandleTouchWidth - KSBallHandleEdgeInset - barWidth;
    self.barView.frame = CGRectMake(barX, (KSBallHandleTouchHeight - KSBallHandleBarHeight) / 2.0, barWidth, KSBallHandleBarHeight);
    self.barView.layer.cornerRadius = barWidth / 2.0;
    switch (self.settingsStore.settings.handleStyle) {
        case KSBallHandleStyleDark:
            self.barView.hidden = NO;
            self.barView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:active ? 0.9 : 0.7];
            self.barView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
            break;
        case KSBallHandleStyleHidden:
            // 隐藏时热区仍然有效；拖动调整位置期间临时显示，便于看清落点。
            self.barView.hidden = !self.dragging;
            self.barView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
            self.barView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
            break;
        case KSBallHandleStyleLight:
        default:
            self.barView.hidden = NO;
            self.barView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:active ? 0.98 : 0.8];
            self.barView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
            break;
    }
}

- (CGPoint)barCenter {
    return [self.handleView convertPoint:self.barView.center toView:self.view];
}

- (CGRect)menuSafeBounds {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    return UIEdgeInsetsInsetRect(self.view.bounds, UIEdgeInsetsMake(insets.top + 8.0, insets.left + 8.0, insets.bottom + 8.0, insets.right + 8.0));
}

#pragma mark - 扇形菜单

- (BOOL)showMenu {
    if (self.settingsStore.settings.shortcuts.count == 0) {
        [self showFeedback:@"长按悬浮条进入设置添加应用"];
        return NO;
    }
    // 预览仍在显示时直接接管，图标已在位，无需再从悬浮条弹出。
    BOOL animateFromHandle = !self.menuVisible;
    [self cancelMenuPreviewTimer];
    self.previewingMenu = NO;
    return [self presentMenuAnimatedFromHandle:animateFromHandle backdrop:YES];
}

// 配置变化后在悬浮条旁展示扇形菜单，连续调整时原地更新，停止调整后自动收起。
- (void)presentMenuPreviewWithBackdrop:(BOOL)backdrop {
    [self cancelMenuPreviewTimer];
    if (![self presentMenuAnimatedFromHandle:!self.menuVisible backdrop:backdrop]) {
        return;
    }
    if (!backdrop) {
        [self hideBackdropAnimated:YES];
    }
    self.previewingMenu = YES;
    [self performSelector:@selector(endMenuPreview) withObject:nil afterDelay:KSBallMenuPreviewDuration];
}

- (void)endMenuPreview {
    if (self.previewingMenu) {
        [self dismissMenuAnimated:YES];
    }
}

- (void)cancelMenuPreviewTimer {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(endMenuPreview) object:nil];
}

- (BOOL)presentMenuAnimatedFromHandle:(BOOL)animateFromHandle backdrop:(BOOL)backdrop {
    NSArray<KSBallShortcut *> *shortcuts = self.settingsStore.settings.shortcuts;
    if (shortcuts.count == 0) {
        return NO;
    }

    KSBallSettings *settings = self.settingsStore.settings;
    CGFloat scale = 1.0;
    CGPoint anchor = [self barCenter];
    NSArray<NSValue *> *centers = [KSBallFanLayout centersForItemCount:shortcuts.count anchorCenter:anchor safeBounds:[self menuSafeBounds] edge:[self currentEdge] itemSize:settings.iconSize itemSpacing:settings.iconSpacing ringSpacing:settings.ringSpacing scale:&scale];
    self.menuItemSize = settings.iconSize * scale;
    // 命中范围覆盖到最近两个图标间隙的一半，滑动时不会出现“空档”。
    self.menuHoverRadius = (settings.iconSize + MIN(settings.iconSpacing, settings.ringSpacing)) * scale / 2.0 + 2.0;
    [self updateHoveredItemView:nil];
    [self rebuildMenuItemsForShortcuts:[shortcuts subarrayWithRange:NSMakeRange(0, centers.count)]];
    self.menuVisible = YES;

    if (backdrop) {
        [self showBackdrop];
    }
    [UIView animateWithDuration:0.16 animations:^{
        [self layoutBar];
    }];
    [self.hoverFeedbackGenerator prepare];

    if (!animateFromHandle) {
        [self.menuItemViews enumerateObjectsUsingBlock:^(UIView * _Nonnull itemView, NSUInteger index, BOOL * _Nonnull stop) {
            itemView.center = centers[index].CGPointValue;
        }];
        return YES;
    }
    for (UIView *itemView in self.menuItemViews) {
        itemView.center = anchor;
        itemView.alpha = 0.0;
        itemView.transform = CGAffineTransformMakeScale(0.2, 0.2);
    }
    [UIView animateWithDuration:0.34 delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        [self.menuItemViews enumerateObjectsUsingBlock:^(UIView * _Nonnull itemView, NSUInteger index, BOOL * _Nonnull stop) {
            itemView.center = centers[index].CGPointValue;
            itemView.transform = CGAffineTransformIdentity;
            itemView.alpha = 1.0;
        }];
    } completion:nil];
    return YES;
}

#pragma mark - 毛玻璃背景

- (void)showBackdrop {
    KSBallSettings *settings = self.settingsStore.settings;
    BOOL lightBackdrop = settings.backdropStyle == KSBallBackdropStyleLight;
    // 亮色背景上用深色文字，其余情况保持白字加阴影。
    self.previewNameLabel.textColor = lightBackdrop ? UIColor.blackColor : UIColor.whiteColor;
    self.previewNameLabel.layer.shadowOpacity = lightBackdrop ? 0.0 : 0.5;
    if (settings.backdropStyle == KSBallBackdropStyleNone) {
        [self hideBackdropAnimated:YES];
        return;
    }
    self.backdropRequested = YES;
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:lightBackdrop ? UIBlurEffectStyleSystemThinMaterialLight : UIBlurEffectStyleSystemThinMaterialDark];
    // 收起动画可能还在进行，直接重新淡入。透明度通过视图 alpha 控制毛玻璃的浓淡。
    self.backdropView.hidden = NO;
    [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.backdropView.effect = effect;
        self.backdropView.alpha = settings.backdropOpacity;
    } completion:nil];
}

- (void)hideBackdropAnimated:(BOOL)animated {
    self.backdropRequested = NO;
    if (self.backdropView.hidden) {
        return;
    }
    void (^changes)(void) = ^{
        self.backdropView.effect = nil;
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        // 动画期间可能已重新请求背景，此时保持显示。
        if (!self.backdropRequested) {
            self.backdropView.hidden = YES;
        }
    };
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

#pragma mark - 收起菜单

- (void)dismissMenuAnimated:(BOOL)animated {
    [self cancelMenuPreviewTimer];
    self.previewingMenu = NO;
    [self updateHoveredItemView:nil];
    if (!self.menuVisible && self.menuItemViews.count == 0) {
        return;
    }
    self.menuVisible = NO;
    NSArray<UIView *> *itemViews = [self.menuItemViews copy];
    [self.menuItemViews removeAllObjects];
    self.menuShortcuts = @[];
    CGPoint anchor = [self barCenter];
    void (^changes)(void) = ^{
        for (UIView *itemView in itemViews) {
            itemView.alpha = 0.0;
            itemView.center = anchor;
            itemView.transform = CGAffineTransformMakeScale(0.2, 0.2);
        }
        [self layoutBar];
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        for (UIView *itemView in itemViews) {
            [itemView removeFromSuperview];
        }
    };
    [self hideBackdropAnimated:animated];
    if (animated) {
        [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (void)rebuildMenuItemsForShortcuts:(NSArray<KSBallShortcut *> *)shortcuts {
    for (UIView *itemView in self.menuItemViews) {
        [itemView removeFromSuperview];
    }
    [self.menuItemViews removeAllObjects];
    self.menuShortcuts = shortcuts;

    CGFloat size = self.menuItemSize;
    for (KSBallShortcut *shortcut in shortcuts) {
        UIView *itemView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, size, size)];
        itemView.userInteractionEnabled = NO;
        itemView.layer.shadowColor = UIColor.blackColor.CGColor;
        itemView.layer.shadowOpacity = 0.3;
        itemView.layer.shadowRadius = 5.0;
        itemView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        itemView.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:itemView.bounds].CGPath;

        UIImageView *iconView = [[UIImageView alloc] initWithFrame:itemView.bounds];
        iconView.layer.cornerRadius = size / 2.0;
        iconView.clipsToBounds = YES;
        UIImage *icon = self.iconsByBundleIdentifier[shortcut.bundleIdentifier.lowercaseString];
        if (icon) {
            iconView.image = icon;
            iconView.contentMode = UIViewContentModeScaleAspectFill;
        } else {
            iconView.image = [UIImage systemImageNamed:@"app.fill"];
            iconView.tintColor = UIColor.whiteColor;
            iconView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.95];
            iconView.contentMode = UIViewContentModeCenter;
        }
        [itemView addSubview:iconView];
        // 菜单图标只做展示：选择由悬浮条上的同一次滑动完成，预览期间也不能挡住下层应用的触摸。
        KSBallSetLayerAllowsHitTesting(itemView.layer, NO);
        itemView.accessibilityLabel = shortcut.displayName;
        [self.view insertSubview:itemView belowSubview:self.previewImageView];
        [self.menuItemViews addObject:itemView];
    }
}

- (nullable UIView *)menuItemViewNearPoint:(CGPoint)point {
    UIView *nearestItemView = nil;
    CGFloat nearestDistance = self.menuHoverRadius;
    for (UIView *itemView in self.menuItemViews) {
        CGFloat distance = hypot(itemView.center.x - point.x, itemView.center.y - point.y);
        if (distance <= nearestDistance) {
            nearestDistance = distance;
            nearestItemView = itemView;
        }
    }
    return nearestItemView;
}

- (void)updateHoveredItemView:(nullable UIView *)itemView {
    if (itemView == self.hoveredItemView) {
        return;
    }
    UIView *previousItemView = self.hoveredItemView;
    self.hoveredItemView = itemView;
    if (itemView) {
        // 每移到一个新图标上触发一次 Taptic Engine 震动。
        [self.hoverFeedbackGenerator impactOccurred];
        [self.hoverFeedbackGenerator prepare];
    }

    [UIView animateWithDuration:0.14 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        previousItemView.transform = CGAffineTransformIdentity;
        itemView.transform = CGAffineTransformMakeScale(1.25, 1.25);
    } completion:nil];

    if (!itemView) {
        [UIView animateWithDuration:0.14 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.previewImageView.alpha = 0.0;
            self.previewImageView.transform = CGAffineTransformMakeScale(0.85, 0.85);
            self.previewNameLabel.alpha = 0.0;
        } completion:nil];
        return;
    }

    NSUInteger index = [self.menuItemViews indexOfObjectIdenticalTo:itemView];
    KSBallShortcut *shortcut = index < self.menuShortcuts.count ? self.menuShortcuts[index] : nil;
    UIImage *icon = self.iconsByBundleIdentifier[shortcut.bundleIdentifier.lowercaseString];
    self.previewImageView.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
    self.previewImageView.tintColor = UIColor.whiteColor;
    self.previewNameLabel.text = shortcut.displayName;

    // 预览放在屏幕中央，与扇形菜单重叠时移到扇形另一侧的空白区域。
    CGRect bounds = self.view.bounds;
    CGPoint previewCenter = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds) - 20.0);
    CGRect previewFrame = CGRectMake(previewCenter.x - KSBallPreviewIconSize / 2.0, previewCenter.y - KSBallPreviewIconSize / 2.0, KSBallPreviewIconSize, KSBallPreviewIconSize + 40.0);
    BOOL overlapsMenu = NO;
    for (UIView *menuItemView in self.menuItemViews) {
        if (CGRectIntersectsRect(CGRectInset(menuItemView.frame, -8.0, -8.0), previewFrame)) {
            overlapsMenu = YES;
            break;
        }
    }
    if (overlapsMenu) {
        CGFloat barY = [self barCenter].y;
        previewCenter.y = barY > CGRectGetMidY(bounds) ? CGRectGetHeight(bounds) * 0.25 : CGRectGetHeight(bounds) * 0.72;
    }
    self.previewImageView.transform = CGAffineTransformIdentity;
    self.previewImageView.center = previewCenter;
    CGFloat labelWidth = CGRectGetWidth(bounds) - 48.0;
    self.previewNameLabel.frame = CGRectMake(24.0, previewCenter.y + KSBallPreviewIconSize / 2.0 + 12.0, labelWidth, 24.0);
    if (self.previewImageView.alpha < 0.01) {
        self.previewImageView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    }
    [UIView animateWithDuration:0.16 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.previewImageView.alpha = 1.0;
        self.previewImageView.transform = CGAffineTransformIdentity;
        self.previewNameLabel.alpha = 1.0;
    } completion:nil];
}

- (void)launchShortcut:(KSBallShortcut *)shortcut {
    if (![self.applicationBridge launchBundleIdentifier:shortcut.bundleIdentifier]) {
        [self showFeedback:@"应用不可用或无法启动"];
    }
}

#pragma mark - 手势

// 从悬浮条向内滑出扇形菜单；滑到图标上显示名称并震动，松手启动该应用，在空白处松手则取消。
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            if ([self showMenu]) {
                [self updateHoveredItemView:[self menuItemViewNearPoint:location]];
            }
            break;
        case UIGestureRecognizerStateChanged:
            if (self.menuVisible) {
                [self updateHoveredItemView:[self menuItemViewNearPoint:location]];
            }
            break;
        case UIGestureRecognizerStateEnded: {
            KSBallShortcut *target = nil;
            if (self.menuVisible) {
                UIView *itemView = [self menuItemViewNearPoint:location];
                NSUInteger index = itemView ? [self.menuItemViews indexOfObjectIdenticalTo:itemView] : NSNotFound;
                target = index < self.menuShortcuts.count ? self.menuShortcuts[index] : nil;
            }
            [self dismissMenuAnimated:YES];
            if (target) {
                [self launchShortcut:target];
            }
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self dismissMenuAnimated:YES];
            break;
        default:
            break;
    }
}

// 长按不动进入设置页；长按后拖动可沿边缘移动悬浮条，越过屏幕中线会换到另一侧。
- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            [self dismissMenuAnimated:YES];
            self.dragging = YES;
            self.dragMoved = NO;
            self.dragStartLocation = location;
            self.dragEdge = self.settingsStore.settings.edge;
            self.dragCenterY = [self currentHandleCenterY];
            [UIView animateWithDuration:0.16 animations:^{
                [self layoutBar];
            }];
            break;
        }
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

#pragma mark - 辅助

- (void)showFeedback:(NSString *)message {
    self.feedbackLabel.text = message;
    CGFloat width = MIN(ceil([self.feedbackLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 32.0)].width) + 32.0, CGRectGetWidth(self.view.bounds) - 32.0);
    CGFloat bottom = CGRectGetHeight(self.view.bounds) - MAX(self.view.safeAreaInsets.bottom, 44.0);
    self.feedbackLabel.frame = CGRectMake(CGRectGetMidX(self.view.bounds) - width / 2.0, bottom - 40.0, width, 32.0);
    [UIView animateWithDuration:0.15 animations:^{
        self.feedbackLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 delay:1.4 options:0 animations:^{
            self.feedbackLabel.alpha = 0.0;
        } completion:nil];
    }];
}

- (void)refreshHitTargets {
    // 菜单图标不参与命中测试：整个选择过程都由悬浮条上的同一次滑动手势完成。
    ((KSBallHUDCanvasView *)self.view).interactiveViews = @[self.handleView];
}

@end
