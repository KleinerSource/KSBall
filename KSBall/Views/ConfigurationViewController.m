#import "ConfigurationViewController.h"
#import "AppPickerViewController.h"
#import "HUDSceneCoordinator.h"
#import "KSBallFanLayout.h"
#import "KSBallSettingsStore.h"
#import "KSBallUpdateChecker.h"
#import "ShortcutArrangementViewController.h"
#import "SystemApplicationBridge.h"

// 自动检查成功后，这段时间内回到前台不再重复请求 GitHub。
static const NSTimeInterval KSBallAutomaticUpdateCheckInterval = 6.0 * 60.0 * 60.0;
static const NSUInteger KSBallUpdateNotesDisplayLimit = 1000;

typedef NS_ENUM(NSInteger, KSBallConfigurationSection) {
    KSBallConfigurationSectionHUD = 0,
    KSBallConfigurationSectionTrigger = 1,
    KSBallConfigurationSectionAppearance = 2,
    KSBallConfigurationSectionLayout = 3,
    KSBallConfigurationSectionFloatingSplit = 4,
    KSBallConfigurationSectionShortcuts = 5,
    KSBallConfigurationSectionSupport = 6,
    KSBallConfigurationSectionUpdate = 7,
    KSBallConfigurationSectionCount = 8,
};

typedef NS_ENUM(NSInteger, KSBallAppearanceRow) {
    KSBallAppearanceRowHandleStyle = 0,
    KSBallAppearanceRowBackdropStyle = 1,
    KSBallAppearanceRowBackdropBlur = 2,
    KSBallAppearanceRowCount = 3,
};

typedef NS_ENUM(NSInteger, KSBallTriggerRow) {
    KSBallTriggerRowMode = 0,
    KSBallTriggerRowAreaSize = 1,
    KSBallTriggerRowLandscape = 2,
    KSBallTriggerRowTopLeft = 3,
    KSBallTriggerRowTopRight = 4,
    KSBallTriggerRowBottomLeft = 5,
    KSBallTriggerRowBottomRight = 6,
    KSBallTriggerRowCount = 7,
};

typedef NS_ENUM(NSInteger, KSBallLayoutRow) {
    KSBallLayoutRowIconSize = 0,
    KSBallLayoutRowIconSpacing = 1,
    KSBallLayoutRowRingSpacing = 2,
    KSBallLayoutRowCount = 3,
};

typedef NS_ENUM(NSInteger, KSBallFloatingSplitRow) {
    KSBallFloatingSplitRowEnabled = 0,
    KSBallFloatingSplitRowDwellDuration = 1,
    KSBallFloatingSplitRowCount = 2,
};

// 快捷应用分组开头的两个操作行，其后才是各个应用。
typedef NS_ENUM(NSInteger, KSBallShortcutActionRow) {
    KSBallShortcutActionRowAdd = 0,
    KSBallShortcutActionRowArrange = 1,
    KSBallShortcutActionRowCount = 2,
};

typedef NS_ENUM(NSInteger, KSBallUpdateRow) {
    KSBallUpdateRowCheck = 0,
    KSBallUpdateRowAutomatic = 1,
    KSBallUpdateRowBeta = 2,
    KSBallUpdateRowCount = 3,
};

typedef NS_ENUM(NSInteger, KSBallSupportRow) {
    KSBallSupportRowLaunchServices = 0,
    KSBallSupportRowFloatingHost = 1,
    KSBallSupportRowCount = 2,
};

@interface ConfigurationViewController ()
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong) HUDSceneCoordinator *hudSceneCoordinator;
@property (nonatomic, strong) KSBallUpdateChecker *updateChecker;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *listIconsByBundleIdentifier;
@property (nonatomic) BOOL adjustingSlider;
@end

@implementation ConfigurationViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge hudSceneCoordinator:(HUDSceneCoordinator *)hudSceneCoordinator updateChecker:(KSBallUpdateChecker *)updateChecker {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _hudSceneCoordinator = hudSceneCoordinator;
        _updateChecker = updateChecker;
        _listIconsByBundleIdentifier = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"KSBall";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:KSBallSettingsDidChangeNotification object:self.settingsStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateCheckerDidChange:) name:KSBallUpdateCheckerDidChangeNotification object:self.updateChecker];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.settingsStore reload];
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self checkForUpdatesAutomatically];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return KSBallConfigurationSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD: return 1;
        case KSBallConfigurationSectionTrigger:
            return self.settingsStore.settings.menuTriggerMode == KSBallMenuTriggerModeFixedCorners ? KSBallTriggerRowCount : KSBallTriggerRowLandscape + 1;
        case KSBallConfigurationSectionAppearance: return KSBallAppearanceRowCount;
        case KSBallConfigurationSectionLayout: return KSBallLayoutRowCount;
        case KSBallConfigurationSectionFloatingSplit: return KSBallFloatingSplitRowCount;
        case KSBallConfigurationSectionShortcuts: return KSBallShortcutActionRowCount + self.settingsStore.settings.shortcuts.count;
        case KSBallConfigurationSectionUpdate: return KSBallUpdateRowCount;
        case KSBallConfigurationSectionSupport: return KSBallSupportRowCount;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD: return @"悬浮条";
        case KSBallConfigurationSectionTrigger: return @"菜单启动";
        case KSBallConfigurationSectionAppearance: return @"外观";
        case KSBallConfigurationSectionLayout: return @"菜单布局";
        case KSBallConfigurationSectionFloatingSplit: return @"悬浮分屏";
        case KSBallConfigurationSectionShortcuts: return [NSString stringWithFormat:@"快捷应用（%lu/%lu）", (unsigned long)self.settingsStore.settings.shortcuts.count, (unsigned long)KSBallMaximumShortcuts];
        case KSBallConfigurationSectionSupport: return @"系统能力";
        case KSBallConfigurationSectionUpdate: return @"软件更新";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD:
            return @"悬浮条位于屏幕边缘内侧。从悬浮条向内滑动展开扇形菜单，滑到图标上会显示名称并震动；停留后松手可按悬浮分屏等待时间选择悬浮窗打开，在空白处松手则取消。长按不移动回到此设置页，长按后拖动可调整位置。锁屏界面会自动隐藏悬浮条。";
        case KSBallConfigurationSectionTrigger:
            return @"把手模式沿用当前可拖动悬浮条。固定位置模式可同时启用多个屏幕角落；触发区域大小会应用到把手和所有已选角落。关闭横屏触发后，横屏时不会拦截游戏触摸。";
        case KSBallConfigurationSectionAppearance:
            return @"“自动”跟随系统的浅色/深色模式。悬浮条设为隐藏后，边缘的触摸区域仍然有效。模糊程度控制毛玻璃的模糊强度，调整时会实时预览。";
        case KSBallConfigurationSectionLayout:
            return @"扇形菜单围绕悬浮条逐圈展开，每圈按屏幕可显示的范围和间距放下尽可能多的图标。同圈间距控制一圈内相邻图标的距离，圈间距控制两圈之间的距离。空间不足时会等比缩小图标。";
        case KSBallConfigurationSectionFloatingSplit:
            return @"选中扇形菜单中的应用并停留达到等待时间后松手，即以悬浮窗打开；未达到时间松手则全屏打开。关闭总开关会关闭已打开的悬浮窗口并退出宿主，以减少内存占用。";
        case KSBallConfigurationSectionShortcuts:
            return @"在“调整顺序”中以扇形预览长按拖动图标即可排序，靠前的应用位于靠近悬浮条的内圈。左滑应用可删除。\n\n使用扇形菜单时，选中应用并等待设定时间，图标右下角出现窗口标识后松手，即以悬浮窗打开；悬浮窗可拖动标题栏移动、拖右下角缩放，也可收进边栏。最多同时悬浮 3 个应用。";
        case KSBallConfigurationSectionSupport:
            return @"KSBall 只应通过 TrollStore 安装。私有能力不可用时，配置仍会保留。";
        case KSBallConfigurationSectionUpdate:
            return @"开启“检查开发版更新”后会检查 dev 通道；关闭后检查标准版 latest。切换回标准版时允许安装较低版本。更新通过 TrollStore 安装。";
        default: {
            // 页面最底部显示版本号与开发者。
            NSDictionary *info = NSBundle.mainBundle.infoDictionary;
            NSString *version = info[@"CFBundleShortVersionString"] ?: @"-";
            NSString *build = info[@"CFBundleVersion"] ?: @"-";
            return [NSString stringWithFormat:@"开启“自动检查更新”后，打开 KSBall 时会检查最新构建。更新通过 TrollStore 安装，安装后需要再打开一次 KSBall 以恢复悬浮条。\n\nKSBall %@ (%@)\n开发者：KleinerSource", version, build];
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case KSBallConfigurationSectionHUD:
            return [self enabledCell];
        case KSBallConfigurationSectionTrigger:
            return [self triggerCellForRow:indexPath.row];
        case KSBallConfigurationSectionAppearance:
            return [self appearanceCellForRow:indexPath.row];
        case KSBallConfigurationSectionLayout:
            return [self layoutCellForRow:indexPath.row];
        case KSBallConfigurationSectionFloatingSplit:
            return indexPath.row == KSBallFloatingSplitRowEnabled ? [self floatingSplitCell] : [self floatingWindowDwellDurationCell];
        case KSBallConfigurationSectionShortcuts:
            return [self shortcutCellForRow:indexPath.row];
        case KSBallConfigurationSectionUpdate:
            return [self updateCellForRow:indexPath.row];
        default:
            return indexPath.row == KSBallSupportRowFloatingHost ? [self floatingHostCell] : [self supportCell];
    }
}

#pragma mark - 单元格

- (UITableViewCell *)enabledCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"HUDCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"HUDCell"];
    cell.textLabel.text = @"启用全局悬浮条";
    UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
    if (!toggle) {
        toggle = [UISwitch new];
        [toggle addTarget:self action:@selector(toggleHUD:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    toggle.on = self.settingsStore.settings.enabled;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (KSBallFixedTriggerCorner)fixedTriggerCornerForRow:(NSInteger)row {
    switch (row) {
        case KSBallTriggerRowTopLeft: return KSBallFixedTriggerCornerTopLeft;
        case KSBallTriggerRowTopRight: return KSBallFixedTriggerCornerTopRight;
        case KSBallTriggerRowBottomLeft: return KSBallFixedTriggerCornerBottomLeft;
        default: return KSBallFixedTriggerCornerBottomRight;
    }
}

- (UITableViewCell *)triggerCellForRow:(NSInteger)row {
    KSBallSettings *settings = self.settingsStore.settings;
    if (row == KSBallTriggerRowMode) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TriggerModeCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TriggerModeCell"];
        UISegmentedControl *control = [cell.accessoryView isKindOfClass:UISegmentedControl.class] ? (UISegmentedControl *)cell.accessoryView : nil;
        if (!control) {
            control = [[UISegmentedControl alloc] initWithItems:@[@"把手", @"固定位置"]];
            control.frame = CGRectMake(0.0, 0.0, 170.0, 32.0);
            [control addTarget:self action:@selector(triggerModeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = control;
        }
        control.selectedSegmentIndex = settings.menuTriggerMode;
        cell.textLabel.text = @"启动方式";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (row == KSBallTriggerRowAreaSize) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TriggerAreaSizeCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"TriggerAreaSizeCell"];
        UISlider *slider = [cell.accessoryView isKindOfClass:UISlider.class] ? (UISlider *)cell.accessoryView : nil;
        if (!slider) {
            slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 150.0, 32.0)];
            slider.minimumValue = KSBallMinimumHandleTouchRadius;
            slider.maximumValue = KSBallMaximumHandleTouchRadius;
            [slider addTarget:self action:@selector(triggerAreaSizeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
        }
        slider.value = settings.handleTouchRadius;
        cell.textLabel.text = @"触发区域大小";
        cell.detailTextLabel.text = [self touchRadiusText:settings.handleTouchRadius];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (row == KSBallTriggerRowLandscape) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"LandscapeTriggerCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LandscapeTriggerCell"];
        UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
        if (!toggle) {
            toggle = [UISwitch new];
            [toggle addTarget:self action:@selector(toggleLandscapeTrigger:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        toggle.on = settings.landscapeTriggerEnabled;
        cell.textLabel.text = @"横屏允许触发";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSArray<NSString *> *cornerTitles = @[@"左上", @"右上", @"左下", @"右下"];
    NSInteger cornerIndex = row - KSBallTriggerRowTopLeft;
    KSBallFixedTriggerCorner corner = [self fixedTriggerCornerForRow:row];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"FixedTriggerCornerCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"FixedTriggerCornerCell"];
    UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
    if (!toggle) {
        toggle = [UISwitch new];
        [toggle addTarget:self action:@selector(fixedTriggerCornerChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    toggle.tag = row;
    toggle.on = (settings.fixedTriggerCorners & corner) != 0;
    cell.textLabel.text = [NSString stringWithFormat:@"%@触发", cornerTitles[cornerIndex]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)appearanceCellForRow:(NSInteger)row {
    KSBallSettings *settings = self.settingsStore.settings;
    if (row == KSBallAppearanceRowBackdropBlur) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"BlurCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"BlurCell"];
        UISlider *slider = [cell.accessoryView isKindOfClass:UISlider.class] ? (UISlider *)cell.accessoryView : nil;
        if (!slider) {
            slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 150.0, 32.0)];
            slider.minimumValue = KSBallMinimumBackdropBlur;
            slider.maximumValue = 1.0;
            slider.tag = row;
            [slider addTarget:self action:@selector(appearanceSliderChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
        }
        BOOL backdropEnabled = settings.backdropStyle != KSBallBackdropStyleNone;
        slider.value = settings.backdropBlur;
        slider.enabled = backdropEnabled;
        cell.textLabel.text = @"模糊程度";
        cell.textLabel.enabled = backdropEnabled;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", settings.backdropBlur * 100.0];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"StyleCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"StyleCell"];
    UISegmentedControl *segmentedControl = [cell.accessoryView isKindOfClass:UISegmentedControl.class] ? (UISegmentedControl *)cell.accessoryView : nil;
    if (!segmentedControl) {
        segmentedControl = [[UISegmentedControl alloc] initWithFrame:CGRectMake(0.0, 0.0, 216.0, 32.0)];
        [segmentedControl addTarget:self action:@selector(appearanceStyleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = segmentedControl;
    }
    BOOL handleRow = row == KSBallAppearanceRowHandleStyle;
    NSArray<NSString *> *titles = handleRow ? @[@"自动", @"亮色", @"暗色", @"隐藏"] : @[@"自动", @"亮色", @"暗色", @"无"];
    [segmentedControl removeAllSegments];
    [titles enumerateObjectsUsingBlock:^(NSString * _Nonnull title, NSUInteger index, BOOL * _Nonnull stop) {
        [segmentedControl insertSegmentWithTitle:title atIndex:index animated:NO];
    }];
    segmentedControl.tag = row;
    segmentedControl.selectedSegmentIndex = [self segmentIndexForStyle:handleRow ? settings.handleStyle : settings.backdropStyle];
    cell.textLabel.text = handleRow ? @"悬浮条" : @"毛玻璃";
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

// 分段控件把“自动”放在最前，枚举值为兼容旧设置则把它放在末尾，两者在这里互相换算。
- (NSInteger)segmentIndexForStyle:(NSInteger)style {
    return style == KSBallHandleStyleAutomatic ? 0 : style + 1;
}

- (NSInteger)styleForSegmentIndex:(NSInteger)index {
    return index == 0 ? KSBallHandleStyleAutomatic : index - 1;
}

- (NSString *)touchRadiusText:(CGFloat)radius {
    // 把手与固定角落共用同一触发区域尺寸。
    CGFloat width = KSBallHandleEdgeInset + KSBallHandleBarWidth / 2.0 + radius;
    CGFloat height = KSBallHandleBarHeight + radius * 2.0;
    return [NSString stringWithFormat:@"%.0f pt · 区域 %.0f × %.0f pt", radius, width, height];
}

- (UITableViewCell *)layoutCellForRow:(NSInteger)row {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"LayoutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"LayoutCell"];
    UIStepper *stepper = [cell.accessoryView isKindOfClass:UIStepper.class] ? (UIStepper *)cell.accessoryView : nil;
    if (!stepper) {
        stepper = [UIStepper new];
        stepper.stepValue = 2.0;
        [stepper addTarget:self action:@selector(layoutMetricChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stepper;
    }
    KSBallSettings *settings = self.settingsStore.settings;
    stepper.tag = row;
    switch (row) {
        case KSBallLayoutRowIconSize:
            cell.textLabel.text = @"图标大小";
            stepper.minimumValue = KSBallMinimumIconSize;
            stepper.maximumValue = KSBallMaximumIconSize;
            stepper.value = settings.iconSize;
            break;
        case KSBallLayoutRowIconSpacing:
            cell.textLabel.text = @"同圈间距";
            stepper.minimumValue = KSBallMinimumIconSpacing;
            stepper.maximumValue = KSBallMaximumIconSpacing;
            stepper.value = settings.iconSpacing;
            break;
        default:
            cell.textLabel.text = @"圈间距";
            stepper.minimumValue = KSBallMinimumRingSpacing;
            stepper.maximumValue = KSBallMaximumRingSpacing;
            stepper.value = settings.ringSpacing;
            break;
    }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", stepper.value];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)shortcutCellForRow:(NSInteger)row {
    NSArray<KSBallShortcut *> *shortcuts = self.settingsStore.settings.shortcuts;
    if (row < KSBallShortcutActionRowCount) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"ActionCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ActionCell"];
        BOOL addRow = row == KSBallShortcutActionRowAdd;
        // 至少两个应用时才有顺序可调。
        BOOL enabled = addRow || shortcuts.count > 1;
        cell.textLabel.text = addRow ? @"添加应用" : @"调整顺序";
        cell.textLabel.textColor = enabled ? self.view.tintColor : UIColor.tertiaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:addRow ? @"plus.circle.fill" : @"circle.grid.cross.fill"];
        cell.imageView.tintColor = enabled ? self.view.tintColor : UIColor.tertiaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        return cell;
    }
    KSBallShortcut *shortcut = shortcuts[row - KSBallShortcutActionRowCount];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = shortcut.displayName;
    cell.detailTextLabel.text = shortcut.bundleIdentifier;
    cell.imageView.image = [self listIconForBundleIdentifier:shortcut.bundleIdentifier];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)supportCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"SupportCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SupportCell"];
    cell.textLabel.text = self.applicationBridge.isAvailable ? @"LaunchServices 可用" : @"LaunchServices 不可用";
    cell.detailTextLabel.text = self.applicationBridge.isAvailable ? self.hudSceneCoordinator.statusDescription : self.applicationBridge.unavailabilityReason;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)floatingHostCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"FloatingHostCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FloatingHostCell"];
    cell.textLabel.text = @"悬浮分屏";
    cell.detailTextLabel.text = self.hudSceneCoordinator.floatingHostStatusDescription;
    cell.detailTextLabel.numberOfLines = 0;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)floatingSplitCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"FloatingSplitCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"FloatingSplitCell"];
    UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
    if (!toggle) {
        toggle = [UISwitch new];
        [toggle addTarget:self action:@selector(toggleFloatingSplit:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    toggle.on = self.settingsStore.settings.floatingSplitEnabled;
    cell.textLabel.text = @"启用悬浮分屏";
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)floatingWindowDwellDurationCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"FloatingWindowDwellDurationCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FloatingWindowDwellDurationCell"];
    UIStepper *stepper = [cell.accessoryView isKindOfClass:UIStepper.class] ? (UIStepper *)cell.accessoryView : nil;
    if (!stepper) {
        stepper = [UIStepper new];
        stepper.minimumValue = KSBallMinimumFloatingWindowDwellDuration;
        stepper.maximumValue = KSBallMaximumFloatingWindowDwellDuration;
        stepper.stepValue = 1.0;
        stepper.accessibilityLabel = @"悬浮窗等待时间";
        [stepper addTarget:self action:@selector(floatingWindowDwellDurationChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stepper;
    }
    CGFloat duration = self.settingsStore.settings.floatingWindowDwellDuration;
    stepper.value = duration;
    cell.textLabel.text = @"悬浮窗等待时间";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f 秒", duration];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)updateCellForRow:(NSInteger)row {
    if (row == KSBallUpdateRowCheck) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"CheckUpdateCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"CheckUpdateCell"];
        cell.textLabel.text = @"检查更新";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [self configureCheckUpdateCell:cell];
        return cell;
    }

    if (row == KSBallUpdateRowBeta) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"BetaUpdateCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BetaUpdateCell"];
        cell.textLabel.text = @"检查开发版更新";
        UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
        if (!toggle) {
            toggle = [UISwitch new];
            [toggle addTarget:self action:@selector(toggleBetaUpdateCheck:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        toggle.on = self.updateChecker.betaUpdatesEnabled;
        toggle.enabled = !self.updateChecker.isChecking;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (row == KSBallUpdateRowAutomatic) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"AutomaticUpdateCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AutomaticUpdateCell"];
        cell.textLabel.text = @"自动检查更新";
        UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
        if (!toggle) {
            toggle = [UISwitch new];
            [toggle addTarget:self action:@selector(toggleAutomaticUpdateCheck:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        toggle.on = self.updateChecker.automaticCheckEnabled;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    return [UITableViewCell new];
}

- (void)configureCheckUpdateCell:(UITableViewCell *)cell {
    KSBallUpdateChecker *checker = self.updateChecker;
    KSBallRelease *release = checker.latestRelease;
    BOOL hasUpdate = !checker.isChecking && release && [checker isUpdateRelease:release];
    if (checker.isChecking) {
        cell.detailTextLabel.text = @"正在检查…";
    } else if (checker.lastError) {
        cell.detailTextLabel.text = @"检查失败";
    } else if (release) {
        NSString *channelName = checker.betaUpdatesEnabled ? @"开发版" : @"标准版";
        cell.detailTextLabel.text = hasUpdate ? [NSString stringWithFormat:@"发现%@ %@", channelName, release.version.displayString] : @"已是最新版本";
    } else {
        cell.detailTextLabel.text = nil;
    }
    cell.detailTextLabel.textColor = hasUpdate ? self.view.tintColor : UIColor.secondaryLabelColor;
    [cell setNeedsLayout];
}

#pragma mark - 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row == KSBallShortcutActionRowAdd) {
        [self showApplicationPicker];
    } else if (indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row == KSBallShortcutActionRowArrange) {
        if (self.settingsStore.settings.shortcuts.count > 1) {
            ShortcutArrangementViewController *arrangement = [[ShortcutArrangementViewController alloc] initWithSettingsStore:self.settingsStore applicationBridge:self.applicationBridge];
            [self presentViewController:arrangement animated:YES completion:nil];
        }
    } else if (indexPath.section == KSBallConfigurationSectionUpdate && indexPath.row == KSBallUpdateRowCheck) {
        [self checkForUpdatesManually];
    }
}

- (void)showApplicationPicker {
    NSArray<KSBallShortcut *> *existingShortcuts = self.settingsStore.settings.shortcuts;
    if (existingShortcuts.count >= KSBallMaximumShortcuts) {
        [self showAlertWithTitle:@"已达上限" message:[NSString stringWithFormat:@"扇形菜单最多配置 %lu 个应用。", (unsigned long)KSBallMaximumShortcuts]];
        return;
    }
    AppPickerViewController *picker = [[AppPickerViewController alloc] initWithApplicationBridge:self.applicationBridge existingBundleIdentifiers:[existingShortcuts valueForKey:@"bundleIdentifier"] remainingCapacity:KSBallMaximumShortcuts - existingShortcuts.count];
    __weak typeof(self) weakSelf = self;
    picker.selectionHandler = ^BOOL(KSBallShortcut * _Nonnull shortcut) {
        return [weakSelf.settingsStore addShortcut:shortcut];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

// 左滑删除；排序改在扇形编辑器里完成。
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isShortcutRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && [self isShortcutRowAtIndexPath:indexPath]) {
        [self.settingsStore removeShortcutAtIndex:indexPath.row - KSBallShortcutActionRowCount];
    }
}

- (BOOL)isShortcutRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row >= KSBallShortcutActionRowCount &&
        indexPath.row < KSBallShortcutActionRowCount + (NSInteger)self.settingsStore.settings.shortcuts.count;
}

- (void)toggleHUD:(UISwitch *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.enabled = sender.isOn;
    }];
}

- (void)toggleFloatingSplit:(UISwitch *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.floatingSplitEnabled = sender.isOn;
    }];
}

- (void)floatingWindowDwellDurationChanged:(UIStepper *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.floatingWindowDwellDuration = sender.value;
    }];
}

- (void)triggerModeChanged:(UISegmentedControl *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.menuTriggerMode = sender.selectedSegmentIndex == 1 ? KSBallMenuTriggerModeFixedCorners : KSBallMenuTriggerModeHandle;
    }];
}

- (void)fixedTriggerCornerChanged:(UISwitch *)sender {
    KSBallFixedTriggerCorner corner = [self fixedTriggerCornerForRow:sender.tag];
    KSBallSettings *settings = self.settingsStore.settings;
    KSBallFixedTriggerCorner corners = settings.fixedTriggerCorners;
    corners = sender.isOn ? (corners | corner) : (corners & ~corner);
    if (corners == 0) {
        sender.on = YES;
        return;
    }
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.fixedTriggerCorners = corners;
    }];
}

- (void)toggleLandscapeTrigger:(UISwitch *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.landscapeTriggerEnabled = sender.isOn;
    }];
}

- (void)appearanceStyleChanged:(UISegmentedControl *)sender {
    NSInteger style = [self styleForSegmentIndex:sender.selectedSegmentIndex];
    BOOL handleRow = sender.tag == KSBallAppearanceRowHandleStyle;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        if (handleRow) {
            settings.handleStyle = style;
        } else {
            settings.backdropStyle = style;
        }
    }];
}

// 拖动过程中实时写入设置，悬浮条会同步显示触摸范围或毛玻璃效果；
// 只在数值跨过一个刻度时写入，避免每一帧都同步一次。
- (void)appearanceSliderChanged:(UISlider *)sender {
    CGFloat value = round(sender.value * 20.0) / 20.0;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:KSBallConfigurationSectionAppearance];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];

    KSBallSettings *settings = self.settingsStore.settings;
    CGFloat current = settings.backdropBlur;
    if (fabs(current - value) < 0.001) {
        return;
    }
    self.adjustingSlider = sender.isTracking;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.backdropBlur = value;
    }];
    self.adjustingSlider = NO;
}

- (void)triggerAreaSizeChanged:(UISlider *)sender {
    CGFloat value = round(sender.value);
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:KSBallTriggerRowAreaSize inSection:KSBallConfigurationSectionTrigger];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.detailTextLabel.text = [self touchRadiusText:value];

    if (fabs(self.settingsStore.settings.handleTouchRadius - value) < 0.001) {
        return;
    }
    self.adjustingSlider = sender.isTracking;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.handleTouchRadius = value;
    }];
    self.adjustingSlider = NO;
}

- (void)layoutMetricChanged:(UIStepper *)sender {
    CGFloat value = sender.value;
    NSInteger row = sender.tag;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        switch (row) {
            case KSBallLayoutRowIconSize: settings.iconSize = value; break;
            case KSBallLayoutRowIconSpacing: settings.iconSpacing = value; break;
            default: settings.ringSpacing = value; break;
        }
    }];
}

#pragma mark - 软件更新

- (void)toggleAutomaticUpdateCheck:(UISwitch *)sender {
    self.updateChecker.automaticCheckEnabled = sender.isOn;
    [self checkForUpdatesAutomatically];
}

- (void)toggleBetaUpdateCheck:(UISwitch *)sender {
    self.updateChecker.betaUpdatesEnabled = sender.isOn;
    [self checkForUpdatesManually];
}

// 打开配置页或回到前台时静默检查。成功后一段时间内不再请求；失败（如首次联网等待授权）则在下次回到前台时重试。
- (void)checkForUpdatesAutomatically {
    KSBallUpdateChecker *checker = self.updateChecker;
    NSDate *lastCheckDate = checker.lastCheckDate;
    if (!checker.automaticCheckEnabled || checker.isChecking || (lastCheckDate && -lastCheckDate.timeIntervalSinceNow < KSBallAutomaticUpdateCheckInterval)) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [checker checkForUpdatesWithCompletion:^(KSBallRelease *release, NSError *error) {
        // 只提示未被忽略的新版本；正在显示其它页面或弹窗时不打扰，检查结果仍会显示在“检查更新”一行。
        UIViewController *presenter = weakSelf.navigationController ?: weakSelf;
        if (!release || ![weakSelf.updateChecker isUpdateRelease:release] || [weakSelf.updateChecker isReleaseIgnored:release] || presenter.presentedViewController) {
            return;
        }
        [weakSelf presentUpdateAlertForRelease:release];
    }];
}

// 手动检查会重新提示已忽略的版本，失败时说明原因。
- (void)checkForUpdatesManually {
    if (self.updateChecker.isChecking) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.updateChecker checkForUpdatesWithCompletion:^(KSBallRelease *release, NSError *error) {
        if (error) {
            [weakSelf showAlertWithTitle:@"检查更新失败" message:error.localizedDescription];
        } else if ([weakSelf.updateChecker isUpdateRelease:release]) {
            [weakSelf presentUpdateAlertForRelease:release];
        }
    }];
}

- (void)presentUpdateAlertForRelease:(KSBallRelease *)release {
    NSString *notes = release.notes.length > 0 ? release.notes : @"暂无更新说明。";
    if (notes.length > KSBallUpdateNotesDisplayLimit) {
        NSRange range = [notes rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, KSBallUpdateNotesDisplayLimit)];
        notes = [[notes substringWithRange:range] stringByAppendingString:@"…"];
    }
    NSString *message = [NSString stringWithFormat:@"新版本：%@\n当前版本：%@\n\n%@", release.version.displayString, self.updateChecker.currentVersion.displayString, notes];
    BOOL betaRelease = [release.tagName isEqualToString:@"dev"];
    NSComparisonResult versionOrder = [release.version compare:self.updateChecker.currentVersion];
    BOOL downgrade = !betaRelease && versionOrder == NSOrderedAscending;
    BOOL channelSwitch = !betaRelease && versionOrder == NSOrderedSame;
    NSString *title = downgrade || channelSwitch ? @"切换到标准版" : (betaRelease ? @"发现开发版更新" : @"发现标准版更新");
    NSString *installTitle = downgrade ? @"降级到标准版" : (channelSwitch ? @"安装标准版" : @"立即更新");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    UIAlertAction *installAction = [UIAlertAction actionWithTitle:installTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf installRelease:release];
    }];
    [alert addAction:installAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"忽略此版本" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf.updateChecker ignoreRelease:release];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
    alert.preferredAction = installAction;
    [self presentAlertFromTopController:alert];
}

// 交给 TrollStore 下载并安装；TrollStore 不响应 URL scheme 时改为打开发布页手动下载。
- (void)installRelease:(KSBallRelease *)release {
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication openURL:[KSBallUpdateChecker installURLForRelease:release] options:@{} completionHandler:^(BOOL success) {
        if (success) {
            return;
        }
        [UIApplication.sharedApplication openURL:release.pageURL ?: release.downloadURL options:@{} completionHandler:^(BOOL opened) {
            if (!opened) {
                [weakSelf showAlertWithTitle:@"无法打开 TrollStore" message:@"请在 TrollStore 中手动安装新版本。"];
            }
        }];
    }];
}

- (void)updateCheckerDidChange:(NSNotification *)notification {
    // 只刷新可见的那一行，避免重载表格打断正在进行的滑动或拖动。
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:KSBallUpdateRowCheck inSection:KSBallConfigurationSectionUpdate];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) {
        [self configureCheckUpdateCell:cell];
    }
    NSIndexPath *betaIndexPath = [NSIndexPath indexPathForRow:KSBallUpdateRowBeta inSection:KSBallConfigurationSectionUpdate];
    UITableViewCell *betaCell = [self.tableView cellForRowAtIndexPath:betaIndexPath];
    UISwitch *toggle = [betaCell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)betaCell.accessoryView : nil;
    toggle.enabled = !self.updateChecker.isChecking;
}

#pragma mark - 辅助

- (UIImage *)listIconForBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *key = bundleIdentifier.lowercaseString;
    UIImage *cachedIcon = self.listIconsByBundleIdentifier[key];
    if (cachedIcon) {
        return cachedIcon;
    }
    UIImage *icon = [self.applicationBridge iconForBundleIdentifier:bundleIdentifier];
    UIImage *listIcon = KSBallListIconImage(icon);
    if (icon) {
        self.listIconsByBundleIdentifier[key] = listIcon;
    }
    return listIcon;
}

- (void)settingsDidChange:(NSNotification *)notification {
    // 拖动滑块时重载表格会打断手势，数值标签已在拖动回调里更新。
    if (self.adjustingSlider) {
        return;
    }
    [self.tableView reloadData];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self.settingsStore reload];
    [self.tableView reloadData];
    [self checkForUpdatesAutomatically];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentAlertFromTopController:alert];
}

// 检查更新的结果异步返回，此时配置页可能已被其它页面或弹窗覆盖，从最上层的控制器弹出。
- (void)presentAlertFromTopController:(UIAlertController *)alert {
    UIViewController *presenter = self.navigationController ?: self;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
