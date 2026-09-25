#import <UIKit/UIKit.h>
#import <mach/mach.h>

// 悬浮分屏用到的 FrontBoard / RunningBoard / UIKit 私有接口，摘自 FrontBoardAppLauncher。
// 这些类都不在公开 SDK 中，也不链接私有框架：一律通过 KSBallPrivateClass 在运行时取得，
// 直接写类名发消息会生成类引用，导致链接失败。

NS_ASSUME_NONNULL_BEGIN

#define KSBallPrivateClass(name) ((Class)NSClassFromString(@#name))

@class FBScene, RBSProcessIdentity, UIScenePresentationManager, UIMutableScenePresentationContext;

@interface BSTransaction : NSObject
- (void)begin;
- (void)setCompletionBlock:(nullable dispatch_block_t)block;
@end

#pragma mark - RunningBoardServices

@interface RBSProcessIdentity : NSObject
+ (instancetype)identityForEmbeddedApplicationIdentifier:(NSString *)identifier;
@end

@interface RBSProcessPredicate : NSObject
+ (instancetype)predicateMatchingIdentity:(RBSProcessIdentity *)identity;
@end

@interface RBSProcessHandle : NSObject
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
+ (nullable instancetype)handleForPredicate:(RBSProcessPredicate *)predicate error:(NSError * _Nullable * _Nullable)error;
- (audit_token_t)auditToken;
- (int)pid;
@end

#pragma mark - FrontBoard

@interface FBProcessExecutionContext : NSObject
@end

@interface FBMutableProcessExecutionContext : FBProcessExecutionContext
@property (nonatomic, copy) RBSProcessIdentity *identity;
@property (nonatomic, copy) NSDictionary *environment;
@property (nonatomic) long long launchIntent;
@end

@interface FBProcessManager : NSObject
+ (instancetype)sharedInstance;
- (nullable id)launchProcessWithContext:(FBMutableProcessExecutionContext *)context;
- (void)registerProcessForAuditToken:(audit_token_t)token;
@end

@interface FBApplicationProcessLaunchTransaction : BSTransaction
- (instancetype)initWithProcessIdentity:(RBSProcessIdentity *)identity executionContextProvider:(id _Nullable (^)(void))provider;
@end

@interface FBSSceneIdentity : NSObject
+ (instancetype)identityForIdentifier:(NSString *)identifier;
@end

@interface FBSSceneClientIdentity : NSObject
+ (instancetype)identityForProcessIdentity:(RBSProcessIdentity *)identity;
@end

@interface FBSSceneSpecification : NSObject
+ (instancetype)specification;
@end

@interface FBSMutableSceneDefinition : NSObject
@property (nonatomic, copy) FBSSceneIdentity *identity;
@property (nonatomic, copy) FBSSceneClientIdentity *clientIdentity;
@property (nonatomic, copy) FBSSceneSpecification *specification;
+ (instancetype)definition;
@end

@interface FBSMutableSceneParameters : NSObject
@property (nonatomic, copy) id settings;
@property (nonatomic, copy) id clientSettings;
+ (instancetype)parametersForSpecification:(FBSSceneSpecification *)specification;
@end

@interface UIMutableApplicationSceneSettings : NSObject
@property (nonatomic) BOOL canShowAlerts;
@property (nonatomic, strong, nullable) id displayConfiguration;
@property (nonatomic, getter=isForeground) BOOL foreground;
@property (nonatomic) CGRect frame;
@property (nonatomic) UIInterfaceOrientation interfaceOrientation;
@property (nonatomic) UIDeviceOrientation deviceOrientation;
@property (nonatomic) NSInteger level;
@property (nonatomic, copy, nullable) NSString *persistenceIdentifier;
@property (nonatomic) UIEdgeInsets peripheryInsets;
@property (nonatomic) UIEdgeInsets safeAreaInsetsPortrait;
@property (nonatomic) BOOL statusBarDisabled;
@property (nonatomic) UIUserInterfaceStyle userInterfaceStyle;
@end

@interface UIMutableApplicationSceneClientSettings : NSObject
@property (nonatomic) UIInterfaceOrientation interfaceOrientation;
@property (nonatomic) NSInteger statusBarStyle;
@end

@interface FBScene : NSObject
- (UIScenePresentationManager *)uiPresentationManager;
- (void)updateSettingsWithBlock:(void (^)(UIMutableApplicationSceneSettings *settings))block;
@end

@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
- (nullable FBScene *)createSceneWithDefinition:(FBSMutableSceneDefinition *)definition initialParameters:(FBSMutableSceneParameters *)parameters;
- (void)destroyScene:(NSString *)sceneIdentifier withTransitionContext:(nullable id)transitionContext;
@end

#pragma mark - UIKit

@interface UIMutableScenePresentationContext : NSObject
@property (nonatomic) NSUInteger appearanceStyle;
@end

@interface _UIScenePresenter : NSObject
@property (nonatomic, readonly) UIView *presentationView;
@property (nonatomic, readonly) FBScene *scene;
- (void)modifyPresentationContext:(void (^)(UIMutableScenePresentationContext *context))block;
- (void)activate;
- (void)deactivate;
- (void)invalidate;
@end

@interface UIScenePresentationManager : NSObject
- (_UIScenePresenter *)createPresenterWithIdentifier:(NSString *)identifier;
@end

@interface UIScreen (KSBallFrontBoardPrivate)
- (id)displayConfiguration;
@end

NS_ASSUME_NONNULL_END
