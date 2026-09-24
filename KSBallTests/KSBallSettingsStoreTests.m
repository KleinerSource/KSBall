@import XCTest;

#import "KSBallSettingsStore.h"

@interface KSBallSettingsStoreTests : XCTestCase
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, copy) NSString *key;
@end

@implementation KSBallSettingsStoreTests

- (void)setUp {
    [super setUp];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"KSBallTests.%@", [[NSUUID UUID] UUIDString]]];
    self.key = @"settings";
}

- (void)tearDown {
    [super tearDown];
}

- (void)testDefaultsAreStable {
    KSBallSettingsStore *store = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertTrue(store.settings.enabled);
    XCTAssertEqual(store.settings.shortcuts.count, 0);
    XCTAssertEqual(store.settings.edge, KSBallEdgeRight);
}

- (void)testMalformedJSONFallsBackToDefaults {
    [self.defaults setObject:[@"not-json" dataUsingEncoding:NSUTF8StringEncoding] forKey:self.key];
    KSBallSettingsStore *store = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqual(store.settings.shortcuts.count, 0);
    XCTAssertEqualWithAccuracy(store.settings.normalizedVerticalPosition, 0.5, 0.001);
}

- (void)testAddCapsAtSixteenAndRejectsDuplicates {
    KSBallSettingsStore *store = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    for (NSUInteger index = 0; index < KSBallMaximumShortcuts; index++) {
        KSBallShortcut *shortcut = [[KSBallShortcut alloc] initWithBundleIdentifier:[NSString stringWithFormat:@"com.example.%lu", (unsigned long)index] displayName:@"App"];
        XCTAssertTrue([store addShortcut:shortcut]);
    }
    XCTAssertFalse([store addShortcut:[[KSBallShortcut alloc] initWithBundleIdentifier:@"com.example.extra" displayName:@"Extra"]]);
    XCTAssertFalse([store addShortcut:[[KSBallShortcut alloc] initWithBundleIdentifier:@"com.example.0" displayName:@"Duplicate"]]);
    XCTAssertEqual(store.settings.shortcuts.count, KSBallMaximumShortcuts);
}

- (void)testOrderPersistsAfterMove {
    KSBallSettingsStore *store = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    [store addShortcut:[[KSBallShortcut alloc] initWithBundleIdentifier:@"com.example.first" displayName:@"First"]];
    [store addShortcut:[[KSBallShortcut alloc] initWithBundleIdentifier:@"com.example.second" displayName:@"Second"]];
    [store moveShortcutFromIndex:0 toIndex:1];

    KSBallSettingsStore *reloadedStore = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqualObjects(reloadedStore.settings.shortcuts.firstObject.bundleIdentifier, @"com.example.second");
}

- (void)testIconMetricsPersistAndClamp {
    KSBallSettingsStore *store = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqualWithAccuracy(store.settings.iconSize, KSBallDefaultIconSize, 0.001);
    XCTAssertEqualWithAccuracy(store.settings.iconSpacing, KSBallDefaultIconSpacing, 0.001);

    [store mutateSettings:^(KSBallSettings *settings) {
        settings.iconSize = 58.0;
        settings.iconSpacing = 1000.0;
    }];
    KSBallSettingsStore *reloadedStore = [[KSBallSettingsStore alloc] initWithUserDefaults:self.defaults key:self.key];
    XCTAssertEqualWithAccuracy(reloadedStore.settings.iconSize, 58.0, 0.001);
    XCTAssertEqualWithAccuracy(reloadedStore.settings.iconSpacing, KSBallMaximumIconSpacing, 0.001);
}

@end
