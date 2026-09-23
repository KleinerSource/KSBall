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
@end

@implementation ConfigurationViewController

- (instancetype)initWithSettingsStore:(KSBallSettingsStore *)settingsStore applicationBridge:(SystemApplicationBridge *)applicationBridge hudSceneCoordinator:(HUDSceneCoordinator *)hudSceneCoordinator {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settingsStore = settingsStore;
        _applicationBridge = applicationBridge;
        _hudSceneCoordinator = hudSceneCoordinator;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"KSBall";
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:KSBallSettingsDidChangeNotification object:self.settingsStore];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == KSBallConfigurationSectionHUD) {
        return 2;
    }
    if (section == KSBallConfigurationSectionShortcuts) {
        return self.settingsStore.settings.shortcuts.count + 1;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case KSBallConfigurationSectionHUD: return @"悬浮球";
        case KSBallConfigurationSectionLayout: return @"菜单布局";
        case KSBallConfigurationSectionShortcuts: return [NSString stringWithFormat:@"快捷应用（%lu/%lu）", (unsigned long)self.settingsStore.settings.shortcuts.count, (unsigned long)KSBallMaximumShortcuts];
        case KSBallConfigurationSectionSupport: return @"系统能力";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == KSBallConfigurationSectionHUD) {
        return @"启动一次后，HUD 会在跨应用切换时保持显示。长按不移动可随时回到此设置页；长按后拖动可调整悬浮球位置。";
    }
    if (section == KSBallConfigurationSectionLayout) {
        return @"长按后拖动悬浮球会保存左右边缘和纵向位置；菜单始终向屏幕内侧展开。";
    }
    if (section == KSBallConfigurationSectionShortcuts) {
        return @"前 8 个入口位于内圈，后 8 个入口位于外圈。编辑模式下可删除和排序。";
    }
    return @"KSBall 只应通过 TrollStore 安装。私有能力不可用时，配置仍会保留。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == KSBallConfigurationSectionHUD && indexPath.row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HUDCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"HUDCell"];
        cell.textLabel.text = @"启用全局悬浮球";
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
        cell.textLabel.text = @"重新创建悬浮球";
        cell.detailTextLabel.text = self.hudSceneCoordinator.isHUDActive ? @"已显示" : @"立即重试";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (indexPath.section == KSBallConfigurationSectionLayout) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LayoutCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LayoutCell"];
        cell.textLabel.text = @"展开位置";
        UISegmentedControl *segmentedControl = [cell.accessoryView isKindOfClass:UISegmentedControl.class] ? (UISegmentedControl *)cell.accessoryView : nil;
        if (!segmentedControl) {
            segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"偏上", @"居中", @"偏下"]];
            segmentedControl.tag = 12;
            segmentedControl.frame = CGRectMake(0.0, 0.0, 188.0, 32.0);
            [segmentedControl addTarget:self action:@selector(changeFanBias:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = segmentedControl;
        }
        segmentedControl.selectedSegmentIndex = self.settingsStore.settings.fanBias + 1;
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
        cell.imageView.image = [UIImage systemImageNamed:@"app.fill"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SupportCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SupportCell"];
    cell.textLabel.text = self.applicationBridge.isAvailable ? @"LaunchServices 可用" : @"LaunchServices 不可用";
    cell.detailTextLabel.text = self.applicationBridge.isAvailable ? self.hudSceneCoordinator.frontBoardStatusDescription : self.applicationBridge.unavailabilityReason;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == KSBallConfigurationSectionShortcuts && indexPath.row == self.settingsStore.settings.shortcuts.count) {
        if (self.settingsStore.settings.shortcuts.count >= KSBallMaximumShortcuts) {
            [self showAlertWithTitle:@"已达上限" message:@"扇形菜单最多配置 16 个应用。"];
            return;
        }
        AppPickerViewController *picker = [[AppPickerViewController alloc] initWithApplicationBridge:self.applicationBridge];
        __weak typeof(self) weakSelf = self;
        picker.selectionHandler = ^(KSBallShortcut * _Nonnull shortcut) {
            if (![weakSelf.settingsStore addShortcut:shortcut]) {
                [weakSelf showAlertWithTitle:@"无法添加" message:@"该应用已在快捷列表中，或已达到 16 个入口上限。"];
            }
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

- (void)changeFanBias:(UISegmentedControl *)sender {
    [self.settingsStore mutateSettings:^(KSBallSettings *settings) {
        settings.fanBias = sender.selectedSegmentIndex - 1;
    }];
}

- (void)toggleEditing {
    [self setEditing:!self.editing animated:YES];
    self.navigationItem.rightBarButtonItem.title = self.editing ? @"完成" : @"编辑";
}

- (void)settingsDidChange:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
