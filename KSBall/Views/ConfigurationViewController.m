#import "ConfigurationViewController.h"
#import "AppPickerViewController.h"
#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"

typedef NS_ENUM(NSInteger, KSBallConfigurationSection) {
    KSBallConfigurationSectionHUD = 0,
    KSBallConfigurationSectionAppearance = 1,
    KSBallConfigurationSectionLayout = 2,
    KSBallConfigurationSectionShortcuts = 3,
    KSBallConfigurationSectionSupport = 4,
    KSBallConfigurationSectionCount = 5,
};

typedef NS_ENUM(NSInteger, KSBallAppearanceRow) {
    KSBallAppearanceRowHandleStyle = 0,
    KSBallAppearanceRowBackdropStyle = 1,
    KSBallAppearanceRowBackdropOpacity = 2,
    KSBallAppearanceRowCount = 3,
};

typedef NS_ENUM(NSInteger, KSBallLayoutRow) {
    KSBallLayoutRowIconSize = 0,
    KSBallLayoutRowIconSpacing = 1,
    KSBallLayoutRowRingSpacing = 2,
    KSBallLayoutRowCount = 3,
};

@interface ConfigurationViewController ()
@property (nonatomic, strong) KSBallSettingsStore *settingsStore;
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, strong) HUDSceneCoordinator *hudSceneCoordinator;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *listIconsByBundleIdentifier;
@end

@implementation ConfigurationViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge hudSceneCoordinator:(HUDSceneCoordinator *)hudSceneCoordinator {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _hudSceneCoordinator = hudSceneCoordinator;
        _listIconsByBundleIdentifier = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"KSBall";
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:KSBallSettingsDidChangeNotification object:self.settingsStore];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.settingsStore reload];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return KSBallConfigurationSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD: return 2;
        case KSBallConfigurationSectionAppearance: return KSBallAppearanceRowCount;
        case KSBallConfigurationSectionLayout: return KSBallLayoutRowCount;
        case KSBallConfigurationSectionShortcuts: return self.settingsStore.settings.shortcuts.count + 1;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD: return @"悬浮条";
        case KSBallConfigurationSectionAppearance: return @"外观";
        case KSBallConfigurationSectionLayout: return @"菜单布局";
        case KSBallConfigurationSectionShortcuts: return [NSString stringWithFormat:@"快捷应用（%lu/%lu）", (unsigned long)self.settingsStore.settings.shortcuts.count, (unsigned long)KSBallMaximumShortcuts];
        case KSBallConfigurationSectionSupport: return @"系统能力";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD:
            return @"悬浮条位于屏幕边缘内侧。从悬浮条向内滑动展开扇形菜单，滑到图标上会显示名称并震动，松手即启动；在空白处松手则取消。长按不移动回到此设置页，长按后拖动可调整位置。锁屏界面会自动隐藏悬浮条。";
        case KSBallConfigurationSectionAppearance:
            return @"悬浮条设为隐藏后，边缘的触摸区域仍然有效。毛玻璃覆盖整个屏幕，浓度越低越能看清背后的内容。调整时会实时预览。";
        case KSBallConfigurationSectionLayout:
            return @"扇形菜单围绕悬浮条逐圈展开，每圈按屏幕可显示的范围和间距放下尽可能多的图标。同圈间距控制一圈内相邻图标的距离，圈间距控制两圈之间的距离。空间不足时会等比缩小图标。";
        case KSBallConfigurationSectionShortcuts:
            return @"排在前面的入口位于靠近悬浮条的内圈。编辑模式下可删除和排序。";
        default:
            return @"KSBall 只应通过 TrollStore 安装。私有能力不可用时，配置仍会保留。";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case KSBallConfigurationSectionHUD:
            return indexPath.row == 0 ? [self enabledCell] : [self rebuildCell];
        case KSBallConfigurationSectionAppearance:
            return [self appearanceCellForRow:indexPath.row];
        case KSBallConfigurationSectionLayout:
            return [self layoutCellForRow:indexPath.row];
        case KSBallConfigurationSectionShortcuts:
            return [self shortcutCellForRow:indexPath.row];
        default:
            return [self supportCell];
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

- (UITableViewCell *)rebuildCell {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"RebuildHUDCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"RebuildHUDCell"];
    cell.textLabel.text = @"重新创建悬浮条";
    cell.detailTextLabel.text = self.hudSceneCoordinator.isHUDActive ? @"已显示" : @"立即重试";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)appearanceCellForRow:(NSInteger)row {
    KSBallSettings *settings = self.settingsStore.settings;
    if (row == KSBallAppearanceRowBackdropOpacity) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"OpacityCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"OpacityCell"];
        UISlider *slider = [cell.accessoryView isKindOfClass:UISlider.class] ? (UISlider *)cell.accessoryView : nil;
        if (!slider) {
            slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 150.0, 32.0)];
            slider.minimumValue = KSBallMinimumBackdropOpacity;
            slider.maximumValue = 1.0;
            // 拖动时只刷新数值，松手后再写入设置，避免频繁同步到悬浮条。
            [slider addTarget:self action:@selector(backdropOpacitySliderMoved:) forControlEvents:UIControlEventValueChanged];
            [slider addTarget:self action:@selector(backdropOpacitySliderReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            cell.accessoryView = slider;
        }
        BOOL backdropEnabled = settings.backdropStyle != KSBallBackdropStyleNone;
        slider.value = settings.backdropOpacity;
        slider.enabled = backdropEnabled;
        cell.textLabel.text = @"毛玻璃浓度";
        cell.textLabel.enabled = backdropEnabled;
        cell.detailTextLabel.text = [self percentageText:settings.backdropOpacity];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"StyleCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"StyleCell"];
    UISegmentedControl *segmentedControl = [cell.accessoryView isKindOfClass:UISegmentedControl.class] ? (UISegmentedControl *)cell.accessoryView : nil;
    if (!segmentedControl) {
        segmentedControl = [[UISegmentedControl alloc] initWithFrame:CGRectMake(0.0, 0.0, 180.0, 32.0)];
        [segmentedControl addTarget:self action:@selector(appearanceStyleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = segmentedControl;
    }
    BOOL handleRow = row == KSBallAppearanceRowHandleStyle;
    NSArray<NSString *> *titles = handleRow ? @[@"亮色", @"暗色", @"隐藏"] : @[@"亮色", @"暗色", @"无"];
    [segmentedControl removeAllSegments];
    [titles enumerateObjectsUsingBlock:^(NSString * _Nonnull title, NSUInteger index, BOOL * _Nonnull stop) {
        [segmentedControl insertSegmentWithTitle:title atIndex:index animated:NO];
    }];
    segmentedControl.tag = row;
    segmentedControl.selectedSegmentIndex = handleRow ? settings.handleStyle : settings.backdropStyle;
    cell.textLabel.text = handleRow ? @"悬浮条" : @"毛玻璃";
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
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
    if (row == (NSInteger)shortcuts.count) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"AddCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AddCell"];
        cell.textLabel.text = @"添加应用";
        cell.textLabel.textColor = self.view.tintColor;
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    KSBallShortcut *shortcut = shortcuts[row];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];
    cell.textLabel.text = shortcut.displayName;
    cell.detailTextLabel.text = shortcut.bundleIdentifier;
    cell.imageView.image = [self listIconForBundleIdentifier:shortcut.bundleIdentifier];
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

#pragma mark - 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row == (NSInteger)self.settingsStore.settings.shortcuts.count) {
        [self showApplicationPicker];
    } else if (indexPath.section == KSBallConfigurationSectionHUD && indexPath.row == 1) {
        [self.hudSceneCoordinator rebuildHUD];
        [self.tableView reloadData];
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

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isShortcutRowAtIndexPath:indexPath];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    NSUInteger shortcutCount = self.settingsStore.settings.shortcuts.count;
    if (proposedDestinationIndexPath.section != KSBallConfigurationSectionShortcuts || shortcutCount == 0) {
        return sourceIndexPath;
    }
    return [NSIndexPath indexPathForRow:MIN((NSUInteger)proposedDestinationIndexPath.row, shortcutCount - 1) inSection:KSBallConfigurationSectionShortcuts];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    [self.settingsStore moveShortcutFromIndex:sourceIndexPath.row toIndex:destinationIndexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isShortcutRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.settingsStore removeShortcutAtIndex:indexPath.row];
    }
}

- (BOOL)isShortcutRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row < (NSInteger)self.settingsStore.settings.shortcuts.count;
}

- (void)toggleHUD:(UISwitch *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.enabled = sender.isOn;
    }];
}

- (void)appearanceStyleChanged:(UISegmentedControl *)sender {
    NSInteger selectedIndex = sender.selectedSegmentIndex;
    BOOL handleRow = sender.tag == KSBallAppearanceRowHandleStyle;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        if (handleRow) {
            settings.handleStyle = selectedIndex;
        } else {
            settings.backdropStyle = selectedIndex;
        }
    }];
}

- (void)backdropOpacitySliderMoved:(UISlider *)sender {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:KSBallAppearanceRowBackdropOpacity inSection:KSBallConfigurationSectionAppearance]];
    cell.detailTextLabel.text = [self percentageText:sender.value];
}

- (void)backdropOpacitySliderReleased:(UISlider *)sender {
    CGFloat value = sender.value;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.backdropOpacity = value;
    }];
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

#pragma mark - 辅助

- (NSString *)percentageText:(CGFloat)value {
    return [NSString stringWithFormat:@"%.0f%%", value * 100.0];
}

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

- (void)toggleEditing {
    [self setEditing:!self.editing animated:YES];
    self.navigationItem.rightBarButtonItem.title = self.editing ? @"完成" : @"编辑";
}

- (void)settingsDidChange:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self.settingsStore reload];
    [self.tableView reloadData];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
