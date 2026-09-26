#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const KSBallUpdateErrorDomain;
/// 检查开始或结束时发出，object 为对应的检查器。
FOUNDATION_EXPORT NSNotificationName const KSBallUpdateCheckerDidChangeNotification;

typedef NS_ERROR_ENUM(KSBallUpdateErrorDomain, KSBallUpdateError) {
    /// GitHub 返回了非 2xx 状态码。
    KSBallUpdateErrorHTTPStatus = 1,
    /// 响应中没有可安装的构建（缺少安装包或无法识别版本）。
    KSBallUpdateErrorInvalidRelease = 2,
};

/// x.y.z+build 形式的应用版本：x.y.z 对应 CFBundleShortVersionString，build 对应 CFBundleVersion。
@interface KSBallAppVersion : NSObject

@property (nonatomic, readonly) NSInteger major;
@property (nonatomic, readonly) NSInteger minor;
@property (nonatomic, readonly) NSInteger patch;
@property (nonatomic, readonly) NSInteger build;
/// 与 CI 产物名一致的 x.y.z+build。
@property (nonatomic, copy, readonly) NSString *stringValue;
/// 界面展示用的 x.y.z (build)，与设置页底部的版本号格式一致。
@property (nonatomic, copy, readonly) NSString *displayString;

- (instancetype)initWithMajor:(NSInteger)major minor:(NSInteger)minor patch:(NSInteger)patch build:(NSInteger)build;
/// 在文本中查找第一个 x.y.z 或 x.y.z+build，缺少 build 时视为 0。
+ (nullable instancetype)versionFromString:(nullable NSString *)string;
/// 由 CFBundleShortVersionString（允许省略补丁号）与 CFBundleVersion 组成版本。
+ (nullable instancetype)versionWithShortVersion:(nullable NSString *)shortVersion buildNumber:(nullable NSString *)buildNumber;
/// 依次比较主版本、次版本、补丁号与构建号。
- (NSComparisonResult)compare:(KSBallAppVersion *)other;

@end

/// GitHub Release 中可供 TrollStore 安装的构建。
@interface KSBallRelease : NSObject

@property (nonatomic, copy, readonly) NSString *tagName;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, strong, readonly) KSBallAppVersion *version;
@property (nonatomic, copy, readonly) NSString *assetName;
@property (nonatomic, copy, readonly) NSURL *downloadURL;
@property (nonatomic, copy, readonly, nullable) NSURL *pageURL;
/// 去掉 CI 附加的版本号、commit 与 run 链接后的更新内容。
@property (nonatomic, copy, readonly) NSString *notes;

/// 解析 GitHub Release API 的 JSON；草稿、缺少 .tipa / .ipa 安装包或无法识别版本时返回 nil。
+ (nullable instancetype)releaseFromJSONObject:(nullable id)object;

@end

typedef void (^KSBallUpdateFetchCompletion)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error);
typedef void (^KSBallUpdateFetcher)(NSURLRequest *request, KSBallUpdateFetchCompletion completion);
typedef void (^KSBallUpdateCheckCompletion)(KSBallRelease * _Nullable release, NSError * _Nullable error);

/// 从 GitHub Release 检查新版本，并交给 TrollStore 安装。
@interface KSBallUpdateChecker : NSObject

@property (nonatomic, strong, readonly) KSBallAppVersion *currentVersion;
@property (nonatomic, readonly, getter=isChecking) BOOL checking;
/// 最近一次检查成功时得到的发布（不论是否比当前版本新）；最近一次检查失败时为 nil。
@property (nonatomic, strong, readonly, nullable) KSBallRelease *latestRelease;
/// 最近一次检查失败的原因；检查成功时为 nil。
@property (nonatomic, strong, readonly, nullable) NSError *lastError;
/// 最近一次检查成功的时间。
@property (nonatomic, strong, readonly, nullable) NSDate *lastCheckDate;
/// 打开配置页时是否自动检查，默认开启。
@property (nonatomic, getter=isAutomaticCheckEnabled) BOOL automaticCheckEnabled;
/// 检查开发版 Release（dev）；关闭时检查标准版 Release（latest）。
@property (nonatomic, getter=isBetaUpdatesEnabled) BOOL betaUpdatesEnabled;

+ (instancetype)sharedChecker;
/// fetcher 为空时用 NSURLSession 请求 releaseURL。
- (instancetype)initWithReleaseURL:(NSURL *)releaseURL currentVersion:(KSBallAppVersion *)currentVersion userDefaults:(NSUserDefaults *)userDefaults fetcher:(nullable KSBallUpdateFetcher)fetcher;
/// 请求最新发布，completion 总在主线程回调；检查进行中时会等待同一次检查的结果。
- (void)checkForUpdatesWithCompletion:(nullable KSBallUpdateCheckCompletion)completion;
- (BOOL)isUpdateRelease:(KSBallRelease *)release;
- (BOOL)isReleaseIgnored:(KSBallRelease *)release;
- (void)ignoreRelease:(KSBallRelease *)release;
/// TrollStore 的安装链接：apple-magnifier://install?url=<安装包地址>。
+ (NSURL *)installURLForRelease:(KSBallRelease *)release;

@end

NS_ASSUME_NONNULL_END
