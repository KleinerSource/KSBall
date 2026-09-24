#import "ConfigurationViewController.h"
#import "AppPickerViewController.h"
#import "HUDSceneCoordinator.h"
#import "KSBallSettingsStore.h"
#import "SystemApplicationBridge.h"

typedef NS_ENUM(NSInteger, KSBallConfigurationSection) {
    KSBallConfigurationSectionHUD = 0,
    KSBallConfigurationSectionLayout = 1,
    KSBallConfigurationSectionShortcuts = 2,
    KSBallConfigurationSectionSupport = 3,
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
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == KSBallConfigurationSectionHUD) {
        return 2;
    }
    if (section == KSBallConfigurationSectionLayout) {
        return 2;
    }
    if (section == KSBallConfigurationSectionShortcuts) {
        return self.settingsStore.settings.shortcuts.count + 1;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD: return @"悬浮条";
        case KSBallConfigurationSectionLayout: return @"菜单布局";
        case KSBallConfigurationSectionShortcuts: return [NSString stringWithFormat:@"快捷应用（%lu/%lu）", (unsigned long)self.settingsStore.settings.shortcuts.count, (unsigned long)KSBallMaximumShortcuts];
        case KSBallConfigurationSectionSupport: return @"系统能力";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == KSBallConfigurationSectionHUD) {
        return @"悬浮条位于屏幕边缘内侧。从悬浮条向内滑动展开扇形菜单，滑到图标上会显示名称并震动，松手即启动；在空白处松手则取消。长按不移动回到此设置页，长按后拖动可调整位置。锁屏界面会自动隐藏悬浮条。";
    }
    if (section == KSBallConfigurationSectionLayout) {
        return @"扇形菜单围绕悬浮条展开：屏幕中部为半圆，靠近顶部或底部时自动收成四分之一圆。调整图标大小、间距或快捷应用时，悬浮条旁会实时预览扇形菜单。屏幕空间不足时会等比缩小图标。";
    }
    if (section == KSBallConfigurationSectionShortcuts) {
        return @"排在前面的入口位于靠近悬浮条的内圈。编辑模式下可删除和排序。";
    }
    return @"KSBall 只应通过 TrollStore 安装。私有能力不可用时，配置仍会保留。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == KSBallConfigurationSectionHUD && indexPath.row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HUDCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"HUDCell"];
        cell.textLabel.text = @"启用全局悬浮条";
        UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
        if (!toggle) {
            toggle = [UISwitch new];
            toggle.tag = 11;
            [toggle addTarget:self action:@selector(toggleHUD:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        toggle.on = self.settingsStore.settings.enabled;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == KSBallConfigurationSectionHUD) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RebuildHUDCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"RebuildHUDCell"];
        cell.textLabel.text = @"重新创建悬浮条";
        cell.detailTextLabel.text = self.hudSceneCoordinator.isHUDActive ? @"已显示" : @"立即重试";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == KSBallConfigurationSectionLayout) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LayoutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"LayoutCell"];
        UIStepper *stepper = [cell.accessoryView isKindOfClass:UIStepper.class] ? (UIStepper *)cell.accessoryView : nil;
        if (!stepper) {
            stepper = [UIStepper new];
            [stepper addTarget:self action:@selector(changeLayoutMetric:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        }
        KSBallSettings *settings = self.settingsStore.settings;
        BOOL sizeRow = indexPath.row == 0;
        stepper.tag = sizeRow ? 12 : 13;
        stepper.minimumValue = sizeRow ? KSBallMinimumIconSize : KSBallMinimumIconSpacing;
        stepper.maximumValue = sizeRow ? KSBallMaximumIconSize : KSBallMaximumIconSpacing;
        stepper.stepValue = 2.0;
        stepper.value = sizeRow ? settings.iconSize : settings.iconSpacing;
        cell.textLabel.text = sizeRow ? @"图标大小" : @"图标间距";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", stepper.value];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == KSBallConfigurationSectionShortcuts) {
        if (indexPath.row == self.settingsStore.settings.shortcuts.count) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AddCell"];
            cell.textLabel.text = @"添加应用";
            cell.textLabel.textColor = self.view.tintColor;
            cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        KSBallShortcut *shortcut = self.settingsStore.settings.shortcuts[indexPath.row];
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ShortcutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ShortcutCell"];
        cell.textLabel.text = shortcut.displayName;
        cell.detailTextLabel.text = shortcut.bundleIdentifier;
        cell.imageView.image = [self listIconForBundleIdentifier:shortcut.bundleIdentifier];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SupportCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SupportCell"];
    cell.textLabel.text = self.applicationBridge.isAvailable ? @"LaunchServices 可用" : @"LaunchServices 不可用";
    cell.detailTextLabel.text = self.applicationBridge.isAvailable ? self.hudSceneCoordinator.statusDescription : self.applicationBridge.unavailabilityReason;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row == self.settingsStore.settings.shortcuts.count) {
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
    } else if (indexPath.section == KSBallConfigurationSectionHUD && indexPath.row == 1) {
        [self.hudSceneCoordinator rebuildHUD];
        [self.tableView reloadData];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row < self.settingsStore.settings.shortcuts.count;
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
    return indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row < self.settingsStore.settings.shortcuts.count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.settingsStore removeShortcutAtIndex:indexPath.row];
    }
}

- (void)toggleHUD:(UISwitch *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.enabled = sender.isOn;
    }];
}

- (void)changeLayoutMetric:(UIStepper *)sender {
    CGFloat value = sender.value;
    BOOL sizeMetric = sender.tag == 12;
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        if (sizeMetric) {
            settings.iconSize = value;
        } else {
            settings.iconSpacing = value;
        }
    }];
}

- (UIImage *)listIconForBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *key = bundleIdentifier.lowercaseString;
    UIImage *cachedIcon = self.listIconsByBundleIdentifier[key];
    if (cachedIcon) {
        return cachedIcon;
    }
    UIImage *icon = [self.applicationBridge iconForBundleIdentifier:bundleIdentifier];
    if (!icon) {
        return KSBallListIconImage(nil);
    }
    UIImage *listIcon = KSBallListIconImage(icon);
    self.listIconsByBundleIdentifier[key] = listIcon;
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
