#import "KSBallSharedStorage.h"
#import <sys/stat.h>
#import <unistd.h>

static NSString * const KSBallSharedStorageDirectory = @"/var/mobile/KSBall/UserDefaults";
static const uid_t KSBallMobileUserIdentifier = 501;
static const gid_t KSBallMobileGroupIdentifier = 501;

@implementation KSBallSharedStorage

+ (NSString *)pathForKey:(NSString *)key {
    return [KSBallSharedStorageDirectory stringByAppendingPathComponent:key];
}

// HUD 子进程以 root persona 运行。它创建的目录和文件必须交还给 mobile，
// 否则以 mobile 运行的主程序无法再写入设置，配置页的修改就不会同步到悬浮条。
+ (void)grantMobileAccessToPath:(NSString *)path {
    if (geteuid() == 0) {
        chown(path.fileSystemRepresentation, KSBallMobileUserIdentifier, KSBallMobileGroupIdentifier);
    }
}

+ (BOOL)ensureDirectory {
    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:KSBallSharedStorageDirectory
                                            withIntermediateDirectories:YES
                                                             attributes:@{NSFilePosixPermissions: @(0755)}
                                                                  error:&error];
    if (!created) {
        NSLog(@"KSBall shared storage directory creation failed: %@", error.localizedDescription);
        return NO;
    }
    [self grantMobileAccessToPath:KSBallSharedStorageDirectory.stringByDeletingLastPathComponent];
    [self grantMobileAccessToPath:KSBallSharedStorageDirectory];
    return YES;
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
    [self grantMobileAccessToPath:path];
    return YES;
}

+ (void)removeDataForKey:(NSString *)key {
    if (![self ensureDirectory]) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self pathForKey:key] error:nil];
}

@end
