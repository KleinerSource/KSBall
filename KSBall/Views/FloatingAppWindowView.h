#import <UIKit/UIKit.h>
#import "KSBallSettings.h"

NS_ASSUME_NONNULL_BEGIN

@class FloatingAppWindowView;

@protocol FloatingAppWindowViewDelegate <NSObject>
- (void)floatingAppWindowViewDidRequestClose:(FloatingAppWindowView *)windowView;
- (void)floatingAppWindowViewDidRequestMinimize:(FloatingAppWindowView *)windowView;
- (void)floatingAppWindowViewDidRequestFullScreen:(FloatingAppWindowView *)windowView;
- (void)floatingAppWindowViewDidRequestRestore:(FloatingAppWindowView *)windowView;
- (void)floatingAppWindowViewDidRequestHideDock:(FloatingAppWindowView *)windowView;
/// 开始拖动、缩放或点到窗口外框时回调，用于把窗口移到最前。
- (void)floatingAppWindowViewDidBeginInteraction:(FloatingAppWindowView *)windowView;
/// 拖动或缩放结束后回调，由管理器决定收进收纳区还是收回可见范围。
- (void)floatingAppWindowViewDidEndMoving:(FloatingAppWindowView *)windowView;
@end

/// 悬浮窗外框：顶部标题条（关闭 / 收起 / 全屏，拖动移动），右下角缩放手柄，
/// 内容区按窗口宽度等比缩放显示被托管应用的全屏画面。收起后只保留实时缩略图与应用图标角标。
@interface FloatingAppWindowView : UIView

@property (nonatomic, weak, nullable) id<FloatingAppWindowViewDelegate> delegate;
@property (nonatomic, readonly) CGSize screenSize;
@property (nonatomic, getter=isMinimized) BOOL minimized;
/// 收起时所在的收纳区一侧，决定缩略图向哪个方向甩出可隐藏整个边栏。
@property (nonatomic) KSBallEdge minimizedEdge;

- (instancetype)initWithDisplayName:(NSString *)displayName icon:(nullable UIImage *)icon screenSize:(CGSize)screenSize;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
/// 场景就绪后放入应用画面；传 nil 移除画面并重新显示占位。
- (void)setPresentationView:(nullable UIView *)presentationView;
/// 在占位区显示状态文字（启动失败、应用已退出等），并停止加载指示。
- (void)showStatusMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
