#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger KSBallMaximumShortcuts;

typedef NS_ENUM(NSInteger, KSBallEdge) {
    KSBallEdgeLeft = 0,
    KSBallEdgeRight = 1,
};

typedef NS_ENUM(NSInteger, KSBallFanBias) {
    KSBallFanBiasUpper = -1,
    KSBallFanBiasCenter = 0,
    KSBallFanBiasLower = 1,
};

@interface KSBallShortcut : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSUUID *identifier;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)shortcutFromDictionary:(NSDictionary<NSString *, id> *)dictionary;

@end

@interface KSBallSettings : NSObject <NSCopying>

@property (nonatomic) BOOL enabled;
@property (nonatomic) KSBallEdge edge;
@property (nonatomic) CGFloat normalizedVerticalPosition;
@property (nonatomic) KSBallFanBias fanBias;
@property (nonatomic, strong) NSMutableArray<KSBallShortcut *> *shortcuts;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
