#import "AppPickerViewController.h"
#import "KSBallSettings.h"
#import "SystemApplicationBridge.h"

@interface AppPickerViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) SystemApplicationBridge *applicationBridge;
@property (nonatomic, copy) NSArray<KSBallApplication *> *applications;
@property (nonatomic, copy) NSArray<KSBallApplication *> *filteredApplications;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation AppPickerViewController

- (instancetype)initWithApplicationBridge:(SystemApplicationBridge *)applicationBridge {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _applicationBridge = applicationBridge;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"添加应用";
    self.tableView.rowHeight = 58.0;
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
    self.applications = self.applicationBridge.availableApplications;
    self.filteredApplications = self.applications;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text.lowercaseString;
    if (query.length == 0) {
        self.filteredApplications = self.applications;
    } else {
        self.filteredApplications = [self.applications filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(KSBallApplication *application, NSDictionary<NSString *,id> *bindings) {
            return [application.displayName.lowercaseString containsString:query] || [application.bundleIdentifier.lowercaseString containsString:query];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.applicationBridge.isAvailable ? 1 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApplications.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"已安装的用户应用";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"默认隐藏系统内部应用。未列出的应用可通过“手动添加”输入 Bundle ID。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ApplicationCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ApplicationCell"];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    KSBallApplication *application = self.filteredApplications[indexPath.row];
    cell.textLabel.text = application.displayName;
    cell.detailTextLabel.text = application.bundleIdentifier;
    cell.imageView.image = application.icon ?: [UIImage systemImageNamed:@"app.fill"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    KSBallApplication *application = self.filteredApplications[indexPath.row];
    KSBallShortcut *shortcut = [[KSBallShortcut alloc] initWithBundleIdentifier:application.bundleIdentifier displayName:application.displayName];
    if (self.selectionHandler) {
        self.selectionHandler(shortcut);
    }
    [self.navigationController popViewControllerAnimated:YES];
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
        if (weakSelf.selectionHandler) {
            weakSelf.selectionHandler(shortcut);
        }
        [weakSelf.navigationController popViewControllerAnimated:YES];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Bundle ID 无效" message:@"请输入类似 com.example.app 的 Bundle ID。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
