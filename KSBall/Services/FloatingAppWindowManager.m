#import "FloatingAppWindowManager.h"
#import "FloatingAppSceneHost.h"
#import "FloatingAppWindowView.h"
#import "KSBallFloatingWindowLayout.h"
#import "KSBallLayerHitTesting.h"
#import "KSBallSettings.h"
#import "SystemApplicationBridge.h"

static const CGFloat KSBallFloatingDockPlateCornerRadius = 14.0;
static const CGFloat KSBallFloatingDockHandleWidth = 30.0;
static const CGFloat KSBallFloatingDockHandleHeight = 54.0;
// 应用退出后先显示提示，停留片刻再关闭窗口。
static const NSTimeInterval KSBallFloatingExitNoticeDuration = 1.2;

@interface KSBallFloatingWindowEntry : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, strong) FloatingAppWindowView *windowView;
@property (nonatomic, strong, nullable) FloatingAppSceneHost *host;
/// 收起前的窗口位置，恢复时回到这里。
@property (nonatomic) CGRect restoredFrame;
@end

@implementation KSBallFloatingWindowEntry
@end

@interface FloatingAppWindowManager () <FloatingAppWindowViewDelegate>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong) NSMutableArray<KSBallFloatingWindowEntry *> *entries;
/// 收纳区中的窗口，按收起的先后顺序从上往下排列。
@property (nonatomic, strong) NSMutableArray<KSBallFloatingWindowEntry *> *minimizedEntries;
@property (nonatomic, strong) UIVisualEffectView *dockPlateView;
@property (nonatomic, strong) UIView *dockHandleView;
@property (nonatomic, strong) UIImageView *dockHandleIconView;
@property (nonatomic) KSBallEdge dockEdge;
@property (nonatomic) BOOL windowsHidden;
@property (nonatomic) BOOL dockCollapsed;
@property (nonatomic) CGFloat dockHandleCenterY;
- (void)minimizeExpandedEntriesExcept:(nullable KSBallFloatingWindowEntry *)focusedEntry;
- (void)collapseDock;
- (void)expandDock;
- (void)layoutDockHandle;
@end

@implementation FloatingAppWindowManager

- (instancetype)initWithContainerView:(UIView *)containerView applicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super init];
    if (self) {
        _containerView = containerView;
        _applicationBridge = applicationBridge;
        _entries = [NSMutableArray array];
        _minimizedEntries = [NSMutableArray array];
        _dockEdge = KSBallEdgeRight;
        _userInterfaceStyle = UIUserInterfaceStyleLight;

        // 收纳区底板只包住缩略图，不占满整条屏幕边缘；缩略图之间的缝隙也不能漏触摸到下层应用。
        _dockPlateView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        _dockPlateView.layer.cornerRadius = KSBallFloatingDockPlateCornerRadius;
        _dockPlateView.layer.cornerCurve = kCACornerCurveContinuous;
        _dockPlateView.clipsToBounds = YES;
        _dockPlateView.hidden = YES;
        _dockPlateView.alpha = 0.0;
        KSBallSetLayerHitTestsAsOpaque(_dockPlateView.layer, YES);
        [containerView addSubview:_dockPlateView];

        _dockHandleView = [UIView new];
        _dockHandleView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _dockHandleView.layer.cornerRadius = 12.0;
        _dockHandleView.layer.cornerCurve = kCACornerCurveContinuous;
        _dockHandleView.layer.borderWidth = 0.5;
        _dockHandleView.layer.borderColor = UIColor.separatorColor.CGColor;
        _dockHandleView.isAccessibilityElement = YES;
        _dockHandleView.accessibilityLabel = @"显示悬浮应用边栏";
        _dockHandleView.accessibilityTraits = UIAccessibilityTraitButton;
        _dockHandleView.hidden = YES;
        KSBallSetLayerHitTestsAsOpaque(_dockHandleView.layer, YES);
        _dockHandleIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
        _dockHandleIconView.contentMode = UIViewContentModeScaleAspectFit;
        _dockHandleIconView.tintColor = UIColor.secondaryLabelColor;
        [_dockHandleView addSubview:_dockHandleIconView];
        UITapGestureRecognizer *showDockRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(expandDock)];
        showDockRecognizer.cancelsTouchesInView = NO;
        [_dockHandleView addGestureRecognizer:showDockRecognizer];
        [containerView addSubview:_dockHandleView];
    }
    return self;
}

- (void)dealloc {
    for (KSBallFloatingWindowEntry *entry in _entries) {
        [entry.host invalidate];
    }
}

#pragma mark - 几何

- (CGSize)screenSize {
    return UIScreen.mainScreen.bounds.size;
}

- (CGRect)bounds {
    return self.containerView.bounds;
}

- (UIEdgeInsets)safeAreaInsets {
    return self.containerView.safeAreaInsets;
}

- (CGRect)clampedFrame:(CGRect)frame {
    return [KSBallFloatingWindowLayout clampedFrame:frame inBounds:[self bounds] safeAreaInsets:[self safeAreaInsets]];
}

#pragma mark - 查询

- (NSArray<UIView *> *)interactiveViews {
    if (self.windowsHidden) {
        return @[];
    }
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithCapacity:self.entries.count + 1];
    for (KSBallFloatingWindowEntry *entry in self.entries) {
        if (self.dockCollapsed && [self isEntryMinimized:entry]) {
            continue;
        }
        [views addObject:entry.windowView];
    }
    if (self.minimizedEntries.count > 0) {
        [views addObject:self.dockCollapsed ? self.dockHandleView : self.dockPlateView];
    }
    return views;
}

- (nullable KSBallFloatingWindowEntry *)entryForWindowView:(FloatingAppWindowView *)windowView {
    for (KSBallFloatingWindowEntry *entry in self.entries) {
        if (entry.windowView == windowView) {
            return entry;
        }
    }
    return nil;
}

- (nullable KSBallFloatingWindowEntry *)entryForBundleIdentifier:(NSString *)bundleIdentifier {
    for (KSBallFloatingWindowEntry *entry in self.entries) {
        if ([entry.bundleIdentifier caseInsensitiveCompare:bundleIdentifier] == NSOrderedSame) {
            return entry;
        }
    }
    return nil;
}

- (BOOL)isEntryMinimized:(KSBallFloatingWindowEntry *)entry {
    return [self.minimizedEntries indexOfObjectIdenticalTo:entry] != NSNotFound;
}

- (void)notifyInteractiveViewsDidChange {
    if (self.interactiveViewsDidChangeHandler) {
        self.interactiveViewsDidChangeHandler();
    }
}

- (void)showFeedback:(NSString *)message {
    if (self.feedbackHandler) {
        self.feedbackHandler(message);
    }
}

#pragma mark - 打开

- (void)openShortcut:(KSBallShortcut *)shortcut icon:(UIImage *)icon fromPoint:(CGPoint)point {
    KSBallFloatingWindowEntry *existingEntry = [self entryForBundleIdentifier:shortcut.bundleIdentifier];
    if (existingEntry) {
        if ([self isEntryMinimized:existingEntry]) {
            [self restoreEntry:existingEntry];
        } else {
            [self bringEntryToFront:existingEntry];
        }
        return;
    }
    if (self.entries.count >= KSBallMaximumFloatingWindows) {
        [self showFeedback:[NSString stringWithFormat:@"最多同时悬浮 %lu 个应用", (unsigned long)KSBallMaximumFloatingWindows]];
        return;
    }
    [self minimizeExpandedEntriesExcept:nil];

    CGSize screenSize = [self screenSize];
    FloatingAppWindowView *windowView = [[FloatingAppWindowView alloc] initWithDisplayName:shortcut.displayName icon:icon screenSize:screenSize];
    windowView.delegate = self;
    windowView.overrideUserInterfaceStyle = self.userInterfaceStyle;
    NSUInteger expandedCount = self.entries.count - self.minimizedEntries.count;
    windowView.frame = [KSBallFloatingWindowLayout defaultFrameForIndex:expandedCount scale:KSBallFloatingWindowDefaultScale screenSize:screenSize bounds:[self bounds] safeAreaInsets:[self safeAreaInsets]];
    [self.containerView insertSubview:windowView belowSubview:self.dockPlateView];

    KSBallFloatingWindowEntry *entry = [KSBallFloatingWindowEntry new];
    entry.bundleIdentifier = shortcut.bundleIdentifier;
    entry.windowView = windowView;
    entry.restoredFrame = windowView.frame;
    [self.entries addObject:entry];
    [self notifyInteractiveViewsDidChange];

    // 从悬浮条的位置放大弹出。
    CGPoint center = windowView.center;
    CGAffineTransform startTransform = CGAffineTransformMakeTranslation(point.x - center.x, point.y - center.y);
    windowView.transform = CGAffineTransformScale(startTransform, 0.1, 0.1);
    windowView.alpha = 0.0;
    [UIView animateWithDuration:0.42 delay:0.0 usingSpringWithDamping:0.82 initialSpringVelocity:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        windowView.transform = CGAffineTransformIdentity;
        windowView.alpha = 1.0;
    } completion:nil];

    [self startHostForEntry:entry];
}

- (void)startHostForEntry:(KSBallFloatingWindowEntry *)entry {
    FloatingAppSceneHost *host = [[FloatingAppSceneHost alloc] initWithBundleIdentifier:entry.bundleIdentifier];
    host.sceneSafeAreaInsets = [self safeAreaInsets];
    host.userInterfaceStyle = self.userInterfaceStyle;
    __weak typeof(self) weakSelf = self;
    __weak KSBallFloatingWindowEntry *weakEntry = entry;
    host.processExitHandler = ^{
        [weakSelf handleProcessExitForEntry:weakEntry];
    };
    entry.host = host;
    [host startWithCompletion:^(BOOL success, NSString * _Nullable failureReason) {
        KSBallFloatingWindowEntry *strongEntry = weakEntry;
        if (!strongEntry || [weakSelf.entries indexOfObjectIdenticalTo:strongEntry] == NSNotFound) {
            return;
        }
        if (success) {
            [strongEntry.windowView setPresentationView:host.presentationView];
            return;
        }
        NSString *message = [NSString stringWithFormat:@"无法打开：%@", failureReason ?: @"未知原因"];
        [strongEntry.windowView showStatusMessage:message];
        [weakSelf showFeedback:message];
    }];
}

- (void)handleProcessExitForEntry:(KSBallFloatingWindowEntry *)entry {
    if (!entry || [self.entries indexOfObjectIdenticalTo:entry] == NSNotFound) {
        return;
    }
    [entry.windowView setPresentationView:nil];
    [entry.host invalidate];
    entry.host = nil;
    [entry.windowView showStatusMessage:@"应用已退出"];
    __weak typeof(self) weakSelf = self;
    __weak KSBallFloatingWindowEntry *weakEntry = entry;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(KSBallFloatingExitNoticeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KSBallFloatingWindowEntry *strongEntry = weakEntry;
        if (strongEntry) {
            [weakSelf closeEntry:strongEntry animated:YES];
        }
    });
}

#pragma mark - 关闭

- (void)closeEntry:(KSBallFloatingWindowEntry *)entry animated:(BOOL)animated {
    if ([self.entries indexOfObjectIdenticalTo:entry] == NSNotFound) {
        return;
    }
    [entry.host invalidate];
    entry.host = nil;
    BOOL wasMinimized = [self isEntryMinimized:entry];
    [self.entries removeObjectIdenticalTo:entry];
    [self.minimizedEntries removeObjectIdenticalTo:entry];

    FloatingAppWindowView *windowView = entry.windowView;
    windowView.delegate = nil;
    windowView.userInteractionEnabled = NO;
    // 关闭动画期间窗口可能仍按不透明拦截触摸，先从命中区域中移除。
    [self notifyInteractiveViewsDidChange];
    void (^changes)(void) = ^{
        windowView.alpha = 0.0;
        windowView.transform = CGAffineTransformScale(windowView.transform, 0.9, 0.9);
        if (wasMinimized) {
            [self layoutDock];
        }
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        [windowView removeFromSuperview];
        [self updateDockPlateVisibility];
    };
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (void)closeAllWindows {
    for (KSBallFloatingWindowEntry *entry in [self.entries copy]) {
        [self closeEntry:entry animated:NO];
    }
}

- (void)openEntryFullScreen:(KSBallFloatingWindowEntry *)entry {
    NSString *bundleIdentifier = entry.bundleIdentifier;
    // 只收回悬浮场景、保留进程，SpringBoard 会为同一进程创建全屏场景，应用状态得以保留。
    [entry.host detachForFullScreenLaunch];
    entry.host = nil;
    [self closeEntry:entry animated:YES];
    if (![self.applicationBridge launchBundleIdentifier:bundleIdentifier]) {
        [self showFeedback:@"应用不可用或无法启动"];
    }
}

#pragma mark - 收纳区

- (void)minimizeEntry:(KSBallFloatingWindowEntry *)entry toEdge:(KSBallEdge)edge {
    if ([self isEntryMinimized:entry]) {
        return;
    }
    // 第一个收起的窗口决定收纳区在哪一侧，之后的窗口都排进同一列。
    if (self.minimizedEntries.count == 0) {
        self.dockEdge = edge;
    }
    entry.restoredFrame = [self clampedFrame:entry.windowView.frame];
    [self.minimizedEntries addObject:entry];
    entry.windowView.minimizedEdge = self.dockEdge;
    [self.containerView bringSubviewToFront:entry.windowView];
    if (self.dockCollapsed) {
        [self.containerView bringSubviewToFront:self.dockHandleView];
    }
    [self updateDockPlateVisibility];
    [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        entry.windowView.minimized = YES;
        [self layoutDock];
        [entry.windowView layoutIfNeeded];
    } completion:nil];
    [self notifyInteractiveViewsDidChange];
}

- (void)minimizeExpandedEntriesExcept:(nullable KSBallFloatingWindowEntry *)focusedEntry {
    KSBallEdge edge = self.dockEdge;
    BOOL hasDockEdge = self.minimizedEntries.count > 0;
    for (KSBallFloatingWindowEntry *entry in [self.entries copy]) {
        if (entry == focusedEntry || [self isEntryMinimized:entry]) {
            continue;
        }
        if (!hasDockEdge) {
            edge = entry.windowView.center.x < CGRectGetMidX([self bounds]) ? KSBallEdgeLeft : KSBallEdgeRight;
            hasDockEdge = YES;
        }
        [self minimizeEntry:entry toEdge:edge];
    }
}

- (void)restoreEntry:(KSBallFloatingWindowEntry *)entry {
    if (![self isEntryMinimized:entry]) {
        return;
    }
    [self minimizeExpandedEntriesExcept:entry];
    [self.minimizedEntries removeObjectIdenticalTo:entry];
    if (self.minimizedEntries.count == 0) {
        self.dockCollapsed = NO;
        self.dockHandleView.hidden = YES;
    }
    [self.containerView insertSubview:entry.windowView belowSubview:self.dockPlateView];
    CGRect frame = [self clampedFrame:entry.restoredFrame];
    [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        entry.windowView.minimized = NO;
        entry.windowView.frame = frame;
        [entry.windowView layoutIfNeeded];
        [self layoutDock];
    } completion:^(BOOL finished) {
        [self updateDockPlateVisibility];
    }];
    [self notifyInteractiveViewsDidChange];
}

// 在动画块中调用：把收纳区中的缩略图依次排好，底板随之伸缩。
- (void)layoutDock {
    CGSize screenSize = [self screenSize];
    CGRect bounds = [self bounds];
    UIEdgeInsets safeAreaInsets = [self safeAreaInsets];
    [self.minimizedEntries enumerateObjectsUsingBlock:^(KSBallFloatingWindowEntry * _Nonnull entry, NSUInteger index, BOOL * _Nonnull stop) {
        CGRect frame = [KSBallFloatingWindowLayout dockSlotFrameAtIndex:index edge:self.dockEdge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
        if (self.dockCollapsed) {
            frame.origin.x = self.dockEdge == KSBallEdgeLeft ? CGRectGetMinX(bounds) - CGRectGetWidth(frame) : CGRectGetMaxX(bounds);
        }
        entry.windowView.frame = frame;
    }];
    NSUInteger count = self.minimizedEntries.count;
    if (count > 0) {
        CGRect frame = [KSBallFloatingWindowLayout dockPlateFrameForCount:count edge:self.dockEdge screenSize:screenSize bounds:bounds safeAreaInsets:safeAreaInsets];
        if (self.dockCollapsed) {
            frame.origin.x = self.dockEdge == KSBallEdgeLeft ? CGRectGetMinX(bounds) - CGRectGetWidth(frame) : CGRectGetMaxX(bounds);
        }
        self.dockPlateView.frame = frame;
    }
    self.dockPlateView.alpha = count > 0 && !self.dockCollapsed ? 1.0 : 0.0;
}

- (void)layoutDockHandle {
    CGRect bounds = [self bounds];
    CGRect safeBounds = UIEdgeInsetsInsetRect(bounds, [self safeAreaInsets]);
    CGFloat minY = CGRectGetMinY(safeBounds);
    CGFloat maxY = MAX(minY, CGRectGetMaxY(safeBounds) - KSBallFloatingDockHandleHeight);
    CGFloat y = self.dockHandleCenterY - KSBallFloatingDockHandleHeight / 2.0;
    y = MIN(MAX(y, minY), maxY);
    CGFloat x = self.dockEdge == KSBallEdgeLeft ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds) - KSBallFloatingDockHandleWidth;
    self.dockHandleView.frame = CGRectMake(x, y, KSBallFloatingDockHandleWidth, KSBallFloatingDockHandleHeight);
    self.dockHandleIconView.frame = CGRectMake(9.0, 20.0, 12.0, 14.0);
    NSString *symbol = self.dockEdge == KSBallEdgeLeft ? @"chevron.right" : @"chevron.left";
    self.dockHandleIconView.image = [UIImage systemImageNamed:symbol];
}

- (void)collapseDock {
    if (self.dockCollapsed || self.minimizedEntries.count == 0) {
        return;
    }
    self.dockHandleCenterY = CGRectGetMidY(self.dockPlateView.frame);
    self.dockCollapsed = YES;
    self.dockHandleView.hidden = NO;
    [self layoutDockHandle];
    [self.containerView bringSubviewToFront:self.dockHandleView];
    [self notifyInteractiveViewsDidChange];
    [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        for (KSBallFloatingWindowEntry *entry in self.minimizedEntries) {
            entry.windowView.transform = CGAffineTransformIdentity;
        }
        [self layoutDock];
    } completion:nil];
}

- (void)expandDock {
    if (!self.dockCollapsed || self.minimizedEntries.count == 0) {
        return;
    }
    self.dockCollapsed = NO;
    self.dockHandleView.hidden = YES;
    self.dockPlateView.hidden = NO;
    [self notifyInteractiveViewsDidChange];
    [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        [self layoutDock];
    } completion:nil];
}

// 底板按不透明拦截触摸，透明度为 0 时也会挡住下层，必须真正隐藏。
- (void)updateDockPlateVisibility {
    BOOL visible = self.minimizedEntries.count > 0;
    if (!visible) {
        self.dockCollapsed = NO;
        self.dockHandleView.hidden = YES;
    }
    if (visible && self.dockPlateView.hidden) {
        CGSize screenSize = [self screenSize];
        self.dockPlateView.frame = [KSBallFloatingWindowLayout dockPlateFrameForCount:1 edge:self.dockEdge screenSize:screenSize bounds:[self bounds] safeAreaInsets:[self safeAreaInsets]];
        self.dockPlateView.alpha = 0.0;
    }
    self.dockPlateView.hidden = !visible;
    self.dockHandleView.hidden = !visible || !self.dockCollapsed;
    [self notifyInteractiveViewsDidChange];
}

#pragma mark - 状态

- (void)bringEntryToFront:(KSBallFloatingWindowEntry *)entry {
    if ([self isEntryMinimized:entry]) {
        return;
    }
    [self minimizeExpandedEntriesExcept:entry];
    [self.containerView insertSubview:entry.windowView belowSubview:self.dockPlateView];
}

- (void)setWindowsHidden:(BOOL)hidden {
    if (_windowsHidden == hidden) {
        return;
    }
    _windowsHidden = hidden;
    self.containerView.hidden = hidden;
    [self notifyInteractiveViewsDidChange];
}

- (void)setUserInterfaceStyle:(UIUserInterfaceStyle)userInterfaceStyle {
    if (_userInterfaceStyle == userInterfaceStyle) {
        return;
    }
    _userInterfaceStyle = userInterfaceStyle;
    self.dockPlateView.overrideUserInterfaceStyle = userInterfaceStyle;
    self.dockHandleView.overrideUserInterfaceStyle = userInterfaceStyle;
    for (KSBallFloatingWindowEntry *entry in self.entries) {
        entry.windowView.overrideUserInterfaceStyle = userInterfaceStyle;
        [entry.host updateUserInterfaceStyle:userInterfaceStyle];
    }
}

#pragma mark - FloatingAppWindowViewDelegate

- (void)floatingAppWindowViewDidRequestClose:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self closeEntry:entry animated:YES];
    }
}

- (void)floatingAppWindowViewDidRequestMinimize:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (!entry) {
        return;
    }
    KSBallEdge edge = windowView.center.x < CGRectGetMidX([self bounds]) ? KSBallEdgeLeft : KSBallEdgeRight;
    [self minimizeEntry:entry toEdge:edge];
}

- (void)floatingAppWindowViewDidRequestFullScreen:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self openEntryFullScreen:entry];
    }
}

- (void)floatingAppWindowViewDidRequestRestore:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self restoreEntry:entry];
    }
}

- (void)floatingAppWindowViewDidRequestHideDock:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry && [self isEntryMinimized:entry]) {
        [self collapseDock];
    }
}

- (void)floatingAppWindowViewDidBeginInteraction:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (entry) {
        [self bringEntryToFront:entry];
    }
}

- (void)floatingAppWindowViewDidEndMoving:(FloatingAppWindowView *)windowView {
    KSBallFloatingWindowEntry *entry = [self entryForWindowView:windowView];
    if (!entry || [self isEntryMinimized:entry]) {
        return;
    }
    KSBallEdge edge = KSBallEdgeRight;
    if ([KSBallFloatingWindowLayout shouldMinimizeFrame:windowView.frame inBounds:[self bounds] edge:&edge]) {
        [self minimizeEntry:entry toEdge:edge];
        return;
    }
    CGRect frame = [self clampedFrame:windowView.frame];
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        windowView.frame = frame;
        [windowView layoutIfNeeded];
    } completion:nil];
}

@end
