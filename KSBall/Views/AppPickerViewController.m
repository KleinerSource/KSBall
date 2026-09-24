#import "AppPickerViewController.h"
#import "KSBallSettings.h"
#import "SystemApplicationBridge.h"

@interface AppPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, copy) NSArray<KSBallApplication *> *applications;
@property (nonatomic, copy) NSArray<KSBallApplication *> *filteredApplications;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSMutableSet<NSString *> *existingBundleIdentifiers;
@property (nonatomic) NSUInteger remainingCapacity;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *listIconsByBundleIdentifier;
@end

@implementation AppPickerViewController

- (instancetype)initWithApplicationBridge:(SystemApplicationBridge *)applicationBridge existingBundleIdentifiers:(NSArray<NSString *> *)existingBundleIdentifiers remainingCapacity:(NSUInteger)remainingCapacity {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _applicationBridge = applicationBridge;
        _existingBundleIdentifiers = [NSMutableSet setWithArray:[existingBundleIdentifiers valueForKey:@"lowercaseString"]];
        _remainingCapacity = remainingCapacity;
        _listIconsByBundleIdentifier = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"添加应用";
    // 编辑模式下每行前面显示系统的绿色 + 号，点一下即添加一个应用。
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索应用名称";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"手动添加" style:UIBarButtonItemStylePlain target:self action:@selector(showManualEntry)];
    [self reloadApplications];
}

- (void)reloadApplications {
    // 已在快捷列表中的应用直接隐藏。
    NSSet<NSString *> *existingBundleIdentifiers = [self.existingBundleIdentifiers copy];
    self.applications = [self.applicationBridge.availableApplications filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(KSBallApplication *application, NSDictionary<NSString *,id> *bindings) {
        return ![existingBundleIdentifiers containsObject:application.bundleIdentifier.lowercaseString];
    }]];
    [self applySearchQuery:self.searchController.searchBar.text];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearchQuery:searchController.searchBar.text];
    [self.tableView reloadData];
}

- (void)applySearchQuery:(nullable NSString *)text {
    NSString *query = text.lowercaseString;
    if (query.length == 0) {
        self.filteredApplications = self.applications;
        return;
    }
    self.filteredApplications = [self.applications filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(KSBallApplication *application, NSDictionary<NSString *,id> *bindings) {
        return [application.displayName.lowercaseString containsString:query] || [application.bundleIdentifier.lowercaseString containsString:query];
    }]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.applicationBridge.isAvailable ? 1 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApplications.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"已安装的用户应用（还可添加 %lu 个）", (unsigned long)self.remainingCapacity];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"点应用前的 + 号即可加入快捷列表，可连续添加多个。已添加的应用不会出现在这里；默认隐藏系统内部应用，未列出的应用可通过“手动添加”输入 Bundle ID。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApplicationCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ApplicationCell"];
    }
    KSBallApplication *application = self.filteredApplications[indexPath.row];
    cell.textLabel.text = application.displayName;
    cell.detailTextLabel.text = application.bundleIdentifier;
    cell.imageView.image = [self listIconForApplication:application];
    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleInsert;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleInsert) {
        [self addApplicationAtIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self addApplicationAtIndexPath:indexPath];
}

- (void)addApplicationAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.filteredApplications.count) {
        return;
    }
    KSBallApplication *application = self.filteredApplications[indexPath.row];
    KSBallShortcut *shortcut = [[KSBallShortcut alloc] initWithBundleIdentifier:application.bundleIdentifier displayName:application.displayName];
    if (![self addShortcut:shortcut]) {
        return;
    }
    NSMutableArray<KSBallApplication *> *applications = [self.applications mutableCopy];
    [applications removeObjectIdenticalTo:application];
    self.applications = applications;
    NSMutableArray<KSBallApplication *> *filteredApplications = [self.filteredApplications mutableCopy];
    [filteredApplications removeObjectAtIndex:indexPath.row];
    self.filteredApplications = filteredApplications;
    [self.tableView performBatchUpdates:^{
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } completion:^(BOOL finished) {
        // 刷新分组标题中的剩余数量。
        [UIView performWithoutAnimation:^{
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        }];
    }];
}

// 逐个添加：达到上限时立即提示，不会出现选了一批却只加进去一部分的情况。
- (BOOL)addShortcut:(KSBallShortcut *)shortcut {
    if (self.remainingCapacity == 0) {
        [self showAlertWithTitle:@"已达上限" message:[NSString stringWithFormat:@"扇形菜单最多配置 %lu 个应用。", (unsigned long)KSBallMaximumShortcuts]];
        return NO;
    }
    if (!self.selectionHandler || !self.selectionHandler(shortcut)) {
        [self showAlertWithTitle:@"无法添加" message:@"该应用已在快捷列表中，或已达到入口上限。"];
        return NO;
    }
    self.remainingCapacity -= 1;
    [self.existingBundleIdentifiers addObject:shortcut.bundleIdentifier.lowercaseString];
    return YES;
}

- (UIImage *)listIconForApplication:(KSBallApplication *)application {
    NSString *key = application.bundleIdentifier.lowercaseString;
    UIImage *cachedIcon = self.listIconsByBundleIdentifier[key];
    if (cachedIcon) {
        return cachedIcon;
    }
    UIImage *listIcon = KSBallListIconImage(application.icon);
    if (application.icon) {
        self.listIconsByBundleIdentifier[key] = listIcon;
    }
    return listIcon;
}

- (void)showManualEntry {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"手动添加应用" message:@"请输入应用的 Bundle ID。显示名称可留空。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"com.example.app";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"显示名称（可选）";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *bundleIdentifier = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *displayName = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![weakSelf isValidBundleIdentifier:bundleIdentifier]) {
            [weakSelf showInvalidBundleIdentifierAlert];
            return;
        }
        KSBallShortcut *shortcut = [[KSBallShortcut alloc] initWithBundleIdentifier:bundleIdentifier displayName:displayName.length > 0 ? displayName : bundleIdentifier];
        if ([weakSelf addShortcut:shortcut]) {
            [weakSelf reloadApplications];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)isValidBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length < 3 || ![bundleIdentifier containsString:@"."] || [bundleIdentifier containsString:@" "]) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-"];
    return [[bundleIdentifier stringByTrimmingCharactersInSet:allowed] length] == 0;
}

- (void)showInvalidBundleIdentifierAlert {
    [self showAlertWithTitle:@"Bundle ID 无效" message:@"请输入类似 com.example.app 的 Bundle ID。"];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
