#import "FloatingHUDViewController.h"
#import "KSBallFanLayout.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"
#import <math.h>

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
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSMutableArray<UIButton *> *menuButtons;
@property (nonatomic, strong) NSMutableDictionary<NSString *, KSBallShortcut *> *shortcutsByIdentifier;
@property (nonatomic, strong) UILabel *feedbackLabel;
@property (nonatomic) BOOL menuVisible;
@property (nonatomic) BOOL isDragging;
@property (nonatomic) BOOL ignoreNextTap;
@property (nonatomic) BOOL longPressActive;
@property (nonatomic) BOOL longPressMoved;
@property (nonatomic) BOOL panOpenedMenu;
@property (nonatomic) CFTimeInterval touchStartTime;
@property (nonatomic) CGPoint touchStartLocation;
@property (nonatomic) CGPoint touchStartButtonCenter;
@end

@implementation FloatingHUDViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _menuButtons = [NSMutableArray array];
        _shortcutsByIdentifier = [NSMutableDictionary dictionary];
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

    self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingButton.accessibilityLabel = @"KSBall 快捷菜单";
    self.floatingButton.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.84];
    self.floatingButton.tintColor = UIColor.whiteColor;
    self.floatingButton.layer.cornerRadius = 28.0;
    self.floatingButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.floatingButton.layer.shadowOpacity = 0.24;
    self.floatingButton.layer.shadowRadius = 8.0;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0.0, 3.0);
    [self.floatingButton setImage:[UIImage systemImageNamed:@"circle.grid.2x2.fill"] forState:UIControlStateNormal];
    [self.floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.floatingButton addTarget:self action:@selector(beginFloatingButtonPress:forEvent:) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:self.floatingButton];

    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    panRecognizer.delegate = self;
    panRecognizer.cancelsTouchesInView = NO;
    [self.floatingButton addGestureRecognizer:panRecognizer];
    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressRecognizer.minimumPressDuration = 0.55;
    longPressRecognizer.allowableMovement = CGFLOAT_MAX;
    longPressRecognizer.delegate = self;
    longPressRecognizer.cancelsTouchesInView = NO;
    [self.floatingButton addGestureRecognizer:longPressRecognizer];

    self.feedbackLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.feedbackLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.86];
    self.feedbackLabel.textColor = UIColor.whiteColor;
    self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
    self.feedbackLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.feedbackLabel.layer.cornerRadius = 12.0;
    self.feedbackLabel.clipsToBounds = YES;
    self.feedbackLabel.alpha = 0.0;
    [self.view addSubview:self.feedbackLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFromSettings) name:KSBallSettingsDidChangeNotification object:self.settingsStore];
    [self reloadFromSettings];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self positionFloatingButton];
    [self layoutMenuButtons];
}

- (void)reloadFromSettings {
    if (!self.isViewLoaded) {
        return;
    }
    [self dismissMenuAnimated:NO];
    [self positionFloatingButton];
}

- (void)positionFloatingButton {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, UIEdgeInsetsMake(insets.top + 8.0, insets.left + 8.0, insets.bottom + 8.0, insets.right + 8.0));
    KSBallSettings *settings = self.settingsStore.settings;
    CGFloat x = settings.edge == KSBallEdgeLeft ? CGRectGetMinX(safeBounds) + 28.0 : CGRectGetMaxX(safeBounds) - 28.0;
    CGFloat minY = CGRectGetMinY(safeBounds) + 28.0;
    CGFloat maxY = CGRectGetMaxY(safeBounds) - 28.0;
    CGFloat y = minY + (maxY - minY) * settings.normalizedVerticalPosition;
    self.floatingButton.bounds = CGRectMake(0.0, 0.0, 56.0, 56.0);
    self.floatingButton.center = CGPointMake(x, y);
    [self refreshHitTargets];
}

- (void)toggleMenu {
    if (self.isDragging || self.ignoreNextTap) {
        self.ignoreNextTap = NO;
        return;
    }
    if (self.menuVisible) {
        [self dismissMenuAnimated:YES];
    } else {
        [self showMenu];
    }
}

- (void)showMenu {
    NSArray<KSBallShortcut *> *shortcuts = self.settingsStore.settings.shortcuts;
    if (shortcuts.count == 0) {
        [self showFeedback:@"请先长按悬浮球添加应用"];
        return;
    }

    [self rebuildMenuForShortcuts:shortcuts];
    self.menuVisible = YES;
    [self layoutMenuButtons];
    self.floatingButton.transform = CGAffineTransformMakeRotation((CGFloat)M_PI_4);
    for (UIButton *button in self.menuButtons) {
        button.hidden = NO;
        button.alpha = 0.0;
        button.transform = CGAffineTransformMakeScale(0.45, 0.45);
    }
    [self refreshHitTargets];
    [UIView animateWithDuration:0.18 animations:^{
        for (UIButton *button in self.menuButtons) {
            button.alpha = 1.0;
            button.transform = CGAffineTransformIdentity;
        }
    }];
}

- (void)dismissMenuAnimated:(BOOL)animated {
    if (!self.menuVisible && self.menuButtons.count == 0) {
        return;
    }
    self.menuVisible = NO;
    void (^changes)(void) = ^{
        self.floatingButton.transform = CGAffineTransformIdentity;
        for (UIButton *button in self.menuButtons) {
            button.alpha = 0.0;
            button.transform = CGAffineTransformMakeScale(0.45, 0.45);
        }
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        for (UIButton *button in self.menuButtons) {
            button.hidden = YES;
            button.transform = CGAffineTransformIdentity;
        }
        [self refreshHitTargets];
    };
    if (animated) {
        [UIView animateWithDuration:0.14 animations:changes completion:completion];
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

    NSMutableDictionary<NSString *, KSBallApplication *> *applicationsByIdentifier = [NSMutableDictionary dictionary];
    for (KSBallApplication *application in self.applicationBridge.availableApplications) {
        applicationsByIdentifier[application.bundleIdentifier.lowercaseString] = application;
    }

    for (KSBallShortcut *shortcut in shortcuts) {
        KSBallApplication *application = applicationsByIdentifier[shortcut.bundleIdentifier.lowercaseString];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.bounds = CGRectMake(0.0, 0.0, 50.0, 50.0);
        button.layer.cornerRadius = 14.0;
        button.clipsToBounds = YES;
        button.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.92];
        button.tintColor = UIColor.whiteColor;
        button.accessibilityLabel = shortcut.displayName;
        button.accessibilityIdentifier = shortcut.identifier.UUIDString;
        UIImage *icon = application.icon ?: [UIImage systemImageNamed:@"app.fill"];
        [button setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.contentEdgeInsets = UIEdgeInsetsMake(7.0, 7.0, 7.0, 7.0);
        if (!application) {
            button.alpha = 0.55;
        }
        [button addTarget:self action:@selector(launchShortcut:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
        [self.menuButtons addObject:button];
        self.shortcutsByIdentifier[shortcut.identifier.UUIDString] = shortcut;
    }
}

- (void)layoutMenuButtons {
    if (!self.menuVisible || self.menuButtons.count == 0) {
        return;
    }
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, UIEdgeInsetsMake(insets.top + 8.0, insets.left + 8.0, insets.bottom + 8.0, insets.right + 8.0));
    KSBallSettings *settings = self.settingsStore.settings;
    NSArray<NSValue *> *centers = [KSBallFanLayout centersForItemCount:self.menuButtons.count anchorCenter:self.floatingButton.center safeBounds:safeBounds edge:settings.edge bias:settings.fanBias];
    [centers enumerateObjectsUsingBlock:^(NSValue * _Nonnull value, NSUInteger index, BOOL * _Nonnull stop) {
        self.menuButtons[index].center = value.CGPointValue;
    }];
    [self refreshHitTargets];
}

- (void)launchShortcut:(UIButton *)sender {
    KSBallShortcut *shortcut = self.shortcutsByIdentifier[sender.accessibilityIdentifier];
    [self dismissMenuAnimated:YES];
    if (!shortcut || ![self.applicationBridge launchBundleIdentifier:shortcut.bundleIdentifier]) {
        [self showFeedback:@"应用不可用或无法启动"];
    }
}

- (void)beginFloatingButtonPress:(UIButton *)sender forEvent:(UIEvent *)event {
    (void)sender;
    UITouch *touch = event.allTouches.anyObject;
    self.touchStartTime = NSProcessInfo.processInfo.systemUptime;
    self.touchStartLocation = touch ? [touch locationInView:self.view] : self.floatingButton.center;
    self.touchStartButtonCenter = self.floatingButton.center;
    self.panOpenedMenu = NO;
    self.longPressMoved = NO;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.longPressActive = YES;
        self.ignoreNextTap = YES;
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateEnded && !self.longPressMoved && self.openConfigurationHandler) {
        self.openConfigurationHandler();
    }
    if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ignoreNextTap = NO;
            self.longPressActive = NO;
        });
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint location = [recognizer locationInView:self.view];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, UIEdgeInsetsMake(insets.top + 8.0, insets.left + 8.0, insets.bottom + 8.0, insets.right + 8.0));
    CGFloat minY = CGRectGetMinY(safeBounds) + 28.0;
    CGFloat maxY = CGRectGetMaxY(safeBounds) - 28.0;

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if (self.touchStartTime <= 0.0) {
            self.touchStartTime = NSProcessInfo.processInfo.systemUptime;
            self.touchStartLocation = location;
            self.touchStartButtonCenter = self.floatingButton.center;
        }
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = location.x - self.touchStartLocation.x;
        CGFloat dy = location.y - self.touchStartLocation.y;
        CGFloat distance = hypot(dx, dy);
        BOOL heldLongEnough = NSProcessInfo.processInfo.systemUptime - self.touchStartTime >= 0.55;
        BOOL shouldDrag = self.longPressActive || heldLongEnough;
        if (shouldDrag) {
            self.ignoreNextTap = YES;
            self.longPressMoved = YES;
            self.isDragging = YES;
            [self dismissMenuAnimated:NO];
            CGFloat minX = CGRectGetMinX(safeBounds) + 28.0;
            CGFloat maxX = CGRectGetMaxX(safeBounds) - 28.0;
            self.floatingButton.center = CGPointMake(MIN(MAX(self.touchStartButtonCenter.x + dx, minX), maxX),
                                                     MIN(MAX(self.touchStartButtonCenter.y + dy, minY), maxY));
        } else if (distance >= 18.0 && !self.panOpenedMenu) {
            self.ignoreNextTap = YES;
            self.panOpenedMenu = YES;
            if (!self.menuVisible) {
                [self showMenu];
            }
        }
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        if (self.isDragging) {
            KSBallEdge edge = self.floatingButton.center.x < CGRectGetMidX(self.view.bounds) ? KSBallEdgeLeft : KSBallEdgeRight;
            CGFloat normalizedPosition = maxY > minY ? (self.floatingButton.center.y - minY) / (maxY - minY) : 0.5;
            [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
                settings.edge = edge;
                settings.normalizedVerticalPosition = normalizedPosition;
            }];
            [self positionFloatingButton];
        }
        self.touchStartTime = 0.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isDragging = NO;
            self.ignoreNextTap = NO;
            self.longPressActive = NO;
            self.longPressMoved = NO;
            self.panOpenedMenu = NO;
        });
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)showFeedback:(NSString *)message {
    self.feedbackLabel.text = message;
    self.feedbackLabel.frame = CGRectMake(CGRectGetMidX(self.view.bounds) - 105.0, CGRectGetMaxY(self.view.safeAreaLayoutGuide.layoutFrame) - 56.0, 210.0, 32.0);
    [UIView animateWithDuration:0.15 animations:^{
        self.feedbackLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 delay:1.2 options:0 animations:^{
            self.feedbackLabel.alpha = 0.0;
        } completion:nil];
    }];
}

- (void)refreshHitTargets {
    NSMutableArray<UIView *> *targets = [NSMutableArray arrayWithObject:self.floatingButton];
    if (self.menuVisible) {
        [targets addObjectsFromArray:self.menuButtons];
    }
    ((KSBallHUDCanvasView *)self.view).interactiveViews = targets;
}

@end
