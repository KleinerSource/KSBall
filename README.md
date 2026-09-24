# KSBall

KSBall 是一个仅面向 TrollStore 的 iPhone 全局快捷启动器。启动 KSBall 后，它会以 UIKit 插件模式运行独立 HUD 子进程，并通过 SpringBoard accessibility window hosting 显示一条紧贴屏幕边缘的悬浮条；点按或向内滑动悬浮条展开最多 16 个应用的扇形菜单，滑到图标上松手即可启动，长按后拖动可调整位置，长按不移动则进入配置页。

## 能力边界

- 支持 iOS 15 起的系统；实际安装前应确认设备系统受当前 TrollStore 版本支持。
- 全局 HUD 依赖 SpringBoard accessibility window hosting 私有接口和 TrollStore 权限，不可通过 App Store 发布。HUD 子进程沿用 TrollSpeed 的插件模式启动方式，不使用 UIScene。
- 设备重启、注销 SpringBoard（respring）或用户在应用切换器中强制结束 KSBall 后，需要从主屏重新打开一次。
- HUD 窗口固定为竖屏坐标系，横屏时悬浮条仍位于竖屏方向的左右边缘。
- 默认仅列出用户应用和 TrollStore 应用；可手动输入 Bundle ID 添加未枚举到的入口。

## 构建与安装

1. 在 macOS 上使用 Xcode 打开 `KSBall.xcodeproj`，选择 `KSBall` scheme。
2. 用 iPhoneOS SDK 构建 Release 产物。普通开发签名不应嵌入私有 entitlement。
3. 使用你的 TrollStore 签名流程为最终 `.app` 注入 `KSBall/KSBall.entitlements`，再打包 IPA 并在 TrollStore 安装。
4. 首次打开后，在 KSBall 配置页添加快捷应用；点按悬浮条可展开或收起菜单，向内滑动并在图标上松手可直接启动，长按后拖动可保存位置，长按不移动可回到配置页。

## 测试

`KSBallTests` 覆盖设置 JSON 回退、16 项上限、排序持久化、扇形几何和桥接层 mock。SpringBoard 窗口注册与 LaunchServices 启动行为必须在 TrollStore 真机上验证。

## GitHub Actions

推送、拉取请求和手动触发都会运行 `.github/workflows/build-ios.yml`。工作流使用 macOS runner 构建未签名的 TrollStore `.tipa`，并上传 `.tipa`、SHA-256 和 `xcodebuild.log`；最终 TrollStore 签名仍在下载工件后执行。

当前处于测试阶段：每次推送到任意分支都会创建或更新固定的 `testing` 预发布，并覆盖其中的 `.tipa`、SHA-256 和构建日志。拉取请求与手动运行仅产出 Actions 工件，不覆盖测试 Release。
