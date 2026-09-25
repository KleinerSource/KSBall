#import "AppPickerViewController.h"
#import "KSBallSettings.h"
#import "SystemApplicationBridge.h"

static const KSBallApplicationCategory KSBallPickerCategories[] = {
    KSBallApplicationCategoryUser,
    KSBallApplicationCategoryTrollStore,
    KSBallApplicationCategorySystem,
};
static const NSInteger KSBallPickerCategoryCount = sizeof(KSBallPickerCategories) / sizeof(KSBallPickerCategories[0]);

@interface AppPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
// 尚未添加的应用，按分类存放。
@property (nonatomic, copy) NSArray<NSArray<KSBallApplication *> *> *applicationsByCategory;
// 当前分类经搜索过滤后的列表，即表格的数据源。
@property (nonatomic, copy) NSArray<KSBallApplication *> *visibleApplications;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UISegmentedControl *categoryControl;
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
        _applicationsByCategory = @[@[], @[], @[]];
        _visibleApplications = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateTitle];
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

    self.categoryControl = [[UISegmentedControl alloc] initWithItems:@[@"用户应用", @"巨魔应用", @"系统应用"]];
    self.categoryControl.selectedSegmentIndex = 0;
    [self.categoryControl addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, CGRectGetWidth(self.tableView.bounds), 52.0)];
    self.categoryControl.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.categoryControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.categoryControl.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [self.categoryControl.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [self.categoryControl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
    self.tableView.tableHeaderView = header;

    [self reloadApplications];
}

- (void)reloadApplications {
    // 已在快捷列表中的应用直接隐藏。
    NSMutableArray<NSMutableArray<KSBallApplication *> *> *groups = [NSMutableArray array];
    for (NSInteger index = 0; index < KSBallPickerCategoryCount; index++) {
        [groups addObject:[NSMutableArray array]];
    }
    for (KSBallApplication *application in self.applicationBridge.availableApplications) {
        if ([self.existingBundleIdentifiers containsObject:application.bundleIdentifier.lowercaseString]) {
            continue;
        }
        [groups[[self segmentIndexForCategory:application.category]] addObject:application];
    }
    self.applicationsByCategory = groups;
    [self refreshVisibleApplications];
}

- (NSInteger)segmentIndexForCategory:(KSBallApplicationCategory)category {
    for (NSInteger index = 0; index < KSBallPickerCategoryCount; index++) {
        if (KSBallPickerCategories[index] == category) {
            return index;
        }
    }
    return 0;
}

- (void)categoryChanged:(UISegmentedControl *)sender {
    [self refreshVisibleApplications];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self refreshVisibleApplications];
}

- (void)refreshVisibleApplications {
    NSInteger selectedIndex = MAX(self.categoryControl.selectedSegmentIndex, 0);
    NSArray<KSBallApplication *> *applications = self.applicationsByCategory[selectedIndex];
    NSString *query = self.searchController.searchBar.text.lowercaseString;
    if (query.length > 0) {
        applications = [applications filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(KSBallApplication *application, NSDictionary<NSString *,id> *bindings) {
            return [application.displayName.lowercaseString containsString:query] || [application.bundleIdentifier.lowercaseString containsString:query];
        }]];
    }
    self.visibleApplications = applications;
    [self updateSegmentTitles];
    [self.tableView reloadData];
}

- (void)updateSegmentTitles {
    NSArray<NSString *> *titles = @[@"用户应用", @"巨魔应用", @"系统应用"];
    [titles enumerateObjectsUsingBlock:^(NSString * _Nonnull title, NSUInteger index, BOOL * _Nonnull stop) {
        [self.categoryControl setTitle:[NSString stringWithFormat:@"%@ %lu", title, (unsigned long)self.applicationsByCategory[index].count] forSegmentAtIndex:index];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.applicationBridge.isAvailable ? 1 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleApplications.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.visibleApplications.count == 0) {
        return self.searchController.searchBar.text.length > 0 ? @"没有匹配的应用。" : @"这一类中没有可添加的应用。";
    }
    return @"点应用前的 + 号即可加入快捷列表，可连续添加多个。已添加的应用不会出现在这里；未列出的应用可通过“手动添加”输入 Bundle ID。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApplicationCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ApplicationCell"];
    }
    KSBallApplication *application = self.visibleApplications[indexPath.row];
    cell.textLabel.text = application.displayName;
    cell.detailTextLabel.text = application.bundleIdentifier;
    cell.imageView.image = [self listIconForApplication:application];
    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleInsert;
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
    if (indexPath.section != 0 || indexPath.row >= (NSInteger)self.visibleApplications.count) {
        return;
    }
    KSBallApplication *application = self.visibleApplications[indexPath.row];
    KSBallShortcut *shortcut = [[KSBallShortcut alloc] initWithBundleIdentifier:application.bundleIdentifier displayName:application.displayName];
    if (![self addShortcut:shortcut]) {
        return;
    }
    // 先同步更新数据源再删除这一行，不做批量更新和分组重载：
    // 连续快速点击时多个更新交叠会让行数校验失败并直接崩溃。
    NSInteger categoryIndex = [self segmentIndexForCategory:application.category];
    NSMutableArray<NSArray<KSBallApplication *> *> *groups = [self.applicationsByCategory mutableCopy];
    NSMutableArray<KSBallApplication *> *group = [groups[categoryIndex] mutableCopy];
    [group removeObjectIdenticalTo:application];
    groups[categoryIndex] = group;
    self.applicationsByCategory = groups;
    NSMutableArray<KSBallApplication *> *visibleApplications = [self.visibleApplications mutableCopy];
    [visibleApplications removeObjectAtIndex:indexPath.row];
    self.visibleApplications = visibleApplications;
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    [self updateSegmentTitles];
    [self updateTitle];
}

- (void)updateTitle {
    self.title = [NSString stringWithFormat:@"添加应用（剩余 %lu）", (unsigned long)self.remainingCapacity];
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
            [weakSelf showAlertWithTitle:@"Bundle ID 无效" message:@"请输入类似 com.example.app 的 Bundle ID。"];
            return;
        }
        KSBallShortcut *shortcut = [[KSBallShortcut alloc] initWithBundleIdentifier:bundleIdentifier displayName:displayName.length > 0 ? displayName : bundleIdentifier];
        if ([weakSelf addShortcut:shortcut]) {
            [weakSelf reloadApplications];
            [weakSelf updateTitle];
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

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
