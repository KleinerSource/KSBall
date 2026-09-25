#import "KSBallUpdateChecker.h"

NSErrorDomain const KSBallUpdateErrorDomain = @"KSBallUpdateErrorDomain";
NSNotificationName const KSBallUpdateCheckerDidChangeNotification = @"KSBallUpdateCheckerDidChangeNotification";
// GitHub Actions 每次成功构建 main 分支都会重建这个滚动预发布。
static NSString * const KSBallUpdateReleaseURLString = @"https://api.github.com/repos/KleinerSource/KSBall/releases/tags/latest";
static NSString * const KSBallUpdateIgnoredVersionDefaultsKey = @"KSBall.Update.IgnoredVersion";
static NSString * const KSBallUpdateAutomaticCheckDefaultsKey = @"KSBall.Update.AutomaticCheck";
static const NSTimeInterval KSBallUpdateRequestTimeout = 15.0;

static NSString *KSBallTrimmedString(id value) {
    return [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}

@implementation KSBallAppVersion

- (instancetype)initWithMajor:(NSInteger)major minor:(NSInteger)minor patch:(NSInteger)patch build:(NSInteger)build {
    self = [super init];
    if (self) {
        _major = major;
        _minor = minor;
        _patch = patch;
        _build = build;
    }
    return self;
}

+ (instancetype)versionFromString:(NSString *)string {
    if (string.length == 0) {
        return nil;
    }
    static NSRegularExpression *expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 前面不能紧邻数字或点、后面不能紧邻数字，避免把更长数字串的一部分当成版本号。
        expression = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9.])v?([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:\\+([0-9]+))?(?![0-9])" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSTextCheckingResult *match = [expression firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match) {
        return nil;
    }
    NSInteger components[4] = {0, 0, 0, 0};
    for (NSUInteger index = 0; index < 4; index++) {
        NSRange range = [match rangeAtIndex:index + 1];
        if (range.location != NSNotFound) {
            components[index] = [string substringWithRange:range].integerValue;
        }
    }
    return [[self alloc] initWithMajor:components[0] minor:components[1] patch:components[2] build:components[3]];
}

+ (instancetype)versionWithShortVersion:(NSString *)shortVersion buildNumber:(NSString *)buildNumber {
    NSArray<NSString *> *parts = [shortVersion componentsSeparatedByString:@"."];
    if (shortVersion.length == 0 || parts.count > 3) {
        return nil;
    }
    NSCharacterSet *nonDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    NSInteger components[3] = {0, 0, 0};
    for (NSUInteger index = 0; index < parts.count; index++) {
        if (parts[index].length == 0 || [parts[index] rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            return nil;
        }
        components[index] = parts[index].integerValue;
    }
    return [[self alloc] initWithMajor:components[0] minor:components[1] patch:components[2] build:buildNumber.integerValue];
}

- (NSString *)stringValue {
    return [NSString stringWithFormat:@"%ld.%ld.%ld+%ld", (long)self.major, (long)self.minor, (long)self.patch, (long)self.build];
}

- (NSString *)displayString {
    return [NSString stringWithFormat:@"%ld.%ld.%ld (%ld)", (long)self.major, (long)self.minor, (long)self.patch, (long)self.build];
}

- (NSComparisonResult)compare:(KSBallAppVersion *)other {
    NSInteger left[] = {self.major, self.minor, self.patch, self.build};
    NSInteger right[] = {other.major, other.minor, other.patch, other.build};
    for (NSUInteger index = 0; index < 4; index++) {
        if (left[index] != right[index]) {
            return left[index] < right[index] ? NSOrderedAscending : NSOrderedDescending;
        }
    }
    return NSOrderedSame;
}

- (NSString *)description {
    return self.stringValue;
}

@end

@implementation KSBallRelease

- (instancetype)initWithTagName:(NSString *)tagName title:(NSString *)title version:(KSBallAppVersion *)version assetName:(NSString *)assetName downloadURL:(NSURL *)downloadURL pageURL:(NSURL *)pageURL notes:(NSString *)notes {
    self = [super init];
    if (self) {
        _tagName = [tagName copy];
        _title = [title copy];
        _version = version;
        _assetName = [assetName copy];
        _downloadURL = [downloadURL copy];
        _pageURL = [pageURL copy];
        _notes = [notes copy];
    }
    return self;
}

+ (instancetype)releaseFromJSONObject:(id)object {
    if (![object isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSDictionary *dictionary = object;
    if ([dictionary[@"draft"] isKindOfClass:NSNumber.class] && [dictionary[@"draft"] boolValue]) {
        return nil;
    }
    NSDictionary *asset = [self installableAssetInAssets:dictionary[@"assets"]];
    if (!asset) {
        return nil;
    }
    NSURL *downloadURL = [NSURL URLWithString:KSBallTrimmedString(asset[@"browser_download_url"])];
    if (![downloadURL.scheme.lowercaseString isEqualToString:@"https"]) {
        return nil;
    }

    NSString *tagName = KSBallTrimmedString(dictionary[@"tag_name"]);
    NSString *title = KSBallTrimmedString(dictionary[@"name"]);
    NSString *body = KSBallTrimmedString(dictionary[@"body"]);
    NSString *assetName = KSBallTrimmedString(asset[@"name"]);
    // 标题与说明由 CI 写入版本号；安装包文件名中的特殊字符可能被 GitHub 改写，只作兜底。
    KSBallAppVersion *version = nil;
    for (NSString *candidate in @[title, body, assetName, tagName]) {
        version = [KSBallAppVersion versionFromString:candidate];
        if (version) {
            break;
        }
    }
    if (!version) {
        return nil;
    }

    NSString *pageURLString = KSBallTrimmedString(dictionary[@"html_url"]);
    NSURL *pageURL = pageURLString.length > 0 ? [NSURL URLWithString:pageURLString] : nil;
    return [[self alloc] initWithTagName:tagName title:title version:version assetName:assetName downloadURL:downloadURL pageURL:pageURL notes:[self notesFromBody:body]];
}

// 优先选择 TrollStore 专用的 .tipa，其次是普通 .ipa；校验文件与构建日志会被跳过。
+ (NSDictionary *)installableAssetInAssets:(id)assets {
    if (![assets isKindOfClass:NSArray.class]) {
        return nil;
    }
    NSDictionary *ipaAsset = nil;
    for (id asset in assets) {
        if (![asset isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *name = KSBallTrimmedString(asset[@"name"]).lowercaseString;
        if ([name hasSuffix:@".tipa"]) {
            return asset;
        }
        if (!ipaAsset && [name hasSuffix:@".ipa"]) {
            ipaAsset = asset;
        }
    }
    return ipaAsset;
}

// CI 生成的说明依次是“版本: x.y.z+build”、“本次构建包含以下更新：”、提交列表以及 commit 与 run 链接，
// 这里只保留提交列表。
+ (NSString *)notesFromBody:(NSString *)body {
    NSString *notes = [body stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSRange heading = [notes rangeOfString:@"本次构建包含以下更新"];
    if (heading.location != NSNotFound) {
        NSRange lineEnd = [notes rangeOfString:@"\n" options:0 range:NSMakeRange(NSMaxRange(heading), notes.length - NSMaxRange(heading))];
        notes = lineEnd.location == NSNotFound ? @"" : [notes substringFromIndex:NSMaxRange(lineEnd)];
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [notes componentsSeparatedByString:@"\n"]) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        if ([trimmedLine hasPrefix:@"commit:"] || [trimmedLine hasPrefix:@"run:"]) {
            continue;
        }
        [lines addObject:line];
    }
    return [[lines componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@end

@interface KSBallUpdateChecker ()
@property (nonatomic, copy) NSURL *releaseURL;
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, copy) KSBallUpdateFetcher fetcher;
// 检查进行中再次请求时的回调，在同一次检查结束后一并调用。
@property (nonatomic, strong) NSMutableArray<KSBallUpdateCheckCompletion> *pendingCompletions;
@property (nonatomic, readwrite, getter=isChecking) BOOL checking;
@property (nonatomic, strong, readwrite, nullable) KSBallRelease *latestRelease;
@property (nonatomic, strong, readwrite, nullable) NSError *lastError;
@property (nonatomic, strong, readwrite, nullable) NSDate *lastCheckDate;
@end

@implementation KSBallUpdateChecker

+ (instancetype)sharedChecker {
    static KSBallUpdateChecker *checker;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        NSString *shortVersion = [info[@"CFBundleShortVersionString"] isKindOfClass:NSString.class] ? info[@"CFBundleShortVersionString"] : nil;
        NSString *buildNumber = [info[@"CFBundleVersion"] isKindOfClass:NSString.class] ? info[@"CFBundleVersion"] : nil;
        KSBallAppVersion *currentVersion = [KSBallAppVersion versionWithShortVersion:shortVersion buildNumber:buildNumber] ?: [[KSBallAppVersion alloc] initWithMajor:0 minor:0 patch:0 build:0];
        checker = [[self alloc] initWithReleaseURL:[NSURL URLWithString:KSBallUpdateReleaseURLString] currentVersion:currentVersion userDefaults:NSUserDefaults.standardUserDefaults fetcher:nil];
    });
    return checker;
}

- (instancetype)initWithReleaseURL:(NSURL *)releaseURL currentVersion:(KSBallAppVersion *)currentVersion userDefaults:(NSUserDefaults *)userDefaults fetcher:(KSBallUpdateFetcher)fetcher {
    self = [super init];
    if (self) {
        _releaseURL = [releaseURL copy];
        _currentVersion = currentVersion;
        _userDefaults = userDefaults;
        _pendingCompletions = [NSMutableArray array];
        if (fetcher) {
            _fetcher = [fetcher copy];
        } else {
            _fetcher = ^(NSURLRequest *request, KSBallUpdateFetchCompletion completion) {
                [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    completion(data, [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil, error);
                }] resume];
            };
        }
    }
    return self;
}

- (BOOL)isAutomaticCheckEnabled {
    id value = [self.userDefaults objectForKey:KSBallUpdateAutomaticCheckDefaultsKey];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

- (void)setAutomaticCheckEnabled:(BOOL)automaticCheckEnabled {
    [self.userDefaults setBool:automaticCheckEnabled forKey:KSBallUpdateAutomaticCheckDefaultsKey];
}

- (void)checkForUpdatesWithCompletion:(KSBallUpdateCheckCompletion)completion {
    if (completion) {
        [self.pendingCompletions addObject:[completion copy]];
    }
    if (self.checking) {
        return;
    }
    self.checking = YES;
    [self postChange];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.releaseURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:KSBallUpdateRequestTimeout];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [request setValue:[NSString stringWithFormat:@"KSBall/%@", self.currentVersion.stringValue] forHTTPHeaderField:@"User-Agent"];
    self.fetcher(request, ^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        NSError *checkError = error;
        KSBallRelease *release = checkError ? nil : [KSBallUpdateChecker releaseFromData:data response:response error:&checkError];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishCheckWithRelease:release error:checkError];
        });
    });
}

+ (KSBallRelease *)releaseFromData:(NSData *)data response:(NSHTTPURLResponse *)response error:(NSError **)error {
    NSInteger statusCode = response.statusCode;
    if (statusCode < 200 || statusCode >= 300) {
        NSString *description = nil;
        if (statusCode == 404) {
            description = @"GitHub 上还没有可安装的发布（HTTP 404）。";
        } else if (statusCode == 403 || statusCode == 429) {
            description = [NSString stringWithFormat:@"GitHub 接口请求过于频繁，请稍后再试（HTTP %ld）。", (long)statusCode];
        } else {
            description = [NSString stringWithFormat:@"GitHub 返回了异常状态（HTTP %ld）。", (long)statusCode];
        }
        *error = [NSError errorWithDomain:KSBallUpdateErrorDomain code:KSBallUpdateErrorHTTPStatus userInfo:@{NSLocalizedDescriptionKey: description}];
        return nil;
    }
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    KSBallRelease *release = [KSBallRelease releaseFromJSONObject:object];
    if (!release) {
        *error = [NSError errorWithDomain:KSBallUpdateErrorDomain code:KSBallUpdateErrorInvalidRelease userInfo:@{NSLocalizedDescriptionKey: @"最新发布中没有可供 TrollStore 安装的构建。"}];
    }
    return release;
}

- (void)finishCheckWithRelease:(KSBallRelease *)release error:(NSError *)error {
    self.checking = NO;
    self.latestRelease = release;
    self.lastError = release ? nil : error;
    if (release) {
        self.lastCheckDate = NSDate.date;
    }
    NSArray<KSBallUpdateCheckCompletion> *completions = [self.pendingCompletions copy];
    [self.pendingCompletions removeAllObjects];
    [self postChange];
    for (KSBallUpdateCheckCompletion completion in completions) {
        completion(release, self.lastError);
    }
}

- (void)postChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:KSBallUpdateCheckerDidChangeNotification object:self];
}

- (BOOL)isUpdateRelease:(KSBallRelease *)release {
    return [release.version compare:self.currentVersion] == NSOrderedDescending;
}

- (BOOL)isReleaseIgnored:(KSBallRelease *)release {
    return [[self.userDefaults stringForKey:KSBallUpdateIgnoredVersionDefaultsKey] isEqualToString:release.version.stringValue];
}

- (void)ignoreRelease:(KSBallRelease *)release {
    [self.userDefaults setObject:release.version.stringValue forKey:KSBallUpdateIgnoredVersionDefaultsKey];
}

+ (NSURL *)installURLForRelease:(KSBallRelease *)release {
    // 下载地址作为查询参数交给 TrollStore，除非保留字符外全部转义，TrollStore 解码后即为原始地址。
    NSCharacterSet *unreservedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encodedURL = [release.downloadURL.absoluteString stringByAddingPercentEncodingWithAllowedCharacters:unreservedCharacters];
    return [NSURL URLWithString:[@"apple-magnifier://install?url=" stringByAppendingString:encodedURL]];
}

@end
