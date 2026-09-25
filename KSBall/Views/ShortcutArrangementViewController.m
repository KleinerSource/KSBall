#import "ShortcutArrangementViewController.h"
#import "KSBallFanLayout.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import <math.h>

// 手指需要落在图标中心这个距离以内才能拿起图标。
static const CGFloat KSBallArrangementPickupSlop = 8.0;

@interface ShortcutArrangementViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong) UIView *handleBar;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedbackGenerator;
// 两个数组始终按当前顺序一一对应。
@property (nonatomic, strong) NSMutableArray<KSBallShortcut *> *shortcuts;
@property (nonatomic, strong) NSMutableArray<UIView *> *itemViews;
@property (nonatomic, copy) NSArray<NSValue *> *slotCenters;
@property (nonatomic) CGFloat itemSize;
@property (nonatomic, strong, nullable) UIView *draggedView;
@property (nonatomic) NSUInteger dragStartIndex;
@property (nonatomic) CGPoint dragTouchOffset;
@end

@implementation ShortcutArrangementViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _shortcuts = [NSMutableArray array];
        _itemViews = [NSMutableArray array];
        _slotCenters = @[];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    self.handleBar = [UIView new];
    self.handleBar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    self.handleBar.layer.cornerRadius = KSBallHandleBarWidth / 2.0;
    [self.view addSubview:self.handleBar];

    self.hintLabel = [UILabel new];
    self.hintLabel.text = @"长按图标拖动调整顺序";
    self.hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    self.hintLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.hintLabel];

    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = @"完成";
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    self.doneButton = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    [self.doneButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.doneButton];

    self.nameLabel = [UILabel new];
    self.nameLabel.textColor = UIColor.whiteColor;
    self.nameLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.92];
    self.nameLabel.layer.cornerRadius = 12.0;
    self.nameLabel.clipsToBounds = YES;
    self.nameLabel.alpha = 0.0;
    [self.view addSubview:self.nameLabel];

    UILongPressGestureRecognizer *pressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePress:)];
    pressRecognizer.minimumPressDuration = 0.2;
    pressRecognizer.delegate = self;
    [self.view addGestureRecognizer:pressRecognizer];
    self.selectionFeedbackGenerator = [UISelectionFeedbackGenerator new];

    [self.shortcuts addObjectsFromArray:self.settingsStore.settings.shortcuts];
    for (KSBallShortcut *shortcut in self.shortcuts) {
        [self.itemViews addObject:[self itemViewForShortcut:shortcut]];
    }
}

- (UIView *)itemViewForShortcut:(KSBallShortcut *)shortcut {
    UIView *itemView = [UIView new];
    itemView.layer.shadowColor = UIColor.blackColor.CGColor;
    itemView.layer.shadowOpacity = 0.3;
    itemView.layer.shadowRadius = 5.0;
    itemView.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    UIImageView *iconView = [UIImageView new];
    iconView.clipsToBounds = YES;
    iconView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIImage *icon = [self.applicationBridge iconForBundleIdentifier:shortcut.bundleIdentifier];
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
    itemView.accessibilityLabel = shortcut.displayName;
    [self.view insertSubview:itemView belowSubview:self.nameLabel];
    return itemView;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 使用与悬浮条相同的几何与布局参数，这里看到的排列就是悬浮条展开后的样子。
    KSBallSettings *settings = self.settingsStore.settings;
    CGRect bounds = self.view.bounds;
    CGPoint anchor = [KSBallFanLayout handleCenterForEdge:settings.edge normalizedPosition:settings.normalizedVerticalPosition inBounds:bounds];
    self.handleBar.frame = CGRectMake(anchor.x - KSBallHandleBarWidth / 2.0, anchor.y - KSBallHandleBarHeight / 2.0, KSBallHandleBarWidth, KSBallHandleBarHeight);

    CGFloat scale = 1.0;
    CGRect safeBounds = [KSBallFanLayout menuSafeBoundsForBounds:bounds safeAreaInsets:self.view.safeAreaInsets];
    self.slotCenters = [KSBallFanLayout centersForItemCount:self.shortcuts.count anchorCenter:anchor safeBounds:safeBounds edge:settings.edge itemSize:settings.iconSize itemSpacing:settings.iconSpacing ringSpacing:settings.ringSpacing scale:&scale];
    self.itemSize = settings.iconSize * scale;
    [self layoutItemsExcludingView:self.draggedView];

    // 提示与完成按钮放在远离扇形的一侧。
    BOOL controlsAtTop = anchor.y > CGRectGetMidY(bounds);
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat controlsY = controlsAtTop ? insets.top + 16.0 : CGRectGetMaxY(bounds) - insets.bottom - 16.0 - 44.0;
    CGSize buttonSize = [self.doneButton sizeThatFits:CGSizeMake(200.0, 44.0)];
    self.doneButton.frame = CGRectMake(CGRectGetMidX(bounds) - MAX(buttonSize.width, 96.0) / 2.0, controlsY, MAX(buttonSize.width, 96.0), 44.0);
    CGFloat hintY = controlsAtTop ? CGRectGetMaxY(self.doneButton.frame) + 10.0 : CGRectGetMinY(self.doneButton.frame) - 30.0;
    self.hintLabel.frame = CGRectMake(24.0, hintY, CGRectGetWidth(bounds) - 48.0, 20.0);
}

- (void)layoutItemsExcludingView:(nullable UIView *)excludedView {
    CGFloat size = self.itemSize;
    [self.itemViews enumerateObjectsUsingBlock:^(UIView * _Nonnull itemView, NSUInteger index, BOOL * _Nonnull stop) {
        if (index >= self.slotCenters.count || itemView == excludedView) {
            return;
        }
        itemView.bounds = CGRectMake(0.0, 0.0, size, size);
        itemView.center = self.slotCenters[index].CGPointValue;
        itemView.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:itemView.bounds].CGPath;
        UIView *iconView = itemView.subviews.firstObject;
        iconView.frame = itemView.bounds;
        iconView.layer.cornerRadius = size / 2.0;
    }];
}

#pragma mark - 拖动排序

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    CGPoint location = [gestureRecognizer locationInView:self.view];
    return !CGRectContainsPoint(self.doneButton.frame, location) && [self itemIndexAtPoint:location] != NSNotFound;
}

- (NSUInteger)itemIndexAtPoint:(CGPoint)point {
    CGFloat radius = self.itemSize / 2.0 + KSBallArrangementPickupSlop;
    __block NSUInteger foundIndex = NSNotFound;
    __block CGFloat nearestDistance = CGFLOAT_MAX;
    [self.itemViews enumerateObjectsUsingBlock:^(UIView * _Nonnull itemView, NSUInteger index, BOOL * _Nonnull stop) {
        CGFloat distance = hypot(itemView.center.x - point.x, itemView.center.y - point.y);
        if (distance <= radius && distance < nearestDistance) {
            nearestDistance = distance;
            foundIndex = index;
        }
    }];
    return foundIndex;
}

- (NSUInteger)nearestSlotIndexToPoint:(CGPoint)point {
    __block NSUInteger nearestIndex = 0;
    __block CGFloat nearestDistance = CGFLOAT_MAX;
    [self.slotCenters enumerateObjectsUsingBlock:^(NSValue * _Nonnull value, NSUInteger index, BOOL * _Nonnull stop) {
        CGPoint center = value.CGPointValue;
        CGFloat distance = hypot(center.x - point.x, center.y - point.y);
        if (distance < nearestDistance) {
            nearestDistance = distance;
            nearestIndex = index;
        }
    }];
    return nearestIndex;
}

- (void)handlePress:(UILongPressGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            NSUInteger index = [self itemIndexAtPoint:location];
            if (index == NSNotFound) {
                return;
            }
            UIView *itemView = self.itemViews[index];
            self.draggedView = itemView;
            self.dragStartIndex = index;
            self.dragTouchOffset = CGPointMake(itemView.center.x - location.x, itemView.center.y - location.y);
            [self.view bringSubviewToFront:itemView];
            [self.view bringSubviewToFront:self.nameLabel];
            [self.selectionFeedbackGenerator prepare];
            [self.selectionFeedbackGenerator selectionChanged];
            [UIView animateWithDuration:0.15 animations:^{
                itemView.transform = CGAffineTransformMakeScale(1.2, 1.2);
                itemView.layer.shadowOpacity = 0.5;
            }];
            [self showNameForShortcut:self.shortcuts[index] aboveView:itemView];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            UIView *itemView = self.draggedView;
            if (!itemView) {
                return;
            }
            itemView.center = CGPointMake(location.x + self.dragTouchOffset.x, location.y + self.dragTouchOffset.y);
            [self showNameForShortcut:self.shortcuts[[self.itemViews indexOfObjectIdenticalTo:itemView]] aboveView:itemView];
            NSUInteger currentIndex = [self.itemViews indexOfObjectIdenticalTo:itemView];
            NSUInteger targetIndex = [self nearestSlotIndexToPoint:itemView.center];
            if (targetIndex == currentIndex || currentIndex == NSNotFound) {
                return;
            }
            // 与主屏图标一样，拖到新位置时其余图标实时让位。
            KSBallShortcut *shortcut = self.shortcuts[currentIndex];
            [self.shortcuts removeObjectAtIndex:currentIndex];
            [self.shortcuts insertObject:shortcut atIndex:targetIndex];
            [self.itemViews removeObjectAtIndex:currentIndex];
            [self.itemViews insertObject:itemView atIndex:targetIndex];
            [self.selectionFeedbackGenerator selectionChanged];
            [UIView animateWithDuration:0.22 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                [self layoutItemsExcludingView:itemView];
            } completion:nil];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            UIView *itemView = self.draggedView;
            if (!itemView) {
                return;
            }
            self.draggedView = nil;
            NSUInteger finalIndex = [self.itemViews indexOfObjectIdenticalTo:itemView];
            [UIView animateWithDuration:0.22 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                itemView.transform = CGAffineTransformIdentity;
                itemView.layer.shadowOpacity = 0.3;
                [self layoutItemsExcludingView:nil];
                self.nameLabel.alpha = 0.0;
            } completion:nil];
            if (finalIndex != NSNotFound && finalIndex != self.dragStartIndex) {
                [self.settingsStore moveShortcutFromIndex:self.dragStartIndex toIndex:finalIndex];
            }
            break;
        }
        default:
            break;
    }
}

- (void)showNameForShortcut:(KSBallShortcut *)shortcut aboveView:(UIView *)itemView {
    self.nameLabel.text = shortcut.displayName;
    CGFloat width = MIN(ceil([self.nameLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 24.0)].width) + 20.0, CGRectGetWidth(self.view.bounds) - 32.0);
    CGFloat y = CGRectGetMinY(itemView.frame) - 32.0;
    if (y < self.view.safeAreaInsets.top) {
        y = CGRectGetMaxY(itemView.frame) + 8.0;
    }
    CGFloat x = MIN(MAX(itemView.center.x - width / 2.0, 16.0), CGRectGetWidth(self.view.bounds) - 16.0 - width);
    self.nameLabel.frame = CGRectMake(x, y, width, 24.0);
    self.nameLabel.alpha = 1.0;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

@end
