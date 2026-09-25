#import "HUDTouchEventBridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import "PassthroughHUDWindow.h"

typedef struct __IOHIDEvent *KSBallIOHIDEventRef;
typedef struct __IOHIDService *KSBallIOHIDServiceRef;
// 与小端平台上 MacTypes 的 AbsoluteTime（UnsignedWide）布局一致：低 32 位在前。
typedef struct {
    uint32_t lo;
    uint32_t hi;
} KSBallAbsoluteTime;

typedef KSBallIOHIDEventRef (*KSBallCreateDigitizerEventFunction)(CFAllocatorRef, KSBallAbsoluteTime, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef KSBallIOHIDEventRef (*KSBallCreateFingerEventFunction)(CFAllocatorRef, KSBallAbsoluteTime, uint32_t, uint32_t, uint32_t, double, double, double, double, double, double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef void (*KSBallAppendHIDEventFunction)(KSBallIOHIDEventRef, KSBallIOHIDEventRef);
typedef void (*KSBallSetHIDIntegerFunction)(KSBallIOHIDEventRef, uint32_t, int);
typedef void (*KSBallHIDEventCallback)(void *, void *, KSBallIOHIDServiceRef, KSBallIOHIDEventRef);
typedef void *(*KSBallRegisterHIDEventCallbackFunction)(KSBallHIDEventCallback);

@interface UIApplication (KSBallHUDTouchPrivate)
- (UIEvent *)_touchesEvent;
- (void)_enqueueHIDEvent:(KSBallIOHIDEventRef)event;
@end

@interface UIEvent (KSBallHUDTouchPrivate)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
@end

@interface UITouch (KSBallHUDPrivateAPIs)
- (void)setWindow:(UIWindow *)window;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)resetPrevious;
- (void)setView:(UIView *)view;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setIsTapToClick:(BOOL)value;
- (void)setGestureView:(UIView *)view;
- (void)_setHidEvent:(KSBallIOHIDEventRef)event;
@end

@interface UITouch (KSBallTouchEventBridge)
- (instancetype)initKSBallAtPoint:(CGPoint)point inWindow:(UIWindow *)window onView:(UIView *)view;
- (void)setLocationInWindow:(CGPoint)location;
- (void)setPhaseAndUpdateTimestamp:(UITouchPhase)phase;
@end

@implementation UITouch (KSBallTouchEventBridge)

- (instancetype)initKSBallAtPoint:(CGPoint)point inWindow:(UIWindow *)window onView:(UIView *)view {
    self = [super init];
    if (!self) {
        return nil;
    }

    [self setWindow:window];
    [self _setLocationInWindow:point resetPrevious:YES];
    [self setView:view];
    [self setPhase:UITouchPhaseBegan];
    [self _setIsTapToClick:NO];
    [self setTimestamp:NSProcessInfo.processInfo.systemUptime];
    SEL gestureViewSelector = NSSelectorFromString(@"setGestureView:");
    if ([self respondsToSelector:gestureViewSelector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gestureViewSelector, view);
    }
    return self;
}

- (void)setLocationInWindow:(CGPoint)location {
    [self setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [self _setLocationInWindow:location resetPrevious:NO];
}

- (void)setPhaseAndUpdateTimestamp:(UITouchPhase)phase {
    [self setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [self setPhase:phase];
}

@end

static NSMutableDictionary<NSNumber *, UITouch *> *KSBallActiveTouches;
static NSMutableArray<UITouch *> *KSBallLivingTouches;
static NSMutableArray<UITouch *> *KSBallTouchesToRemove;
static NSMutableArray<UITouch *> *KSBallTouchesToStationarify;
static NSArray<UITouch *> *KSBallSafeTouches;
static CFRunLoopSourceRef KSBallTouchEventSource;
static void *KSBallIOKitHandle;
static KSBallCreateDigitizerEventFunction KSBallCreateDigitizerEvent;
static KSBallCreateFingerEventFunction KSBallCreateFingerEvent;
static KSBallAppendHIDEventFunction KSBallAppendHIDEvent;
static KSBallSetHIDIntegerFunction KSBallSetHIDInteger;

static void KSBallLoadHIDEventFunctions(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        KSBallIOKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        KSBallCreateDigitizerEvent = (KSBallCreateDigitizerEventFunction)dlsym(KSBallIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        KSBallCreateFingerEvent = (KSBallCreateFingerEventFunction)dlsym(KSBallIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEventWithQuality");
        KSBallAppendHIDEvent = (KSBallAppendHIDEventFunction)dlsym(KSBallIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventAppendEvent");
        KSBallSetHIDInteger = (KSBallSetHIDIntegerFunction)dlsym(KSBallIOKitHandle ?: RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    });
}

static KSBallIOHIDEventRef KSBallCreateHIDEventForTouch(UITouch *touch) {
    KSBallLoadHIDEventFunctions();
    if (!KSBallCreateDigitizerEvent || !KSBallCreateFingerEvent || !KSBallAppendHIDEvent || !KSBallSetHIDInteger) {
        return NULL;
    }

    uint64_t absoluteTime = mach_absolute_time();
    KSBallAbsoluteTime timestamp;
    timestamp.hi = (uint32_t)(absoluteTime >> 32);
    timestamp.lo = (uint32_t)absoluteTime;
    KSBallIOHIDEventRef handEvent = KSBallCreateDigitizerEvent(kCFAllocatorDefault, timestamp, 3, 0, 0, 1 << 1, 0, 0, 0, 0, 0, 0, false, true, 0);
    if (!handEvent) {
        return NULL;
    }

    const uint32_t digitizerIsDisplayIntegratedField = (11 << 16) + 25;
    KSBallSetHIDInteger(handEvent, digitizerIsDisplayIntegratedField, 1);
    CGPoint location = [touch locationInView:touch.window];
    KSBallIOHIDEventRef fingerEvent = KSBallCreateFingerEvent(kCFAllocatorDefault, timestamp, 1, 2, (1 << 0) | (1 << 1), location.x, location.y, 0, 0, 0, 5, 5, 1, 1, 1, true, true, 0);
    if (!fingerEvent) {
        CFRelease(handEvent);
        return NULL;
    }
    KSBallSetHIDInteger(fingerEvent, digitizerIsDisplayIntegratedField, 1);
    KSBallAppendHIDEvent(handEvent, fingerEvent);
    CFRelease(fingerEvent);
    return handEvent;
}

static void KSBallTouchEventSourceCallback(void *context) {
    UIApplication *application = UIApplication.sharedApplication;
    UIEvent *event = [application _touchesEvent];
    if (!event) {
        return;
    }

    // 已结束的触摸与刚开始的触摸在下一次 HID 事件到达时再处理，确保 UIKit 至少完整看到一次每个阶段。
    [event _clearTouches];
    NSArray<UITouch *> *touches = KSBallSafeTouches;
    for (UITouch *touch in touches) {
        switch (touch.phase) {
            case UITouchPhaseEnded:
            case UITouchPhaseCancelled:
                [KSBallTouchesToRemove addObject:touch];
                break;
            case UITouchPhaseBegan:
                [KSBallTouchesToStationarify addObject:touch];
                break;
            default:
                break;
        }
        [event _addTouch:touch forDelayedDelivery:NO];
    }
    [application sendEvent:event];

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            hasActiveTouch = YES;
            break;
        }
    }
    if (!hasActiveTouch) {
        for (UIWindow *window in application.windows) {
            if ([window isKindOfClass:PassthroughHUDWindow.class] && window.isKeyWindow) {
                [window resignKeyWindow];
                break;
            }
        }
    }
}

static void KSBallReceiveTouch(NSInteger identifier, CGPoint location, UITouchPhase phase, UIWindow *window, UIView *view) {
    BOOL touchesChanged = NO;
    for (UITouch *touch in KSBallTouchesToRemove) {
        [KSBallLivingTouches removeObjectIdenticalTo:touch];
        for (NSNumber *touchKey in KSBallActiveTouches.allKeys) {
            if (KSBallActiveTouches[touchKey] == touch) {
                [KSBallActiveTouches removeObjectForKey:touchKey];
            }
        }
        touchesChanged = YES;
    }
    [KSBallTouchesToRemove removeAllObjects];
    for (UITouch *touch in KSBallTouchesToStationarify) {
        if (touch.phase == UITouchPhaseBegan) {
            [touch setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
        }
    }
    [KSBallTouchesToStationarify removeAllObjects];

    NSNumber *touchKey = @(identifier);
    UITouch *touch = KSBallActiveTouches[touchKey];
    BOOL living = touch && [KSBallLivingTouches indexOfObjectIdenticalTo:touch] != NSNotFound;
    if (!living) {
        // 只在按下时建立新触摸；从 HUD 外滑入的手指不应在悬浮条上凭空产生点击。
        if (phase != UITouchPhaseBegan || !view) {
            return;
        }
        touch = [[UITouch alloc] initKSBallAtPoint:location inWindow:window onView:view];
        if (!touch) {
            return;
        }
        KSBallIOHIDEventRef hidEvent = KSBallCreateHIDEventForTouch(touch);
        if (hidEvent) {
            [touch _setHidEvent:hidEvent];
            CFRelease(hidEvent);
        }
        [KSBallLivingTouches addObject:touch];
        KSBallActiveTouches[touchKey] = touch;
        touchesChanged = YES;
    } else {
        // Began 尚未派发时丢弃移动事件，否则 UIKit 永远收不到 Began，手势识别会失效。
        if (touch.phase == UITouchPhaseBegan && phase == UITouchPhaseMoved) {
            return;
        }
        [touch setLocationInWindow:location];
    }
    [touch setPhaseAndUpdateTimestamp:phase];

    if (touchesChanged) {
        KSBallSafeTouches = [KSBallLivingTouches copy];
    }
    if (phase == UITouchPhaseBegan) {
        [window makeKeyWindow];
    }
    if (KSBallTouchEventSource) {
        CFRunLoopSourceSignal(KSBallTouchEventSource);
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
}

static void KSBallHandleHIDEvent(void *target, void *refcon, KSBallIOHIDServiceRef service, KSBallIOHIDEventRef event) {
    @autoreleasepool {
        UIApplication *application = UIApplication.sharedApplication;
        if (!event) {
            return;
        }

        NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
        if (version.majorVersion < 15 || (version.majorVersion == 15 && version.minorVersion == 0)) {
            SEL enqueueSelector = NSSelectorFromString(@"_enqueueHIDEvent:");
            if ([application respondsToSelector:enqueueSelector]) {
                ((void (*)(id, SEL, KSBallIOHIDEventRef))objc_msgSend)(application, enqueueSelector, event);
            }
        }

        BOOL useAXRepresentation = version.majorVersion >= 15;
        if (version.majorVersion == 15 && version.minorVersion == 0 && version.patchVersion == 0) {
            struct utsname systemInfo;
            uname(&systemInfo);
            NSString *deviceModel = [NSString stringWithUTF8String:systemInfo.machine];
            useAXRepresentation = [deviceModel hasPrefix:@"iPhone13,"] || [deviceModel hasPrefix:@"iPhone14,"];
        }
        if (!useAXRepresentation) {
            return;
        }

        static Class representationClass;
        static dispatch_once_t representationToken;
        dispatch_once(&representationToken, ^{
            [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
            representationClass = objc_getClass("AXEventRepresentation");
        });
        SEL representationSelector = NSSelectorFromString(@"representationWithHIDEvent:hidStreamIdentifier:");
        if (!representationClass || ![representationClass respondsToSelector:representationSelector]) {
            return;
        }
        id representation = ((id (*)(id, SEL, KSBallIOHIDEventRef, id))objc_msgSend)(representationClass, representationSelector, event, @"UIApplicationEvents");
        if (!representation) {
            return;
        }

        SEL locationSelector = NSSelectorFromString(@"location");
        SEL handInfoSelector = NSSelectorFromString(@"handInfo");
        CGPoint location = ((CGPoint (*)(id, SEL))objc_msgSend)(representation, locationSelector);
        id handInfo = ((id (*)(id, SEL))objc_msgSend)(representation, handInfoSelector);
        NSArray *paths = ((id (*)(id, SEL))objc_msgSend)(handInfo, NSSelectorFromString(@"paths"));
        id path = paths.firstObject;
        NSInteger identifier = ((unsigned char (*)(id, SEL))objc_msgSend)(path, NSSelectorFromString(@"pathIdentity"));
        if (identifier <= 0) {
            return;
        }

        UITouchPhase phase = UITouchPhaseEnded;
        if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isTouchDown"))) {
            phase = UITouchPhaseBegan;
        } else if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isMove"))) {
            phase = UITouchPhaseMoved;
        } else if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isCancel"))) {
            phase = UITouchPhaseCancelled;
        } else if (((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isLift")) ||
                   ((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isInRange")) ||
                   ((BOOL (*)(id, SEL))objc_msgSend)(representation, NSSelectorFromString(@"isInRangeLift"))) {
            phase = UITouchPhaseEnded;
        } else {
            return;
        }

        identifier = MIN(MAX(identifier, 1), 98);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *window = nil;
            for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
                if ([candidate isKindOfClass:PassthroughHUDWindow.class] && !candidate.hidden) {
                    window = candidate;
                    break;
                }
            }
            if (!window) {
                return;
            }
            UIView *view = [window hitTest:location withEvent:nil];
            KSBallReceiveTouch(identifier, location, phase, window, view);
        });
    }
}

BOOL KSBallRegisterHUDEventCallback(void) {
    if (![NSThread isMainThread]) {
        return NO;
    }

    static BOOL registered;
    if (registered) {
        return YES;
    }

    KSBallActiveTouches = [NSMutableDictionary dictionary];
    KSBallLivingTouches = [NSMutableArray array];
    KSBallTouchesToRemove = [NSMutableArray array];
    KSBallTouchesToStationarify = [NSMutableArray array];
    KSBallSafeTouches = @[];
    CFRunLoopSourceContext context = {0};
    context.perform = KSBallTouchEventSourceCallback;
    KSBallTouchEventSource = CFRunLoopSourceCreate(kCFAllocatorDefault, -2, &context);
    if (!KSBallTouchEventSource) {
        return NO;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), KSBallTouchEventSource, kCFRunLoopCommonModes);

    void *backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    KSBallRegisterHIDEventCallbackFunction registerCallback = (KSBallRegisterHIDEventCallbackFunction)dlsym(backBoardServices, "BKSHIDEventRegisterEventCallback");
    if (!registerCallback) {
        return NO;
    }
    registerCallback(KSBallHandleHIDEvent);

    void *graphicsServices = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY | RTLD_GLOBAL);
    typedef void (*KSBallGSEventInitializeFunction)(Boolean);
    typedef void (*KSBallGSEventPushRunLoopModeFunction)(CFStringRef);
    KSBallGSEventInitializeFunction initializeEvents = (KSBallGSEventInitializeFunction)dlsym(graphicsServices, "GSEventInitialize");
    KSBallGSEventPushRunLoopModeFunction pushRunLoopMode = (KSBallGSEventPushRunLoopModeFunction)dlsym(graphicsServices, "GSEventPushRunLoopMode");
    if (initializeEvents) {
        initializeEvents(false);
    }
    if (pushRunLoopMode) {
        pushRunLoopMode(kCFRunLoopDefaultMode);
    }

    registered = YES;
    return YES;
}
