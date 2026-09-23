#import "KSBallSharedStorage.h"
#import <sys/stat.h>

static NSString * const KSBallSharedStorageDirectory = @"/var/mobile/KSBall/UserDefaults";

@implementation KSBallSharedStorage

+ (NSString *)pathForKey:(NSString *)key {
    return [KSBallSharedStorageDirectory stringByAppendingPathComponent:key];
}

+ (BOOL)ensureDirectory {
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:KSBallSharedStorageDirectory
                                            withIntermediateDirectories:YES
                                                             attributes:@{NSFilePosixPermissions: @(0755)}
                                                                  error:&error];
    if (!created) {
        NSLog(@"KSBall shared storage directory creation failed: %@", error.localizedDescription);
    }
    return created;
}

+ (NSData *)dataForKey:(NSString *)key {
    if (![self ensureDirectory]) {
        return nil;
    }
    return [NSData dataWithContentsOfFile:[self pathForKey:key]];
}

+ (BOOL)setData:(NSData *)data forKey:(NSString *)key {
    if (![self ensureDirectory]) {
        return NO;
    }

    NSString *path = [self pathForKey:key];
    NSError *error = nil;
    BOOL written = [data writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionNone error:&error];
    if (!written) {
        NSLog(@"KSBall shared storage write failed: %@", error.localizedDescription);
        return NO;
    }
    chmod(path.fileSystemRepresentation, 0644);
    return YES;
}

+ (void)removeDataForKey:(NSString *)key {
    if (![self ensureDirectory]) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self pathForKey:key] error:nil];
}

@end
