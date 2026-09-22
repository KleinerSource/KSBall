@import XCTest;

#import "SystemApplicationBridge.h"

@interface SystemApplicationBridgeTests : XCTestCase
@end

@implementation SystemApplicationBridgeTests

- (void)testInjectedProviderAndLauncherAreUsed {
    __block NSString *launchedBundleIdentifier;
    SystemApplicationBridge *bridge = [[SystemApplicationBridge alloc] initWithApplicationProvider:^NSArray<KSBallApplication *> * _Nonnull{
        return @[[[KSBallApplication alloc] initWithBundleIdentifier:@"com.example.app" displayName:@"Example" icon:nil]];
    } launcher:^BOOL(NSString * _Nonnull bundleIdentifier) {
        launchedBundleIdentifier = bundleIdentifier;
        return YES;
    }];

    XCTAssertTrue(bridge.isAvailable);
    XCTAssertEqual(bridge.availableApplications.count, 1);
    XCTAssertTrue([bridge launchBundleIdentifier:@"com.example.app"]);
    XCTAssertEqualObjects(launchedBundleIdentifier, @"com.example.app");
}

@end
