# KSBall

KSBall 是一个仅面向 TrollStore 的 iPhone 全局悬浮快捷启动器。启动 KSBall 后，它会创建独立的 HUD 场景；短按悬浮球展开最多 16 个应用入口，长按进入配置页。

## 能力边界

- 支持 iOS 15 起的 UIKit 场景实现；实际安装前应确认设备系统受当前 TrollStore 版本支持。
- 全局 HUD 依赖 FrontBoard 私有接口和 TrollStore 权限，不可通过 App Store 发布。
- 设备重启或用户在应用切换器中强制结束 KSBall 后，需要从主屏重新打开一次。
- 默认仅列出用户应用和 TrollStore 应用；可手动输入 Bundle ID 添加未枚举到的入口。

## 构建与安装

1. 在 macOS 上使用 Xcode 打开 `KSBall.xcodeproj`，选择 `KSBall` scheme。
2. 用 iPhoneOS SDK 构建 Release 产物。普通开发签名不应嵌入私有 entitlement。
3. 使用你的 TrollStore 签名流程为最终 `.app` 注入 `KSBall/KSBall.entitlements`，再打包 IPA 并在 TrollStore 安装。
4. 首次打开后，在 KSBall 配置页添加快捷应用；拖动悬浮球可保存位置。

## 测试

`KSBallTests` 覆盖设置 JSON 回退、16 项上限、排序持久化、扇形几何和桥接层 mock。私有 FrontBoard 场景与 LaunchServices 启动行为必须在 TrollStore 真机上验证。
