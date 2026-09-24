#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger KSBallMaximumShortcuts;
FOUNDATION_EXPORT const CGFloat KSBallMinimumIconSize;
FOUNDATION_EXPORT const CGFloat KSBallMaximumIconSize;
FOUNDATION_EXPORT const CGFloat KSBallDefaultIconSize;
FOUNDATION_EXPORT const CGFloat KSBallMinimumIconSpacing;
FOUNDATION_EXPORT const CGFloat KSBallMaximumIconSpacing;
FOUNDATION_EXPORT const CGFloat KSBallDefaultIconSpacing;

typedef NS_ENUM(NSInteger, KSBallEdge) {
    KSBallEdgeLeft = 0,
    KSBallEdgeRight = 1,
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
@property (nonatomic) CGFloat iconSize;
@property (nonatomic) CGFloat iconSpacing;
@property (nonatomic, strong) NSMutableArray<KSBallShortcut *> *shortcuts;

+ (instancetype)defaultSettings;
- (void)normalize;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (instancetype)settingsFromDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;

@end

NS_ASSUME_NONNULL_END
