#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KSBallSharedStorage : NSObject

+ (nullable NSData *)dataForKey:(NSString *)key;
+ (BOOL)setData:(NSData *)data forKey:(NSString *)key;
+ (void)removeDataForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
